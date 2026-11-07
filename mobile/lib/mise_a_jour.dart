// Mises à jour de l'application, toutes automatiques :
// - nouvelle APK publiée sur GitHub (Releases) : téléchargée d'office, puis installée par Android quand
//   l'utilisateur quitte l'application (sans confirmation sur Android 12 et plus, quand Android l'accepte).
//   Application fermée, la tâche de fond VerificationMiseAJour.kt fait de même et dépose l'APK au même endroit ;
// - correctif Shorebird : le code Dart est remplacé au prochain lancement, sans réinstaller.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:http/http.dart' as http;
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shorebird_code_push/shorebird_code_push.dart';

import 'file_attente.dart';
import 'journal.dart';

/// Numéro de version Android (versionCode) de cette APK, fixé par le CI ; 0 pour une version locale.
const numeroVersion = int.fromEnvironment('BUILD', defaultValue: 0);

/// « 1.1.0 », fixé par le CI.
const nomVersion = String.fromEnvironment('NOM_VERSION', defaultValue: '');

/// Fiche de la dernière version publiée, toujours à la même adresse (dernière Release GitHub).
const adresseFiche = String.fromEnvironment(
  'URL_MISE_A_JOUR',
  defaultValue: 'https://github.com/Dominique-BRIA/cetic-mezesse-mobile/releases/latest/download/version.json',
);

/// Fiche version.json écrite par le CI à chaque nouvelle APK.
class VersionPubliee {
  const VersionPubliee({required this.numero, required this.nom, required this.url, this.taille = 0, this.minimum = 0, this.notes = ''});

  final int numero;
  final String nom;
  final String url;

  /// Taille de l'APK en octets ; 0 si inconnue.
  final int taille;

  /// Numéro en dessous duquel l'application refuse de servir : la mise à jour devient obligatoire.
  final int minimum;
  final String notes;

  /// null si la fiche est incomplète : on ne propose rien plutôt qu'une mise à jour douteuse.
  static VersionPubliee? depuisJson(Object? j) {
    if (j is! Map) return null;
    final numero = j['numero'];
    final url = j['url'];
    if (numero is! int || url is! String || !url.startsWith('https://')) return null;
    return VersionPubliee(
      numero: numero,
      nom: j['nom'] is String ? j['nom'] as String : '$numero',
      url: url,
      taille: j['taille'] is int ? j['taille'] as int : 0,
      minimum: j['minimum'] is int ? j['minimum'] as int : 0,
      notes: j['notes'] is String ? j['notes'] as String : '',
    );
  }

  /// Une version locale (numéro 0) ne se compare à rien.
  bool plusRecenteQue(int actuel) => actuel > 0 && numero > actuel;

  bool exigeeSur(int actuel) => actuel > 0 && actuel < minimum;

  /// « 18,4 Mo ».
  String get tailleLisible => taille <= 0 ? '' : '${(taille / 1048576).toStringAsFixed(1).replaceAll('.', ',')} Mo';
}

/// attente → telechargement → prete (APK complète sur le téléphone) → installation.
enum EtapeMiseAJour { attente, telechargement, prete, installation }

class _Echec implements Exception {
  _Echec(this.message);
  final String message;

  @override
  String toString() => message;
}

class MiseAJour extends ChangeNotifier with WidgetsBindingObserver {
  MiseAJour._();
  static final MiseAJour i = MiseAJour._();

  /// Installation native (android/app/src/main/kotlin/…/MainActivity.kt).
  static const _canal = MethodChannel('cetic/installation');

  // Créé seulement au premier usage : hors APK Shorebird (flutter run, tests), il ne fait rien.
  late final ShorebirdUpdater _shorebird = ShorebirdUpdater();
  Timer? _minuterie;

  /// Numéro de cette APK ; modifiable seulement par les tests, où il vaut 0 sinon.
  @visibleForTesting
  int numeroInstalle = numeroVersion;

  VersionPubliee? publiee;
  EtapeMiseAJour etape = EtapeMiseAJour.attente;

  /// De 0 à 1 pendant le téléchargement.
  double? progression;

  /// Dernier échec du téléchargement ou de l'installation, affiché dans le bandeau.
  String? erreur;

  /// APK téléchargée et complète, prête à installer.
  @visibleForTesting
  File? apk;

  /// Dernière installation lancée, et si c'était en arrière-plan (sans que l'utilisateur la voie).
  DateTime? _dernierEssai;
  bool _essaiEnArrierePlan = false;

  /// Correctif Shorebird téléchargé : il s'applique au prochain lancement.
  bool correctifPret = false;
  bool correctifVu = false;

  bool get disponible => publiee?.plusRecenteQue(numeroInstalle) ?? false;
  bool get obligatoire => publiee?.exigeeSur(numeroInstalle) ?? false;

  /// Bandeau d'information : rien à décider, la mise à jour suit son cours toute seule.
  bool get bandeauVisible => !obligatoire && (disponible || (correctifPret && !correctifVu));

  /// Au démarrage puis toutes les 6 heures ; ne bloque jamais l'interface.
  void demarrer() {
    WidgetsBinding.instance.addObserver(this);
    unawaited(verifier());
    _minuterie ??= Timer.periodic(const Duration(hours: 6), (_) => verifier());
  }

  /// Vérifie, puis télécharge d'office la nouvelle version.
  Future<void> verifier() async {
    await Future.wait([_verifierApk(), _verifierCorrectif()]);
    if (disponible && etape == EtapeMiseAJour.attente) unawaited(telecharger());
  }

  Future<void> _verifierApk() async {
    if (!Platform.isAndroid || numeroInstalle == 0) return;
    try {
      final r = await http.get(Uri.parse(adresseFiche)).timeout(const Duration(seconds: 20));
      if (r.statusCode != 200) return;
      final v = VersionPubliee.depuisJson(jsonDecode(utf8.decode(r.bodyBytes)));
      if (v == null) return;
      publiee = v;
      noter('mise à jour : publiée ${v.nom} (${v.numero}), installée $nomVersion ($numeroInstalle)');
      notifyListeners();
    } catch (e) {
      // Pas de réseau ou GitHub injoignable : on réessaiera plus tard, sans rien afficher.
      noter('mise à jour : vérification impossible ($e)');
    }
  }

  Future<void> _verifierCorrectif() async {
    try {
      if (!_shorebird.isAvailable) return;
      var statut = await _shorebird.checkForUpdate();
      if (statut == UpdateStatus.outdated) {
        await _shorebird.update();
        statut = await _shorebird.checkForUpdate();
      }
      if (statut == UpdateStatus.restartRequired && !correctifPret) {
        correctifPret = true;
        noter('correctif : téléchargé, appliqué au prochain lancement');
        notifyListeners();
      }
    } catch (e) {
      noter('correctif : $e');
    }
  }

  void masquerCorrectif() {
    correctifVu = true;
    notifyListeners();
  }

  /// Pour les tests et les captures d'écran : redessine le bandeau après un réglage direct.
  @visibleForTesting
  void signaler() => notifyListeners();

  /// Remet l'état de départ (tests et captures d'écran).
  @visibleForTesting
  void reinitialiser() {
    publiee = null;
    etape = EtapeMiseAJour.attente;
    progression = null;
    erreur = null;
    apk = null;
    _dernierEssai = null;
    _essaiEnArrierePlan = false;
    correctifPret = false;
    correctifVu = false;
  }

  /// L'installation se fait quand l'utilisateur quitte l'application : elle ne la ferme pas en pleine
  /// saisie. Si Android a demandé une confirmation qu'il n'a pas pu afficher en arrière-plan, elle est
  /// relancée au retour au premier plan, une fois.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (etape != EtapeMiseAJour.prete) return;
    final recent = _dernierEssai != null && DateTime.now().difference(_dernierEssai!) < const Duration(minutes: 2);
    if ((state == AppLifecycleState.paused || state == AppLifecycleState.hidden) && !recent) {
      unawaited(installer(arrierePlan: true));
    } else if (state == AppLifecycleState.resumed && _essaiEnArrierePlan) {
      unawaited(installer());
    }
  }

  /// Télécharge l'APK de la version publiée. Renvoie le message d'erreur, ou null.
  Future<String?> telecharger() async {
    final v = publiee;
    if (v == null || etape != EtapeMiseAJour.attente) return null;
    etape = EtapeMiseAJour.telechargement;
    progression = 0;
    erreur = null;
    notifyListeners();
    final client = http.Client();
    try {
      final dossier = await getTemporaryDirectory();
      final fichier = File('${dossier.path}/cetic-mezesse-${v.numero}.apk');
      // Les APK des versions précédentes ne servent plus.
      await for (final f in dossier.list()) {
        if (f is File && f.path.contains('cetic-mezesse-') && f.path.endsWith('.apk') && f.path != fichier.path) {
          await f.delete();
        }
      }
      final dejaLa = v.taille > 0 && await fichier.exists() && await fichier.length() == v.taille;
      if (!dejaLa) await _telecharger(client, v, fichier);
      apk = fichier;
      etape = EtapeMiseAJour.prete;
      noter('mise à jour : ${v.nom} téléchargée');
      notifyListeners();
      // Version trop ancienne pour le serveur : installation tout de suite.
      if (obligatoire) unawaited(installer());
      return null;
    } catch (e) {
      etape = EtapeMiseAJour.attente;
      erreur = e is TimeoutException ? 'le réseau est trop lent, nouvel essai plus tard' : '$e';
      noter('mise à jour : téléchargement interrompu ($erreur)');
      return 'Mise à jour impossible : $erreur';
    } finally {
      client.close();
      progression = null;
      notifyListeners();
    }
  }

  /// Installe l'APK téléchargée. Les notes en attente partent d'abord si le réseau le permet ; celles
  /// qui restent sont gardées, une mise à jour ne vide pas le téléphone. Renvoie le message d'erreur, ou null.
  Future<String?> installer({bool arrierePlan = false}) async {
    final fichier = apk;
    if (fichier == null || etape != EtapeMiseAJour.prete) return null;
    etape = EtapeMiseAJour.installation;
    erreur = null;
    _dernierEssai = DateTime.now();
    _essaiEnArrierePlan = arrierePlan;
    notifyListeners();
    try {
      if (FileAttente.i.envois.isNotEmpty) await FileAttente.i.synchroniser();
      noter('mise à jour : installation${arrierePlan ? ' en arrière-plan' : ''}');
      try {
        await _canal.invokeMethod<bool>('installer', {'chemin': fichier.path});
      } on MissingPluginException {
        // APK sans le canal natif : l'installateur d'Android, comme avant.
        final ouverture = await OpenFilex.open(fichier.path, type: 'application/vnd.android.package-archive');
        if (ouverture.type != ResultType.done) throw _Echec(ouverture.message);
      }
      return null;
    } catch (e) {
      erreur = e is PlatformException ? (e.message ?? e.code) : '$e';
      noter('mise à jour : installation impossible ($erreur)');
      return 'Mise à jour impossible : $erreur';
    } finally {
      // Installation réussie : Android remplace l'application et ce code ne s'exécute plus. Sinon,
      // l'APK reste prête pour le prochain essai.
      etape = EtapeMiseAJour.prete;
      notifyListeners();
    }
  }

  Future<void> _telecharger(http.Client client, VersionPubliee v, File fichier) async {
    final r = await client.send(http.Request('GET', Uri.parse(v.url))).timeout(const Duration(seconds: 30));
    if (r.statusCode != 200) throw _Echec('le serveur a répondu ${r.statusCode}');
    final total = r.contentLength ?? v.taille;
    final partiel = File('${fichier.path}.part');
    final sortie = partiel.openWrite();
    var recus = 0;
    try {
      await for (final morceau in r.stream.timeout(const Duration(seconds: 60))) {
        sortie.add(morceau);
        recus += morceau.length;
        if (total > 0) {
          progression = recus / total;
          notifyListeners();
        }
      }
    } finally {
      await sortie.close();
    }
    if (v.taille > 0 && recus != v.taille) throw _Echec('fichier incomplet ($recus octets sur ${v.taille})');
    await partiel.rename(fichier.path);
  }
}
