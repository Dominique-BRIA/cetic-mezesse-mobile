// Ce que l'application signale à la console technique : sa version à l'ouverture, ses erreurs.
// Rien ici ne doit gêner l'utilisateur : tout échec est ignoré.
import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;

import 'api.dart';
import 'journal.dart';
import 'mise_a_jour.dart';

class Signalement {
  Signalement._();

  static const _canal = MethodChannel('cetic/installation');
  static const _plantagesParLancement = 5;
  static final Set<String> _dejaEnvoyes = {};
  static Map<String, dynamic>? _identite;

  /// Identité du téléphone, fournie par MainActivity ; null si le canal est absent.
  static Future<Map<String, dynamic>?> _lireIdentite() async {
    try {
      return _identite ??= await _canal.invokeMapMethod<String, dynamic>('identite');
    } catch (_) {
      return null;
    }
  }

  /// À chaque ouverture, une fois la session vérifiée. Une version locale (numéro 0) ne signale rien.
  static Future<void> signal() async {
    if (numeroVersion == 0 || Api.i.jeton == null) return;
    try {
      final identite = await _lireIdentite();
      if (identite == null) return;
      await Api.i.envoyer('POST', '/appareils/signal', annee: false, corps: {
        ...identite,
        'numeroVersion': numeroVersion,
        'nomVersion': nomVersion,
        'correctif': await MiseAJour.i.correctifActuel(),
      });
    } catch (e) {
      noter('signal : $e');
    }
  }

  /// Une erreur identique n'est envoyée qu'une fois par lancement, et cinq erreurs au plus.
  @visibleForTesting
  static bool accepte(String message) => _dejaEnvoyes.length < _plantagesParLancement && _dejaEnvoyes.add(message);

  @visibleForTesting
  static void oublier() => _dejaEnvoyes.clear();

  /// Erreur Dart ou Flutter ; les plantages natifs passent par CapturePlantages.kt.
  static Future<void> plantage(String type, String message, String? pile) async {
    if (numeroVersion == 0 || !accepte(message)) return;
    try {
      final identite = await _lireIdentite();
      if (identite == null) return;
      await http
          .post(
            Uri.parse('${Api.base}/appareils/plantages'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'installationId': identite['installationId'],
              'modele': identite['modele'],
              'versionAndroid': identite['versionAndroid'],
              'type': type,
              'message': message,
              'pile': pile,
              'numeroVersion': numeroVersion,
              'nomVersion': nomVersion,
            }),
          )
          .timeout(const Duration(seconds: 10));
    } catch (e) {
      noter('plantage non envoyé : $e');
    }
  }
}
