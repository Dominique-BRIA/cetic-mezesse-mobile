// État de l'application : utilisateur connecté, années scolaires, thème.
import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';

import 'api.dart';
import 'file_attente.dart';
import 'journal.dart';

class Etat extends ChangeNotifier {
  Etat._();
  static final Etat i = Etat._();

  Map<String, dynamic>? utilisateur;
  List<Map<String, dynamic>> annees = [];
  ThemeMode theme = ThemeMode.light;
  bool demarrage = true;

  String get role => utilisateur?['role'] as String? ?? '';
  bool a(List<String> roles) => roles.contains(role);
  bool get estProf => role == 'PROFESSEUR';
  bool get estSG => role == 'SURVEILLANT_GENERAL';
  bool get estProviseur => role == 'PROVISEUR';

  Map<String, dynamic>? get annee {
    for (final a in annees) {
      if (a['id'] == Api.i.anneeId) return a;
    }
    for (final a in annees) {
      if (a['active'] == true) return a;
    }
    return annees.isEmpty ? null : annees.first;
  }

  List<Map<String, dynamic>> get sequences =>
      ((annee?['sequences'] as List?) ?? []).cast<Map<String, dynamic>>();

  Map<String, dynamic>? get sequenceOuverte {
    for (final s in sequences) {
      if (s['saisieOuverte'] == true) return s;
    }
    return null;
  }

  /// Aboutit toujours : une donnée locale illisible ne doit pas laisser l'écran d'ouverture
  /// tourner sans fin. Dans le pire des cas, on revient à l'écran de connexion.
  Future<void> demarrer() async {
    noter('démarrage : début');
    try {
      await Api.i.initialiser();
      noter('démarrage : réglages lus (session ${Api.i.jeton != null ? 'oui' : 'non'}, profil gardé ${Api.i.prefs.containsKey('profil') ? 'oui' : 'non'}, file ${Api.i.prefs.containsKey('file-attente') ? 'oui' : 'non'})');
      Api.i.surSessionExpiree = deconnecter;
      Api.i.surRetourReseau = () {
        FileAttente.i.synchroniser();
        _rafraichir();
      };
      theme = switch (Api.i.prefs.getString('theme')) {
        'dark' => ThemeMode.dark,
        'light' => ThemeMode.light,
        _ => ThemeMode.light,
      };
      FileAttente.i.charger();
      noter('démarrage : file d’attente chargée (${FileAttente.i.envois.length} envoi(s))');
      // Jamais d'attente du serveur à l'ouverture : la session reprend avec le profil et les
      // années gardés sur le téléphone, puis se met à jour en arrière-plan.
      if (Api.i.jeton != null) {
        final profil = _profilGarde();
        if (profil != null) {
          utilisateur = profil;
          final copieAnnees = Api.i.lireCache('/annees', annee: false);
          if (copieAnnees is List) annees = copieAnnees.cast<Map<String, dynamic>>();
        } else {
          // Session ouverte par une version qui ne gardait pas le profil : on redemande la connexion.
          await deconnecter();
        }
      }
    } catch (e, pile) {
      noter('ERREUR démarrage : $e');
      debugPrint('Démarrage interrompu : $e\n$pile');
      utilisateur = null;
    } finally {
      demarrage = false;
      noter('démarrage : fini (${utilisateur == null ? 'connexion' : 'session reprise'})');
      notifyListeners();
    }
    if (utilisateur != null) unawaited(_rafraichir());
  }

  Map<String, dynamic>? _profilGarde() {
    try {
      final brut = Api.i.prefs.getString('profil');
      if (brut != null) return (jsonDecode(brut) as Map).cast<String, dynamic>();
      final copie = Api.i.lireCache('/auth/moi', annee: false);
      return copie is Map ? copie.cast<String, dynamic>() : null;
    } catch (_) {
      return null; // copie illisible : la connexion sera redemandée
    }
  }

  Future<void> _garderProfil() async {
    if (utilisateur != null) await Api.i.prefs.setString('profil', jsonEncode(utilisateur));
  }

  /// Met à jour le profil et les années depuis le serveur, sans bloquer l'interface.
  Future<void> _rafraichir() async {
    if (Api.i.jeton == null) return;
    try {
      utilisateur = (await Api.i.get('/auth/moi', annee: false) as Map).cast<String, dynamic>();
      await _garderProfil();
      await chargerAnnees();
      FileAttente.i.synchroniser();
      notifyListeners();
      unawaited(prechargerEcrans());
    } on ErreurApi {
      // hors ligne : on garde la copie ; une session expirée est traitée par surSessionExpiree
    }
  }

  Future<void> chargerAnnees() async {
    annees = (await Api.i.get('/annees', annee: false) as List).cast<Map<String, dynamic>>();
    final choisie = annee;
    if (choisie != null && choisie['id'] != Api.i.anneeId) {
      Api.i.anneeId = choisie['id'] as String;
      await Api.i.prefs.setString('annee', Api.i.anneeId!);
    }
    notifyListeners();
  }

  /// Sans « rester connecté », le jeton n'est gardé qu'en mémoire : fermer l'application déconnecte.
  Future<void> connecter(String jeton, Map<String, dynamic> u, {bool memoriser = true}) async {
    Api.i.jeton = jeton;
    if (memoriser) {
      await Api.i.prefs.setString('jeton', jeton);
    } else {
      await Api.i.prefs.remove('jeton');
    }
    utilisateur = u;
    await _garderProfil();
    notifyListeners();
    // Les années arrivent en arrière-plan : l'accueil s'ouvre sans les attendre.
    unawaited(chargerAnnees().then((_) => prechargerEcrans()).catchError((_) {}));
  }

  /// Données des écrans du menu, avec leurs filtres par défaut, mises en réserve en arrière-plan :
  /// chaque écran s'ouvre ensuite aussitôt avec cette copie, puis se met à jour.
  Future<void> prechargerEcrans() {
    final direction = estProviseur || estSG;
    return Api.i.precharger([
      ('/notes/avancement', true),
      if (estProf) ('/matieres', true),
      if (direction) ...[
        ('/classes', true),
        ('/eleves?classeId=&q=', true),
        ('/statistiques/etablissement?periode=S1', true),
        ('/tableau-honneur?periode=T1', true),
        ('/utilisateurs?role=PROFESSEUR', true),
        ('/groupes', true),
        ('/eleves?statut=RENVOYE', true),
      ],
      if (estProviseur) ('/attestations', false),
    ]);
  }

  /// Profil modifié par l'utilisateur lui-même (écran Mon profil).
  Future<void> majProfil(Map<String, dynamic> u) async {
    utilisateur = u;
    await _garderProfil();
    notifyListeners();
  }

  Future<void> rafraichirProfil() async {
    utilisateur = (await Api.i.get('/auth/moi', annee: false) as Map).cast<String, dynamic>();
    await _garderProfil();
    notifyListeners();
  }

  Future<void> deconnecter() async {
    Api.i.jeton = null;
    await Api.i.prefs.remove('jeton');
    await Api.i.prefs.remove('profil');
    // La copie locale appartient au compte qui se déconnecte.
    for (final k in Api.i.prefs.getKeys().where((k) => k.startsWith('cache:')).toList()) {
      await Api.i.prefs.remove(k);
    }
    utilisateur = null;
    notifyListeners();
  }

  Future<void> choisirAnnee(String id) async {
    Api.i.anneeId = id;
    await Api.i.prefs.setString('annee', id);
    notifyListeners();
    unawaited(prechargerEcrans());
  }

  Future<void> basculerTheme(Brightness actuelle) async {
    theme = actuelle == Brightness.dark ? ThemeMode.light : ThemeMode.dark;
    await Api.i.prefs.setString('theme', theme == ThemeMode.dark ? 'dark' : 'light');
    notifyListeners();
  }
}
