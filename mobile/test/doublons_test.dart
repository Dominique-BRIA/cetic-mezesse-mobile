import 'package:cetic_mezesse/api.dart';
import 'package:cetic_mezesse/doublons.dart';
import 'package:cetic_mezesse/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Avertissement de doublon : la question s'affiche, et la réponse décide du second envoi.
void main() {
  final avertissement = ErreurApi(409, 'Un compte semblable existe déjà', details: {
    'code': 'DOUBLON',
    'titre': 'Un compte semblable existe déjà',
    'candidats': [
      {'id': 'x', 'type': 'enseignant', 'libelle': 'Therence Zidane ZANGA', 'detail': 'Informatique', 'force': 'FORTE', 'lien': '/enseignants', 'creeLe': null, 'ligne': null},
    ],
  });

  Future<(List<Map<String, String>>, Object?)> essayer(WidgetTester tester, String bouton) async {
    final envois = <Map<String, String>>[];
    Object? issue;
    await tester.pumpWidget(MaterialApp(
      theme: ThemeData(extensions: const [Couleurs.clair]),
      home: Builder(
        builder: (context) => TextButton(
          onPressed: () async {
            try {
              issue = await envoyerVerifie<String>(context, (entetes) async {
                envois.add(entetes);
                if (entetes['X-Doublons'] == 'verifier') throw avertissement;
                return 'enregistré';
              });
            } catch (e) {
              issue = e;
            }
          },
          child: const Text('Envoyer'),
        ),
      ),
    ));
    await tester.tap(find.text('Envoyer'));
    await tester.pumpAndSettle();
    expect(find.text('Therence Zidane ZANGA'), findsOneWidget);
    expect(find.text('Très probablement la même'), findsOneWidget);
    await tester.tap(find.text(bouton));
    await tester.pumpAndSettle();
    return (envois, issue);
  }

  testWidgets('confirmer renvoie avec « confirme » et le même identifiant d\'envoi', (tester) async {
    final (envois, issue) = await essayer(tester, 'Enregistrer quand même');
    expect(issue, 'enregistré');
    expect(envois.map((e) => e['X-Doublons']), ['verifier', 'confirme']);
    expect(envois[0]['X-Envoi'], envois[1]['X-Envoi']);
  });

  testWidgets('annuler abandonne sans second envoi', (tester) async {
    final (envois, issue) = await essayer(tester, 'Annuler');
    expect(issue, isA<Abandon>());
    expect(envois, hasLength(1));
  });
}
