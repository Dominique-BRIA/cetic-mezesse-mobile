// Captures d'écran de l'application pour les manuels (docs/img/mobile/), sans lancer l'APK : les vrais
// écrans sont dessinés dans un test, avec les polices d'Android, sur l'API locale et sa démonstration.
//
//   cd mobile
//   flutter test outils/captures_test.dart --dart-define=API_URL=http://localhost:4100/api
//
// Prérequis : l'API locale (cetic-mezesse-backend, port 4100) sur la base de démonstration, et les comptes
// d'amorçage (Directeur 690000001, SG 690000002, Hélène MESSI 691000010).

// ignore_for_file: invalid_use_of_visible_for_testing_member, avoid_print

import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:cetic_mezesse/api.dart';
import 'package:cetic_mezesse/ecrans/connexion.dart';
import 'package:cetic_mezesse/ecrans/coquille.dart';
import 'package:cetic_mezesse/ecrans/eleves.dart';
import 'package:cetic_mezesse/ecrans/notifications.dart';
import 'package:cetic_mezesse/ecrans/organisation.dart';
import 'package:cetic_mezesse/ecrans/profil.dart';
import 'package:cetic_mezesse/etat.dart';
import 'package:cetic_mezesse/main.dart';
import 'package:cetic_mezesse/mise_a_jour.dart';
import 'package:cetic_mezesse/widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

const dossierSortie = '../docs/img/mobile';
final _racine = GlobalKey();

/// Mot de passe des comptes d'amorçage : SEED_MOT_DE_PASSE du .env du backend.
final _motDePasseAmorcage = () {
  final env = File('../../cetic-mezesse-backend/.env');
  final ligne = env.existsSync() ? env.readAsLinesSync().where((l) => l.startsWith('SEED_MOT_DE_PASSE=')).firstOrNull : null;
  return ligne?.split('=').skip(1).join('=').replaceAll('"', '') ?? 'Cetic2026';
}();

class Compte {
  Compte(this.jeton, this.utilisateur);
  final String jeton;
  final Map<String, dynamic> utilisateur;
}

final comptes = <String, Compte>{};

class _VraiReseau extends HttpOverrides {}

Future<void> chargerPolices() async {
  final racine = Platform.environment['FLUTTER_ROOT'] ?? 'C:/flutter';
  final dossier = '$racine/bin/cache/artifacts/material_fonts';
  Future<ByteData> lire(String f) async => ByteData.sublistView(File('$dossier/$f').readAsBytesSync());
  // « FlutterTest » : police des styles sans famille (titre de la barre, boutons), Roboto sur Android.
  for (final famille in ['Roboto', 'FlutterTest']) {
    final roboto = FontLoader(famille);
    for (final f in ['roboto-regular.ttf', 'roboto-medium.ttf', 'roboto-bold.ttf', 'roboto-italic.ttf', 'roboto-light.ttf', 'roboto-black.ttf']) {
      roboto.addFont(lire(f));
    }
    await roboto.load();
  }
  await (FontLoader('MaterialIcons')..addFont(lire('materialicons-regular.otf'))).load();
}

Future<Compte> connecter(String identifiant, String motDePasse) async {
  final r = await http.post(
    Uri.parse('${Api.base}/auth/connexion'),
    headers: {'Content-Type': 'application/json'},
    body: jsonEncode({'identifiant': identifiant, 'motDePasse': motDePasse, 'resterConnecte': false}),
  );
  if (r.statusCode != 200) throw StateError('Connexion $identifiant : ${r.statusCode} ${r.body}');
  final j = jsonDecode(utf8.decode(r.bodyBytes)) as Map<String, dynamic>;
  return Compte(j['jeton'] as String, (j['utilisateur'] as Map).cast<String, dynamic>());
}

/// Laisse les vraies requêtes aboutir et l'écran se dessiner, jusqu'à ce qu'il ne charge plus.
Future<void> attendre(WidgetTester t, {int minimum = 600, int maximum = 8000}) async {
  var ecoule = 0;
  while (ecoule < maximum) {
    await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 150)));
    await t.pump(const Duration(milliseconds: 100));
    ecoule += 150;
    final charge = find.byType(LinearProgressIndicator).evaluate().isNotEmpty ||
        find.byType(CircularProgressIndicator).evaluate().isNotEmpty ||
        find.byType(Chargement).evaluate().isNotEmpty;
    if (ecoule >= minimum && !charge) break;
  }
  // Fin des animations (tiroir, fenêtres) sans attendre les minuteries de l'application.
  for (var i = 0; i < 10; i++) {
    await t.pump(const Duration(milliseconds: 60));
  }
}

Future<void> capturer(WidgetTester t, String nom) async {
  await attendre(t, minimum: 300);
  // Une requête de préchargement échouée en passant ne doit pas laisser le bandeau « Hors connexion ».
  Api.i.horsLigne.value = false;
  await attendre(t, minimum: 300);
  final rendu = _racine.currentContext!.findRenderObject()! as RenderRepaintBoundary;
  final octets = await t.runAsync(() async {
    final image = await rendu.toImage(pixelRatio: 1.5);
    final png = await image.toByteData(format: ui.ImageByteFormat.png);
    return png!.buffer.asUint8List();
  });
  Directory(dossierSortie).createSync(recursive: true);
  File('$dossierSortie/$nom.png').writeAsBytesSync(octets!);

  print('capture : $nom.png');
}

/// Ouvre l'application comme au lancement, avec la session du compte (ou sans session).
Future<void> ouvrir(WidgetTester t, {String? role, String destination = 'accueil'}) async {
  final c = role == null ? null : comptes[role]!;
  SharedPreferences.setMockInitialValues({
    'theme': 'light',
    if (c != null) 'jeton': c.jeton,
    if (c != null) 'profil': jsonEncode(c.utilisateur),
  });
  Etat.i
    ..utilisateur = null
    ..annees = []
    ..demarrage = true;
  destinationCourante.value = destination;
  await t.runAsync(() => Etat.i.demarrer());
  // Les années et leurs séquences, d'habitude chargées en arrière-plan : nécessaires aux listes de choix.
  if (c != null) await t.runAsync(() => Etat.i.chargerAnnees());
  await t.pumpWidget(RepaintBoundary(key: _racine, child: const Application()));
  await attendre(t);
}

/// Fiche d'un élève avec sa photo : le temps que l'image arrive du réseau et se décode.
Future<void> ficheEleve(WidgetTester t) async {
  await pousser(t, FicheEleve(id: (await t.runAsync(eleveAvecPhoto))!));
  await attendre(t, minimum: 3000);
}

/// Ouvre un écran par-dessus la coquille, comme le fait l'application (fiche, profil…).
Future<void> pousser(WidgetTester t, Widget ecran) async {
  Navigator.of(t.element(find.byType(Coquille))).push(MaterialPageRoute<void>(builder: (_) => ecran));
  await attendre(t);
}

Future<void> toucher(WidgetTester t, Finder f) async {
  await t.ensureVisible(f.first);
  await t.pump();
  await t.tap(f.first);
  await attendre(t);
}

/// Choisit une option dans une liste déroulante, repérée par son libellé (« Classe », « Séquence »…).
Future<void> choisir(WidgetTester t, String champ, String option) async {
  final liste = find.ancestor(
    of: find.text(champ),
    matching: find.byWidgetPredicate((w) => w.runtimeType.toString().startsWith('DropdownButtonFormField')),
  );
  await toucher(t, liste);
  await toucher(t, find.textContaining(option).last);
}

Future<dynamic> lire(String role, String chemin) async {
  final r = await http.get(Uri.parse('${Api.base}$chemin'), headers: {'Authorization': 'Bearer ${comptes[role]!.jeton}'});
  return jsonDecode(utf8.decode(r.bodyBytes));
}

/// Un élève de la démonstration qui a une photo (fiche plus parlante), à défaut le premier.
Future<String> eleveAvecPhoto() async {
  final liste = (await lire('SURVEILLANT_GENERAL', '/eleves') as List).cast<Map>();
  final avec = liste.where((i) => (i['eleve'] as Map)['photoCle'] != null);
  return ((avec.isNotEmpty ? avec.first : liste.first)['eleve'] as Map)['id'] as String;
}

/// Une capture : ouvre l'application avec le compte, joue les gestes, enregistre l'image.
void ecran(String nom, {String? role, String destination = 'accueil', Future<void> Function(WidgetTester t)? gestes}) {
  testWidgets(nom, (t) async {
    debugDisableShadows = false;
    try {
      await ouvrir(t, role: role, destination: destination);
      if (gestes != null) await gestes(t);
      await capturer(t, nom);
    } finally {
      // Minuteries de l'application (délais d'attente, animations) : écoulées avant la fin du test.
      await t.pumpWidget(const SizedBox());
      await t.pump(const Duration(minutes: 1));
      debugDisableShadows = true;
      MiseAJour.i.reinitialiser();
    }
  });
}

const prof = 'PROFESSEUR';
const directeur = 'PROVISEUR';
const sg = 'SURVEILLANT_GENERAL';

void main() {
  setUpAll(() async {
    HttpOverrides.global = _VraiReseau();
    await chargerPolices();
    comptes[directeur] = await connecter('690000001', _motDePasseAmorcage);
    comptes[sg] = await connecter('690000002', _motDePasseAmorcage);
    comptes[prof] = await connecter('691000010', 'password');
  });

  setUp(() {
    final vue = TestWidgetsFlutterBinding.instance.platformDispatcher.views.first;
    vue.physicalSize = const Size(1080, 2340);
    vue.devicePixelRatio = 2.625;
  });

  // Communs aux trois manuels.
  ecran('connexion');
  ecran('menu', role: prof, gestes: (t) => toucher(t, find.byTooltip('Open navigation menu')));
  ecran('profil', role: prof, gestes: (t) => pousser(t, const EcranProfil()));
  ecran('mot-de-passe', role: prof, gestes: (t) => pousser(t, const EcranMotDePasse()));

  // Professeur.
  ecran('prof-accueil', role: prof);
  ecran('prof-notifications', role: prof, gestes: (t) => toucher(t, find.byType(ClocheNotifications)));
  ecran('prof-saisie', role: prof, destination: 'saisie', gestes: (t) => choisir(t, 'Séquence', 'Séquence 2'));
  ecran('prof-manquantes', role: prof, destination: 'manquantes', gestes: (t) => choisir(t, 'Séquence', 'Séquence 2'));
  ecran('prof-statistiques', role: prof, destination: 'stats-prof');

  // Directeur.
  ecran('dir-accueil', role: directeur);
  ecran('dir-decisions', role: directeur, destination: 'decisions');
  ecran('dir-desapprouver', role: directeur, destination: 'decisions', gestes: (t) => toucher(t, find.widgetWithText(OutlinedButton, 'Désapprouver')));
  ecran('dir-fiche-eleve', role: directeur, gestes: ficheEleve);
  ecran('dir-renvoyer', role: directeur, gestes: (t) async {
    await ficheEleve(t);
    await toucher(t, find.text('Renvoyer'));
  });
  ecran('dir-renvoyes', role: directeur, destination: 'renvoyes');
  ecran('dir-attestations', role: directeur, destination: 'attestations');
  ecran('dir-nouvelle-attestation', role: directeur, destination: 'attestations', gestes: (t) => toucher(t, find.text('Nouvelle attestation')));
  ecran('dir-parametres', role: directeur, destination: 'parametres');

  // Surveillant Général.
  ecran('sg-accueil', role: sg);
  ecran('sg-notifications', role: sg, gestes: (t) => toucher(t, find.byType(ClocheNotifications)));
  ecran('sg-parametres', role: sg, destination: 'parametres');
  ecran('sg-annees', role: sg, destination: 'annees');
  ecran('sg-specialites', role: sg, gestes: (t) => pousser(t, const EcranSpecialites()));
  ecran('sg-classes', role: sg, destination: 'classes');
  ecran('sg-nouvelle-classe', role: sg, destination: 'classes', gestes: (t) => toucher(t, find.byType(FloatingActionButton)));
  ecran('sg-groupes', role: sg, destination: 'groupes');
  ecran('sg-enseignants', role: sg, destination: 'enseignants');
  ecran('sg-enseignant-carriere', role: sg, destination: 'enseignants', gestes: (t) async {
    await toucher(t, find.byType(PopupMenuButton<String>));
    await toucher(t, find.text('Modifier'));
    await t.scrollUntilVisible(find.text('Carrière'), 300, scrollable: find.byType(Scrollable).last);
    await attendre(t);
  });
  ecran('sg-matieres', role: sg, destination: 'matieres', gestes: (t) => choisir(t, 'Classe', '1re année Mécanique A'));
  ecran('sg-nouvelle-matiere', role: sg, destination: 'matieres', gestes: (t) async {
    await choisir(t, 'Classe', '1re année Mécanique A');
    await toucher(t, find.byType(FloatingActionButton));
  });
  ecran('sg-eleves', role: sg, destination: 'eleves');
  ecran('sg-ajout-eleves', role: sg, destination: 'eleves', gestes: (t) => toucher(t, find.text('Ajouter des élèves')));
  ecran('sg-import', role: sg, destination: 'eleves', gestes: (t) => toucher(t, find.text('Importer')));
  ecran('sg-photos', role: sg, destination: 'eleves', gestes: (t) async {
    await toucher(t, find.text('Photos'));
    await choisir(t, 'Classe', '1re année Mécanique A');
  });
  ecran('sg-fiche-eleve', role: sg, gestes: ficheEleve);
  ecran('sg-reinscription', role: sg, destination: 'reinscription');
  ecran('sg-notes', role: sg, destination: 'notes', gestes: (t) => choisir(t, 'Classe', '1re année Mécanique A'));
  ecran('sg-bulletins', role: sg, destination: 'bulletins');
  ecran('sg-cartes', role: sg, destination: 'cartes');
  ecran('sg-statistiques', role: sg, destination: 'statistiques');
  ecran('sg-classement', role: sg, destination: 'classement');
  ecran('sg-tableau-honneur', role: sg, destination: 'tableau-honneur');

  // Mises à jour (chapitre « L'application mobile »).
  const nouvelle = VersionPubliee(
    numero: 3,
    nom: '1.1.1',
    url: 'https://github.com/Dominique-BRIA/cetic-mezesse-mobile/releases/download/v1.1.1%2B3/cetic-mezesse.apk',
    taille: 58245417,
    minimum: 0,
    notes: 'Cartes scolaires et tableau d’honneur plus rapides.',
  );
  // Les étapes sont posées à la main : rien n'est téléchargé ni installé.
  ecran('maj-telechargement', role: prof, gestes: (t) async {
    MiseAJour.i
      ..numeroInstalle = 2
      ..publiee = nouvelle
      ..etape = EtapeMiseAJour.telechargement
      ..progression = 0.42
      ..signaler();
    await attendre(t, maximum: 1500);
  });
  ecran('maj-bandeau', role: prof, gestes: (t) async {
    MiseAJour.i
      ..numeroInstalle = 2
      ..publiee = nouvelle
      ..etape = EtapeMiseAJour.prete
      ..signaler();
    await attendre(t);
  });
  ecran('maj-correctif', role: prof, gestes: (t) async {
    MiseAJour.i
      ..numeroInstalle = 3
      ..correctifPret = true
      ..signaler();
    await attendre(t);
  });
  ecran('maj-obligatoire', role: prof, gestes: (t) async {
    MiseAJour.i
      ..numeroInstalle = 2
      ..publiee = const VersionPubliee(numero: 3, nom: '1.1.1', url: 'https://exemple.cm/a.apk', taille: 58245417, minimum: 3)
      ..etape = EtapeMiseAJour.telechargement
      ..progression = 0.42
      ..signaler();
    await attendre(t, maximum: 1500);
  });
}
