// Bouton retour d'Android : il ouvre le menu ; menu ouvert, il quitte l'application.
import 'dart:convert';

import 'package:cetic_mezesse/ecrans/coquille.dart';
import 'package:cetic_mezesse/etat.dart';
import 'package:cetic_mezesse/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'demarrage_test.dart' show profil;

void main() {
  testWidgets('retour : ouvre le menu, puis quitte l’application', (t) async {
    var quitte = 0;
    // La police de test, plus large que Roboto, fait déborder le titre du menu : sans effet sur le téléphone.
    final erreurs = FlutterError.onError;
    FlutterError.onError = (d) {
      if (!d.exceptionAsString().contains('overflowed')) erreurs?.call(d);
    };
    t.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (appel) async {
      if (appel.method == 'SystemNavigator.pop') quitte++;
      return null;
    });
    SharedPreferences.setMockInitialValues({'jeton': 'j', 'profil': jsonEncode(profil)});
    Etat.i
      ..utilisateur = null
      ..annees = []
      ..demarrage = true;
    destinationCourante.value = 'saisie';
    await t.runAsync(() => Etat.i.demarrer().timeout(const Duration(seconds: 5)));
    await t.pumpWidget(const Application());
    await t.pump(const Duration(milliseconds: 100));
    expect(find.byType(Coquille), findsOneWidget);
    ScaffoldState echafaudage() => t.state<ScaffoldState>(find.descendant(of: find.byType(Coquille), matching: find.byType(Scaffold)).first);
    expect(echafaudage().isDrawerOpen, isFalse);

    // Premier retour : le menu s'ouvre, l'application reste ouverte.
    await t.binding.handlePopRoute();
    await t.pump(const Duration(seconds: 1));
    expect(echafaudage().isDrawerOpen, isTrue);
    expect(quitte, 0);

    // Second retour, menu ouvert : l'application se ferme.
    await t.binding.handlePopRoute();
    await t.pump(const Duration(seconds: 1));
    expect(quitte, 1);
    destinationCourante.value = 'accueil';
    FlutterError.onError = erreurs;
  });
}
