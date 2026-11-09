// Console technique : politique de mise à jour et limite des rapports d'erreur.
import 'dart:io';

import 'package:cetic_mezesse/mise_a_jour.dart';
import 'package:cetic_mezesse/signalement.dart';
import 'package:flutter_test/flutter_test.dart';

const fiche = VersionPubliee(numero: 7, nom: '1.2.0', url: 'https://exemple.cm/a.apk', minimum: 3);

void main() {
  group('politique', () {
    test('se lit entièrement', () {
      final p = PolitiqueMiseAJour.depuisJson({'suspendue': true, 'versionsBloquees': [5, 6], 'minimum': 4, 'message': 'x'})!;
      expect(p.suspendue, isTrue);
      expect(p.versionsBloquees, [5, 6]);
      expect(p.minimum, 4);
    });

    test('réponse inattendue : pas de politique', () {
      expect(PolitiqueMiseAJour.depuisJson(null), isNull);
      expect(PolitiqueMiseAJour.depuisJson({'suspendue': true}), isNull);
      expect(PolitiqueMiseAJour.depuisJson({'suspendue': 'non', 'versionsBloquees': [], 'minimum': 0}), isNull);
    });

    test('suspendue ou version bloquée : écartée', () {
      expect(const PolitiqueMiseAJour(suspendue: true).appliquer(fiche), isNull);
      expect(const PolitiqueMiseAJour(versionsBloquees: [7]).appliquer(fiche), isNull);
      expect(const PolitiqueMiseAJour(versionsBloquees: [6]).appliquer(fiche), same(fiche));
    });

    test('le plus élevé des deux minimums s’applique', () {
      expect(const PolitiqueMiseAJour(minimum: 5).appliquer(fiche)!.minimum, 5);
      expect(const PolitiqueMiseAJour(minimum: 1).appliquer(fiche)!.minimum, 3);
    });
  });

  group('version écartée', () {
    final m = MiseAJour.i;
    setUp(() => m
      ..reinitialiser()
      ..numeroInstalle = 5);

    test('déjà téléchargée : ne s’installera pas', () {
      m
        ..publiee = fiche
        ..apk = File('cetic-mezesse-7.apk')
        ..etape = EtapeMiseAJour.prete;
      m.appliquerPolitique(fiche, const PolitiqueMiseAJour(versionsBloquees: [7]));
      expect(m.publiee, isNull);
      expect(m.apk, isNull);
      expect(m.etape, EtapeMiseAJour.attente);
      expect(m.disponible, isFalse);
    });

    test('téléchargement en cours : il va à son terme, l’état ne change pas', () {
      m
        ..publiee = fiche
        ..etape = EtapeMiseAJour.telechargement;
      m.appliquerPolitique(fiche, const PolitiqueMiseAJour(suspendue: true));
      expect(m.etape, EtapeMiseAJour.telechargement);
      expect(m.publiee, same(fiche));
    });

    test('autorisée : proposée, avec le minimum de la politique', () {
      m.appliquerPolitique(fiche, const PolitiqueMiseAJour(minimum: 6));
      expect(m.disponible, isTrue);
      expect(m.obligatoire, isTrue);
    });
  });

  test('rapports d’erreur : une fois par message, cinq au plus par lancement', () {
    Signalement.oublier();
    expect(Signalement.accepte('a'), isTrue);
    expect(Signalement.accepte('a'), isFalse);
    for (final m in ['b', 'c', 'd', 'e']) {
      expect(Signalement.accepte(m), isTrue);
    }
    expect(Signalement.accepte('f'), isFalse);
    Signalement.oublier();
  });
}
