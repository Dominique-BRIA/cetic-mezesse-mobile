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
import 'push.dart';

class Signalement {
  Signalement._();

  static const _canal = MethodChannel('cetic/installation');
  static const _plantagesParLancement = 5;
  static final Set<String> _dejaEnvoyes = {};
  static Map<String, dynamic>? _identite;

  /// Détachement noté à la déconnexion, en attente de confirmation par l'API (hors réseau, envoi interrompu).
  static const _cleOubli = 'push:a-oublier';

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
      final jetonPush = await Push.jeton();
      // Reconnecté avant que le détachement ait abouti : ce téléphone sert de nouveau, on ne le détache plus.
      await Api.i.prefs.remove(_cleOubli);
      await Api.i.envoyer('POST', '/appareils/signal', annee: false, corps: {
        ...identite,
        'numeroVersion': numeroVersion,
        'nomVersion': nomVersion,
        'correctif': await MiseAJour.i.correctifActuel(),
        if (jetonPush != null) 'jetonPush': jetonPush,
      });
    } catch (e) {
      noter('signal : $e');
    }
  }

  /// À toute déconnexion (bouton, session expirée) : ce téléphone ne reçoit plus les notifications du compte.
  /// Le détachement est noté d'abord, puis envoyé sans session : l'identifiant d'installation et le jeton de
  /// notification, que seul ce téléphone connaît, suffisent. Sans jeton, le téléphone ne reçoit rien : rien à faire.
  static Future<void> detacher() async {
    try {
      final identite = await _lireIdentite();
      final jetonPush = await Push.jeton();
      if (identite == null || jetonPush == null) return;
      await Api.i.prefs.setString(_cleOubli, jsonEncode({'installationId': identite['installationId'], 'jetonPush': jetonPush}));
    } catch (e) {
      noter('détachement non noté : $e');
      return;
    }
    await envoyerOubli();
  }

  /// Envoie le détachement en attente ; réessayé à chaque ouverture et chaque minute tant qu'il n'a pas abouti.
  static Future<void> envoyerOubli() async {
    final note = Api.i.prefs.getString(_cleOubli);
    if (note == null) return;
    // Quelqu'un s'est reconnecté : le signal rattache le téléphone à ce compte, rien à détacher.
    if (Api.i.jeton != null) {
      await Api.i.prefs.remove(_cleOubli);
      return;
    }
    try {
      final r = await http
          .post(Uri.parse('${Api.base}/appareils/oublier'), headers: {'Content-Type': 'application/json'}, body: note)
          .timeout(const Duration(seconds: 10));
      if (r.statusCode >= 200 && r.statusCode < 300 || r.statusCode == 400) {
        if (Api.i.prefs.getString(_cleOubli) == note) await Api.i.prefs.remove(_cleOubli);
      }
    } catch (e) {
      noter('détachement en attente : $e');
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
