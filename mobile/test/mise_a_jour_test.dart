// Mises à jour automatiques : lecture de la fiche version.json, comparaison des versions, bandeau
// d'avancement, installation quand l'utilisateur quitte l'application, écran bloquant.
import 'dart:io';

import 'package:cetic_mezesse/ecrans/mise_a_jour.dart';
import 'package:cetic_mezesse/mise_a_jour.dart';
import 'package:cetic_mezesse/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

const fiche = {
  'numero': 7,
  'nom': '1.2.0',
  'url': 'https://github.com/Dominique-BRIA/cetic-mezesse-mobile/releases/download/v1.2.0+7/cetic-mezesse.apk',
  'taille': 19293798,
  'minimum': 3,
  'notes': 'Cartes scolaires plus rapides.',
};

Future<void> afficher(WidgetTester t, Widget w) => t.pumpWidget(MaterialApp(theme: construireTheme(Brightness.light), home: Scaffold(body: w)));

void main() {
  final m = MiseAJour.i;
  setUp(() {
    m
      ..reinitialiser()
      ..numeroInstalle = 5;
  });

  group('fiche version.json', () {
    test('se lit entièrement', () {
      final v = VersionPubliee.depuisJson(fiche)!;
      expect(v.numero, 7);
      expect(v.nom, '1.2.0');
      expect(v.minimum, 3);
      expect(v.tailleLisible, '18,4 Mo');
      expect(v.notes, 'Cartes scolaires plus rapides.');
    });

    test('incomplète ou douteuse : aucune mise à jour', () {
      expect(VersionPubliee.depuisJson(null), isNull);
      expect(VersionPubliee.depuisJson('texte'), isNull);
      expect(VersionPubliee.depuisJson({'nom': '1.2.0'}), isNull);
      expect(VersionPubliee.depuisJson({'numero': '7', 'url': fiche['url']}), isNull);
      expect(VersionPubliee.depuisJson({'numero': 7, 'url': 'http://exemple.cm/app.apk'}), isNull);
    });

    test('champs facultatifs absents', () {
      final v = VersionPubliee.depuisJson({'numero': 7, 'url': fiche['url']})!;
      expect(v.nom, '7');
      expect(v.minimum, 0);
      expect(v.tailleLisible, '');
    });
  });

  group('comparaison', () {
    final v = VersionPubliee.depuisJson(fiche)!;

    test('plus récente seulement si le numéro est plus grand', () {
      expect(v.plusRecenteQue(5), isTrue);
      expect(v.plusRecenteQue(7), isFalse);
      expect(v.plusRecenteQue(9), isFalse);
    });

    test('obligatoire en dessous du minimum', () {
      expect(v.exigeeSur(2), isTrue);
      expect(v.exigeeSur(3), isFalse);
    });

    test('une version locale (numéro 0) ne propose ni n’exige rien', () {
      expect(v.plusRecenteQue(0), isFalse);
      expect(v.exigeeSur(0), isFalse);
    });
  });

  group('bandeau', () {
    testWidgets('caché tant que rien n’est publié', (t) async {
      await afficher(t, const BandeauMiseAJour());
      expect(find.textContaining('version'), findsNothing);
    });

    testWidgets('déjà à jour : rien', (t) async {
      m
        ..numeroInstalle = 7
        ..publiee = VersionPubliee.depuisJson(fiche);
      await afficher(t, const BandeauMiseAJour());
      expect(find.textContaining('1.2.0'), findsNothing);
    });

    testWidgets('téléchargement : avancement, sans rien à décider', (t) async {
      m
        ..publiee = VersionPubliee.depuisJson(fiche)
        ..etape = EtapeMiseAJour.telechargement
        ..progression = 0.42;
      await afficher(t, const BandeauMiseAJour());
      expect(find.text('Version 1.2.0 en cours de téléchargement'), findsOneWidget);
      expect(find.text('42 %'), findsOneWidget);
      expect(find.byType(LinearProgressIndicator), findsOneWidget);
      expect(find.byType(TextButton), findsNothing);
      expect(find.byType(FilledButton), findsNothing);
    });

    testWidgets('version prête : s’installera en quittant, ou tout de suite', (t) async {
      m
        ..publiee = VersionPubliee.depuisJson(fiche)
        ..etape = EtapeMiseAJour.prete;
      await afficher(t, const BandeauMiseAJour());
      expect(find.text('Version 1.2.0 prête'), findsOneWidget);
      expect(find.text('Installer'), findsOneWidget);
    });

    testWidgets('téléchargement interrompu : réessayer', (t) async {
      m
        ..publiee = VersionPubliee.depuisJson(fiche)
        ..erreur = 'le réseau est trop lent, nouvel essai plus tard';
      await afficher(t, const BandeauMiseAJour());
      expect(find.text('Mise à jour 1.2.0 interrompue'), findsOneWidget);
      expect(find.text('Réessayer'), findsOneWidget);
    });

    testWidgets('correctif Shorebird prêt : redémarrer', (t) async {
      m.correctifPret = true;
      await afficher(t, const BandeauMiseAJour());
      expect(find.text('Correctif installé'), findsOneWidget);
      await t.tap(find.text('OK'));
      await t.pump();
      expect(find.text('Correctif installé'), findsNothing);
    });
  });

  group('installation automatique', () {
    late List<String> appels;
    setUp(() {
      appels = [];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(const MethodChannel('cetic/installation'), (appel) async {
        appels.add('${appel.method} ${(appel.arguments as Map)['chemin']}');
        return true;
      });
      m
        ..publiee = VersionPubliee.depuisJson(fiche)
        ..apk = File('cetic-mezesse-7.apk')
        ..etape = EtapeMiseAJour.prete;
    });

    testWidgets('en quittant l’application, puis au retour si Android attendait une confirmation', (t) async {
      // L'utilisateur quitte l'application : installation en arrière-plan.
      m.didChangeAppLifecycleState(AppLifecycleState.paused);
      await t.pump();
      expect(appels, ['installer cetic-mezesse-7.apk']);
      expect(m.etape, EtapeMiseAJour.prete);

      // Il revient : l'application est toujours là, Android attendait une confirmation ; elle est relancée.
      m.didChangeAppLifecycleState(AppLifecycleState.resumed);
      await t.pump();
      expect(appels.length, 2);

      // L'écran de confirmation d'Android met l'application en arrière-plan : pas de troisième essai.
      m.didChangeAppLifecycleState(AppLifecycleState.paused);
      await t.pump();
      expect(appels.length, 2);
    });

    testWidgets('rien à installer tant que l’APK n’est pas complète', (t) async {
      m.etape = EtapeMiseAJour.telechargement;
      m.didChangeAppLifecycleState(AppLifecycleState.paused);
      await t.pump();
      expect(appels, isEmpty);
    });
  });

  testWidgets('version trop ancienne : écran bloquant, sans bandeau', (t) async {
    m
      ..numeroInstalle = 2
      ..publiee = VersionPubliee.depuisJson(fiche);
    expect(m.obligatoire, isTrue);
    expect(m.bandeauVisible, isFalse);
    await t.pumpWidget(MaterialApp(theme: construireTheme(Brightness.light), home: const EcranMiseAJourObligatoire()));
    expect(find.text('Mise à jour nécessaire'), findsOneWidget);
    expect(find.text('Mettre à jour'), findsOneWidget);
  });
}
