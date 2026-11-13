// Notifications push (Firebase Cloud Messaging). L'API envoie chaque notification aussi aux téléphones
// du destinataire : Android l'affiche même application fermée. Ici : le jeton du téléphone, l'autorisation
// d'afficher, et l'écran à ouvrir quand on touche la notification. Sans configuration Firebase (APK
// construite sans google-services.json), tout cela est simplement inactif : la cloche suffit.
import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';

import 'api.dart';
import 'journal.dart';

class Push {
  Push._();

  static bool _pret = false;
  static String? _jeton;
  static bool _proposee = false;
  static const _cleDemandee = 'push:autorisation-demandee';

  /// Écran demandé par une notification touchée (« /saisie »…) : la coquille l'ouvre puis remet à null.
  static final ValueNotifier<String?> lienDemande = ValueNotifier(null);

  /// Incrémenté à chaque notification reçue application ouverte : la cloche se recharge aussitôt.
  static final ValueNotifier<int> recues = ValueNotifier(0);

  /// Appelé quand Firebase change le jeton du téléphone : il faut le renvoyer à l'API.
  static void Function()? surNouveauJeton;

  static bool get actif => _pret;

  static Future<void> demarrer() async {
    try {
      await Firebase.initializeApp();
      _pret = true;
    } catch (e) {
      noter('push : indisponible ($e)');
      return;
    }
    try {
      final m = FirebaseMessaging.instance;
      // Jeton d'enregistrement FCM, que l'API envoie par l'API HTTP v1 (champ « token »). Firebase 17
      // propose aussi l'identifiant d'installation (register / onRegistered) : passage possible plus tard,
      // l'ancien jeton restant accepté pour l'envoi.
      // ignore: deprecated_member_use
      m.onTokenRefresh.listen((t) {
        _jeton = t;
        surNouveauJeton?.call();
      });
      FirebaseMessaging.onMessage.listen((_) => recues.value++);
      FirebaseMessaging.onMessageOpenedApp.listen(_ouvrir);
      final initiale = await m.getInitialMessage();
      if (initiale != null) _ouvrir(initiale);
    } catch (e) {
      noter('push : $e');
    }
  }

  static void _ouvrir(RemoteMessage m) {
    final lien = m.data['lien'];
    if (lien is String && lien.isNotEmpty) lienDemande.value = lien;
  }

  /// Jeton du téléphone, ou null si Firebase est absent ou injoignable (il sera envoyé une autre fois).
  static Future<String?> jeton() async {
    if (!_pret) return null;
    try {
      // ignore: deprecated_member_use
      return _jeton ??= await FirebaseMessaging.instance.getToken().timeout(const Duration(seconds: 15));
    } catch (e) {
      noter('push : jeton indisponible ($e)');
      return null;
    }
  }

  /// Une fois connecté, une seule fois : Android 13 et plus demandent l'autorisation d'afficher des
  /// notifications. On explique d'abord à quoi elles servent ; « Plus tard » ne redemande pas.
  static Future<void> proposerAutorisation(BuildContext context) async {
    if (!_pret || _proposee) return;
    _proposee = true;
    try {
      final reglages = await FirebaseMessaging.instance.getNotificationSettings();
      if (reglages.authorizationStatus == AuthorizationStatus.authorized) return;
      if (Api.i.prefs.getBool(_cleDemandee) == true || !context.mounted) return;
      final oui = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Recevoir les notifications ?'),
          content: const Text(
              "Ouverture de la saisie des notes, décisions et rappels : vous êtes prévenu sur ce téléphone, même quand l'application est fermée."),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Plus tard')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Autoriser')),
          ],
        ),
      );
      await Api.i.prefs.setBool(_cleDemandee, true);
      if (oui == true) await FirebaseMessaging.instance.requestPermission();
    } catch (e) {
      noter('push : autorisation ($e)');
    }
  }
}
