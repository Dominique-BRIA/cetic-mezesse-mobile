// Mises à jour de l'application, de deux façons :
// - nouvelle APK publiée sur GitHub (Releases) : téléchargée ici, puis installée par Android ;
// - correctif Shorebird : le code Dart est remplacé au prochain lancement, sans réinstaller.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shorebird_code_push/shorebird_code_push.dart';

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

enum EtapeMiseAJour { attente, telechargement, installation }

class _Echec implements Exception {
  _Echec(this.message);
  final String message;

  @override
  String toString() => message;
}

class MiseAJour extends ChangeNotifier {
  MiseAJour._();
  static final MiseAJour i = MiseAJour._();

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

  /// « Plus tard » : le bandeau revient au prochain lancement.
  bool reportee = false;

  /// Correctif Shorebird téléchargé : il s'applique au prochain lancement.
  bool correctifPret = false;
  bool correctifVu = false;

  bool get disponible => publiee?.plusRecenteQue(numeroInstalle) ?? false;
  bool get obligatoire => publiee?.exigeeSur(numeroInstalle) ?? false;
  bool get bandeauVisible => !obligatoire && ((disponible && !reportee) || (correctifPret && !correctifVu));

  /// Au démarrage puis toutes les 6 heures ; ne bloque jamais l'interface.
  void demarrer() {
    unawaited(verifier());
    _minuterie ??= Timer.periodic(const Duration(hours: 6), (_) => verifier());
  }

  Future<void> verifier() => Future.wait([_verifierApk(), _verifierCorrectif()]);

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

  void reporter() {
    reportee = true;
    correctifVu = true;
    notifyListeners();
  }

  /// « Rechercher une mise à jour » dans le menu : le bandeau reporté réapparaît.
  void reafficher() {
    reportee = false;
    correctifVu = false;
    notifyListeners();
  }

  /// Télécharge l'APK puis ouvre l'installateur d'Android. Renvoie le message d'erreur, ou null.
  Future<String?> installer() async {
    final v = publiee;
    if (v == null || etape != EtapeMiseAJour.attente) return null;
    etape = EtapeMiseAJour.telechargement;
    progression = 0;
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
      etape = EtapeMiseAJour.installation;
      notifyListeners();
      final ouverture = await OpenFilex.open(fichier.path, type: 'application/vnd.android.package-archive');
      if (ouverture.type != ResultType.done) throw _Echec(ouverture.message);
      return null;
    } catch (e) {
      final message = e is TimeoutException ? 'le réseau est trop lent, réessayez plus tard' : '$e';
      noter('mise à jour : échec ($message)');
      return 'Mise à jour impossible : $message';
    } finally {
      client.close();
      etape = EtapeMiseAJour.attente;
      progression = null;
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
