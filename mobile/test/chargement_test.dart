// Chargement d'un écran : la copie gardée sur le téléphone s'affiche aussitôt, sans attendre le serveur ;
// sans copie, un squelette tient la place du contenu.
import 'dart:async';
import 'dart:convert';

import 'package:cetic_mezesse/api.dart';
import 'package:cetic_mezesse/theme.dart';
import 'package:cetic_mezesse/widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<void> preparer(Map<String, Object> prefs) async {
  SharedPreferences.setMockInitialValues(prefs);
  await Api.i.initialiser();
  Api.i.anneeId = null;
  Api.i.horsLigne.value = false;
}

Widget ecran(Future<List> Function() charger, {bool copieImmediate = true}) => MaterialApp(
      theme: construireTheme(Brightness.light),
      home: Scaffold(
        body: Charge<List>(
          charger: charger,
          copieImmediate: copieImmediate,
          construire: (context, d, _) => ListView(children: [for (final x in d) Text('$x')]),
        ),
      ),
    );

void main() {
  final cle = 'cache:${Api.base}/classes';

  testWidgets('copie gardée : affichée aussitôt, avec la barre de mise à jour', (t) async {
    await preparer({cle: jsonEncode(['1re année Mécanique A'])});
    // Le serveur ne répond pas encore : seule la copie peut être affichée.
    final serveur = Completer<List>();
    await t.pumpWidget(ecran(() async {
      // Passe « copie locale » : lit la copie ; passe « serveur » : attend la réponse simulée.
      if (Zone.current[#copieSeule] == true) return await Api.i.get('/classes') as List;
      return serveur.future;
    }));
    await t.pump();
    expect(find.text('1re année Mécanique A'), findsOneWidget);
    expect(find.byType(LinearProgressIndicator), findsOneWidget);
    expect(find.byType(Chargement), findsNothing);

    // La réponse du serveur remplace la copie et retire la barre.
    serveur.complete(['1re année Mécanique A', '1re année Mécanique B']);
    await t.pump();
    await t.pump();
    expect(find.text('1re année Mécanique B'), findsOneWidget);
    expect(find.byType(LinearProgressIndicator), findsNothing);
  });

  testWidgets('sans copie : squelette', (t) async {
    await preparer({});
    await t.pumpWidget(ecran(() => Completer<List>().future));
    await t.pump();
    expect(find.byType(Chargement), findsOneWidget);
  });

  testWidgets('formulaire : la copie n\'est pas utilisée', (t) async {
    await preparer({cle: jsonEncode(['copie'])});
    // Même lecture que l'écran à copie, mais la copie est refusée : le squelette attend le serveur.
    await t.pumpWidget(ecran(() async {
      if (Zone.current[#copieSeule] == true) return await Api.i.get('/classes') as List;
      return Completer<List>().future;
    }, copieImmediate: false));
    await t.pump();
    expect(find.text('copie'), findsNothing);
    expect(find.byType(Chargement), findsOneWidget);
  });

  test('copie seule : aucune écriture vers le serveur', () async {
    await preparer({});
    await expectLater(Api.i.copieSeulement(() => Api.i.post('/attestations', {'utilisateurId': 'u'})), throwsA(isA<ErreurApi>()));
    await expectLater(Api.i.copieSeulement(() => Api.i.get('/classes')), throwsA(isA<ErreurApi>()));
  });
}
