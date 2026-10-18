// Accès à l'API. Chaque lecture réussie est gardée sur le téléphone : sans réseau,
// l'application affiche la dernière version connue au lieu d'une erreur.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'journal.dart';

class ErreurApi implements Exception {
  ErreurApi(this.statut, this.message, {this.horsLigne = false});
  final int statut;
  final String message;
  final bool horsLigne;
  @override
  String toString() => message;
}

/// Type d'une photo d'après son extension (le serveur n'accepte que JPEG et PNG).
MediaType typeImage(String chemin) =>
    chemin.toLowerCase().endsWith('.png') ? MediaType('image', 'png') : MediaType('image', 'jpeg');

/// Code du commit de l'APK, fourni par le workflow GitHub (« locale » pour une construction à la main).
const versionApp = String.fromEnvironment('VERSION', defaultValue: 'locale');

class Api {
  Api._();
  static final Api i = Api._();

  static const base = String.fromEnvironment(
    'API_URL',
    defaultValue: 'https://cetic-mezesse-api-dgfxfucegjg8gscb.francecentral-01.azurewebsites.net/api',
  );

  String? jeton;
  String? anneeId;
  late SharedPreferences prefs;

  /// Vrai quand la dernière requête n'a pas pu joindre le serveur.
  final ValueNotifier<bool> horsLigne = ValueNotifier(false);

  /// Appelé quand le serveur refuse la session (jeton expiré ou compte désactivé).
  VoidCallback? surSessionExpiree;

  /// Appelé après chaque requête réussie : sert à vider la file d'attente des notes.
  VoidCallback? surRetourReseau;

  Future<void> initialiser() async {
    prefs = await SharedPreferences.getInstance();
    jeton = prefs.getString('jeton');
    anneeId = prefs.getString('annee');
  }

  Uri _uri(String chemin, {bool annee = true}) {
    final u = Uri.parse('$base$chemin');
    if (!annee || anneeId == null || u.queryParameters.containsKey('anneeId')) return u;
    return u.replace(queryParameters: {...u.queryParameters, 'anneeId': anneeId!});
  }

  Map<String, String> _entetes({bool json = false}) => {
        if (json) 'Content-Type': 'application/json',
        if (jeton != null) 'Authorization': 'Bearer $jeton',
      };

  void _reseauOk() {
    final etaitHorsLigne = horsLigne.value;
    horsLigne.value = false;
    if (etaitHorsLigne) surRetourReseau?.call();
  }

  /// Exécute [lecture] en ne servant que les copies gardées sur le téléphone, sans aucun appel réseau :
  /// un écran peut ainsi s'afficher aussitôt avec sa dernière version connue. Échoue s'il manque une copie.
  Future<R> copieSeulement<R>(Future<R> Function() lecture) => runZoned(lecture, zoneValues: {_copieSeule: true});

  static const _copieSeule = #copieSeule;
  bool get _enCopieSeule => Zone.current[_copieSeule] == true;

  Future<http.Response> _executer(Future<http.Response> Function() requete, {String quoi = 'requête'}) async {
    // Lecture de la copie locale : jamais de réseau, et surtout jamais d'écriture.
    if (_enCopieSeule) throw ErreurApi(0, 'Pas de copie locale.');
    http.Response r;
    final chrono = Stopwatch()..start();
    try {
      r = await requete().timeout(const Duration(seconds: 25));
    } on SocketException catch (e) {
      noter('ERREUR réseau $quoi : ${e.message} (${chrono.elapsedMilliseconds} ms)');
      horsLigne.value = true;
      throw ErreurApi(0, 'Pas de connexion au serveur.', horsLigne: true);
    } on TimeoutException {
      noter('ERREUR délai dépassé $quoi (${chrono.elapsedMilliseconds} ms)');
      horsLigne.value = true;
      throw ErreurApi(0, 'Le serveur ne répond pas.', horsLigne: true);
    } on http.ClientException catch (e) {
      noter('ERREUR client $quoi : ${e.message}');
      horsLigne.value = true;
      throw ErreurApi(0, 'Pas de connexion au serveur.', horsLigne: true);
    }
    noter('$quoi → ${r.statusCode} (${chrono.elapsedMilliseconds} ms)');
    _reseauOk();
    if (r.statusCode == 401 && jeton != null) surSessionExpiree?.call();
    if (r.statusCode >= 400) {
      var message = 'Erreur ${r.statusCode}';
      try {
        final j = jsonDecode(utf8.decode(r.bodyBytes));
        if (j is Map && j['message'] is String) message = j['message'] as String;
      } catch (_) {}
      throw ErreurApi(r.statusCode, message);
    }
    return r;
  }

  /// Copie locale d'une lecture précédente, sans passer par le réseau.
  dynamic lireCache(String chemin, {bool annee = true}) {
    final copie = prefs.getString('cache:${_uri(chemin, annee: annee)}');
    return copie == null ? null : jsonDecode(copie);
  }

  /// Lecture avec repli sur la copie locale en cas d'absence de réseau.
  Future<dynamic> get(String chemin, {bool annee = true}) async {
    final uri = _uri(chemin, annee: annee);
    final cle = 'cache:$uri';
    // Déjà hors ligne : on sert la copie tout de suite et on retente le réseau en arrière-plan,
    // plutôt que d'attendre l'expiration de chaque requête.
    final copieConnue = prefs.getString(cle);
    if (_enCopieSeule) {
      if (copieConnue == null) throw ErreurApi(0, 'Pas de copie locale.');
      return jsonDecode(copieConnue);
    }
    if (horsLigne.value && copieConnue != null) {
      unawaited(_rafraichirCache(uri, cle));
      return jsonDecode(copieConnue);
    }
    try {
      final r = await _executer(() => http.get(uri, headers: _entetes()), quoi: 'GET ${uri.path}');
      final texte = utf8.decode(r.bodyBytes);
      unawaited(prefs.setString(cle, texte));
      return jsonDecode(texte);
    } on ErreurApi catch (e) {
      final copie = prefs.getString(cle);
      if (e.horsLigne && copie != null) return jsonDecode(copie);
      rethrow;
    }
  }

  Future<void> _rafraichirCache(Uri uri, String cle) async {
    try {
      final r = await _executer(() => http.get(uri, headers: _entetes()), quoi: 'GET ${uri.path}');
      await prefs.setString(cle, utf8.decode(r.bodyBytes));
    } catch (_) {
      // toujours hors ligne : la copie servie reste valable
    }
  }

  Future<dynamic> envoyer(String methode, String chemin, {Object? corps, bool annee = true}) async {
    final uri = _uri(chemin, annee: annee);
    final req = http.Request(methode, uri)..headers.addAll(_entetes(json: corps != null));
    if (corps != null) req.body = jsonEncode(corps);
    final r = await _executer(() async => http.Response.fromStream(await req.send()), quoi: '${req.method} ${req.url.path}');
    if (r.statusCode == 204 || r.bodyBytes.isEmpty) return null;
    return jsonDecode(utf8.decode(r.bodyBytes));
  }

  Future<dynamic> post(String chemin, [Object? corps]) => envoyer('POST', chemin, corps: corps ?? {});
  Future<dynamic> put(String chemin, Object corps) => envoyer('PUT', chemin, corps: corps);
  Future<dynamic> patch(String chemin, Object corps) => envoyer('PATCH', chemin, corps: corps);
  Future<dynamic> delete(String chemin) => envoyer('DELETE', chemin);

  /// Met en réserve, en arrière-plan, les données des écrans du menu : ils s'ouvriront ensuite tout de
  /// suite avec cette copie. Les échecs sont ignorés (l'écran refera la requête).
  Future<void> precharger(List<(String, bool)> lectures) async {
    for (final (chemin, annee) in lectures) {
      if (jeton == null || horsLigne.value) return;
      try {
        await get(chemin, annee: annee);
      } catch (_) {}
    }
  }

  Future<dynamic> televerser(String chemin, String champ, File fichier, {Map<String, String> champs = const {}}) async {
    final req = http.MultipartRequest('POST', _uri(chemin))
      ..headers.addAll(_entetes())
      ..fields.addAll(champs)
      ..files.add(await http.MultipartFile.fromPath(champ, fichier.path, contentType: typeImage(fichier.path)));
    final r = await _executer(() async => http.Response.fromStream(await req.send()), quoi: '${req.method} ${req.url.path}');
    return jsonDecode(utf8.decode(r.bodyBytes));
  }

  /// Formulaire avec plusieurs fichiers (photos d'une saisie groupée) : champs texte + fichiers par nom de champ.
  Future<dynamic> envoyerFormulaire(String chemin, {Map<String, String> champs = const {}, Map<String, File> fichiers = const {}, bool annee = true}) async {
    final req = http.MultipartRequest('POST', _uri(chemin, annee: annee))
      ..headers.addAll(_entetes())
      ..fields.addAll(champs);
    for (final f in fichiers.entries) {
      req.files.add(await http.MultipartFile.fromPath(f.key, f.value.path, contentType: typeImage(f.value.path)));
    }
    final r = await _executer(() async => http.Response.fromStream(await req.send()), quoi: '${req.method} ${req.url.path}');
    return jsonDecode(utf8.decode(r.bodyBytes));
  }

  /// Télécharge un document (PDF, Excel) et l'ouvre avec l'application du téléphone.
  Future<void> ouvrirDocument(String chemin, {String methode = 'GET', Object? corps}) async {
    final req = http.Request(methode, _uri(chemin))..headers.addAll(_entetes(json: corps != null));
    if (corps != null) req.body = jsonEncode(corps);
    final r = await _executer(() async => http.Response.fromStream(await req.send()), quoi: '${req.method} ${req.url.path}');
    final nom = RegExp(r'filename="([^"]+)"').firstMatch(r.headers['content-disposition'] ?? '')?.group(1) ?? 'document';
    final dossier = await getTemporaryDirectory();
    final f = File('${dossier.path}/$nom');
    await f.writeAsBytes(r.bodyBytes);
    final ouverture = await OpenFilex.open(f.path);
    if (ouverture.type != ResultType.done) {
      throw ErreurApi(0, 'Aucune application pour ouvrir ${nom.split('.').last.toUpperCase()} : ${ouverture.message}');
    }
  }

  String urlPhoto(String eleveId, String? version) =>
      '${_uri('/eleves/$eleveId/photo', annee: false)}?jeton=$jeton&v=${version ?? ''}';
}
