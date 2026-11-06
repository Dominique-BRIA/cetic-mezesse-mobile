// Mises à jour : lecture de la fiche version.json, comparaison des versions, bandeau et écran bloquant.
import 'package:cetic_mezesse/ecrans/mise_a_jour.dart';
import 'package:cetic_mezesse/mise_a_jour.dart';
import 'package:cetic_mezesse/theme.dart';
import 'package:flutter/material.dart';
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
      ..publiee = null
      ..reportee = false
      ..correctifPret = false
      ..correctifVu = false
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

    test('incomplète ou douteuse : aucune mise à jour proposée', () {
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
      expect(find.text('Mettre à jour'), findsNothing);
    });

    testWidgets('nouvelle version : taille, notes, « Plus tard » le cache', (t) async {
      m.publiee = VersionPubliee.depuisJson(fiche);
      await afficher(t, const BandeauMiseAJour());
      expect(find.text('Nouvelle version 1.2.0 (18,4 Mo)'), findsOneWidget);
      expect(find.text('Cartes scolaires plus rapides.'), findsOneWidget);
      await t.tap(find.text('Plus tard'));
      await t.pump();
      expect(find.text('Mettre à jour'), findsNothing);
    });

    testWidgets('déjà à jour : rien', (t) async {
      m
        ..numeroInstalle = 7
        ..publiee = VersionPubliee.depuisJson(fiche);
      await afficher(t, const BandeauMiseAJour());
      expect(find.byType(FilledButton), findsNothing);
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
