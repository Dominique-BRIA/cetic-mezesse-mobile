// Cloche : la liste des notifications s'ouvre au toucher sans attendre la réponse du serveur.
import 'dart:async';
import 'dart:io';

import 'package:cetic_mezesse/api.dart';
import 'package:cetic_mezesse/ecrans/notifications.dart';
import 'package:cetic_mezesse/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Serveur qui ne répond jamais : chaque requête reste en attente (jusqu'au délai de l'application).
class _ClientMuet implements HttpClient {
  @override
  Future<HttpClientRequest> openUrl(String method, Uri url) => Completer<HttpClientRequest>().future;
  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class _ReseauMuet extends HttpOverrides {
  @override
  HttpClient createHttpClient(SecurityContext? context) => _ClientMuet();
}

void main() {
  testWidgets('la feuille s\'ouvre aussitôt, même si le serveur ne répond pas', (t) async {
    HttpOverrides.global = _ReseauMuet();
    SharedPreferences.setMockInitialValues({});
    await Api.i.initialiser();
    Api.i.horsLigne.value = false;
    await t.pumpWidget(MaterialApp(
      theme: construireTheme(Brightness.light),
      home: Scaffold(appBar: AppBar(actions: [ClocheNotifications(ouvrir: (_) {})])),
    ));
    await t.tap(find.byTooltip('Notifications'));
    // Une image après le toucher, puis l'animation d'ouverture : le serveur, lui, n'a toujours pas répondu.
    await t.pump();
    await t.pump(const Duration(milliseconds: 400));
    expect(find.text('Notifications'), findsOneWidget);

    // Fin du test : on retire la cloche (minuterie) et on laisse expirer les requêtes en attente.
    await t.pumpWidget(const SizedBox());
    await t.pump(const Duration(seconds: 30));
  });
}
