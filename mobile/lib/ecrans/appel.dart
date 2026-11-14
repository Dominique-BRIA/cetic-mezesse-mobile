import 'dart:convert';

import 'package:flutter/material.dart';

import '../api.dart';
import '../etat.dart';
import '../theme.dart';
import '../widgets.dart';
import 'emploi_du_temps.dart' show duree;
import 'organisation.dart';

// Feuille d'appel : une classe, un jour. Les séances viennent de l'emploi du temps ; tout le monde est
// présent par défaut, le SG ne coche que les absents, séance par séance (appui long sur un élève : toute la
// journée). Chaque case est gardée sur le téléphone ; « Enregistrer l'appel » l'envoie une fois pour toutes,
// ensuite chaque modification est une correction historisée.

const _jours = ['', 'lundi', 'mardi', 'mercredi', 'jeudi', 'vendredi', 'samedi', 'dimanche'];

/// Jour de cours le plus proche en partant de [d] dans le sens [pas] (-1 ou +1) : le week-end est sauté.
DateTime _jourDeCours(DateTime d, int pas) {
  var j = DateTime(d.year, d.month, d.day);
  while (j.weekday >= 6) {
    j = j.add(Duration(days: pas));
  }
  return j;
}

String _iso(DateTime d) => '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

String _dateLongue(String iso, int jour) {
  final p = iso.split('-');
  return '${_jours[jour]} ${p[2]}/${p[1]}/${p[0]}';
}

String _personne(Map? p) => p == null ? 'Aucun enseignant' : '${p['prenom']} ${p['nom']}';

String _heureLocale(String iso) {
  final d = DateTime.parse(iso).toLocal();
  return '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')} à ${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
}

/// Colonne d'une séance : son identifiant une fois l'appel enregistré, son créneau avant.
String _colonne(Map s) => (s['id'] as String?) ?? 'c:${s['creneauId']}';

class EcranAppel extends StatefulWidget {
  const EcranAppel({super.key});
  @override
  State<EcranAppel> createState() => _EcranAppelState();
}

class _EcranAppelState extends State<EcranAppel> {
  String? _classe;
  // Le week-end, la feuille s'ouvre sur le dernier vendredi.
  DateTime _date = _jourDeCours(DateTime.now(), -1);
  int _rechargement = 0;
  Map? _vue;
  // État de l'appel du jour par classe : fait (absents), à faire, pas de cours.
  Map<String, Map> _etats = {};
  Set<String> _cases = {};
  Set<String> _enregistrees = {};
  String? _seance;
  String? _sequence;
  bool _reprise = false;
  bool _envoi = false;
  final _recherche = TextEditingController();
  bool _seulementAbsents = false;
  Set<String> _justifiees = {};
  // Échec d'envoi (réseau coupé…) : la saisie reste sur le téléphone, on le dit dans la barre.
  String? _erreurEnvoi;

  // ---------- Saisie gardée sur le téléphone ----------

  String _cleCache(Map vue) => 'appel:${vue['classeId']}:${vue['date']}';

  void _garder() {
    final vue = _vue;
    if (vue == null || !Etat.i.estSG) return;
    final aGarder = vue['fiche'] != null ? _modifie : (_cases.isNotEmpty || (_sequence != null && _sequence != vue['sequenceProposee']));
    if (aGarder) {
      Api.i.prefs.setString(_cleCache(vue), jsonEncode({'cases': _cases.toList(), 'sequenceId': _sequence}));
    } else {
      Api.i.prefs.remove(_cleCache(vue));
    }
  }

  /// Séquence changée sur une feuille enregistrée : c'est une correction, comme une case cochée.
  bool get _sequenceModifiee => _vue?['fiche'] != null && _sequence != null && _sequence != _vue!['fiche']['sequenceId'];

  bool get _modifie =>
      _vue?['fiche'] == null || _sequenceModifiee || _cases.length != _enregistrees.length || _cases.any((c) => !_enregistrees.contains(c));

  /// Nouvelle vue du serveur : la saisie gardée sur le téléphone l'emporte sur ce qui est enregistré.
  void _recevoir(Map vue) {
    _vue = vue;
    _justifiees = {for (final a in ((vue['justifiees'] as List?) ?? const []).cast<Map>()) '${a['seanceId']}|${a['inscriptionId']}'};
    _enregistrees = {for (final a in (vue['absences'] as List).cast<Map>()) '${a['seanceId']}|${a['inscriptionId']}'};
    final seances = (vue['seances'] as List).cast<Map>();
    final colonnes = {for (final s in seances.where((s) => s['statut'] != 'ANNULEE')) _colonne(s): s};
    final parCreneau = {for (final s in seances.where((s) => s['creneauId'] != null)) 'c:${s['creneauId']}': s};
    final renvoyes = {for (final e in (vue['eleves'] as List).cast<Map>().where((e) => e['renvoye'] == true)) e['inscriptionId']};
    final texte = Etat.i.estSG ? Api.i.prefs.getString(_cleCache(vue)) : null;
    final cache = texte == null ? null : jsonDecode(texte) as Map;
    var depart = {..._enregistrees};
    if (cache != null) {
      depart = {};
      for (final k in (cache['cases'] as List).cast<String>()) {
        final p = k.split('|');
        final s = colonnes[p[0]] ?? (vue['fiche'] != null ? parCreneau[p[0]] : null);
        if (s != null && s['statut'] != 'ANNULEE' && !renvoyes.contains(p[1])) depart.add('${_colonne(s)}|${p[1]}');
      }
    }
    _cases = depart;
    _sequence = cache?['sequenceId'] as String? ?? (vue['fiche']?['sequenceId'] as String?) ?? vue['sequenceProposee'] as String?;
    _reprise = cache != null && ((cache['cases'] as List).isNotEmpty || vue['fiche'] != null) && (vue['fiche'] == null || _modifie);
    final actives = _actives(vue);
    if (_seance == null || !actives.any((s) => _colonne(s) == _seance)) {
      // Même créneau après l'enregistrement : la séance choisie reste la même.
      final avant = _seance == null ? null : parCreneau[_seance];
      _seance = avant != null ? _colonne(avant) : (actives.isEmpty ? null : _colonne(actives.first));
    }
  }

  List<Map> _actives(Map vue) => (vue['seances'] as List).cast<Map>().where((s) => s['statut'] != 'ANNULEE').toList();

  void _maj(VoidCallback f) {
    setState(f);
    _garder();
  }

  void _changer({String? classe, DateTime? date}) {
    setState(() {
      if (classe != null) _classe = classe;
      if (date != null) _date = date;
      _vue = null;
      _seance = null;
      _rechargement++;
    });
  }

  Future<Map?> _appeler(Future<dynamic> Function() action, String succes) async {
    setState(() {
      _envoi = true;
      _erreurEnvoi = null;
    });
    Map? vue;
    var ok = false;
    try {
      vue = await action() as Map;
      ok = true;
      if (mounted) message(context, succes);
    } on ErreurApi catch (e) {
      if (e.horsLigne || e.statut == 0) {
        _erreurEnvoi = "Pas de réseau : rien n'est perdu, la saisie reste sur ce téléphone. Réessayez.";
      } else if (mounted) {
        message(context, e.message, erreur: true);
      }
    }
    if (!mounted) return null;
    setState(() {
      _envoi = false;
      if (ok && vue != null) _recevoir(vue);
    });
    if (ok && vue != null) {
      // L'état du jour (fait, absents) suit l'enregistrement ; une erreur ici n'annule rien.
      try {
        final etats = (await Api.i.get('/appel/etat?date=${vue['date']}') as List).cast<Map>();
        if (mounted) setState(() => _etats = {for (final e in etats) e['classeId'] as String: e});
      } catch (_) {}
    }
    return ok ? vue : null;
  }

  Future<Map?> _enregistrerAppel({bool demander = true}) async {
    final vue = _vue!;
    final absents = (vue['eleves'] as List).cast<Map>().where((e) => _minutes(e) > 0).length;
    if (demander && !await confirmer(context, "Enregistrer l'appel ?", '$absents élève(s) absent(s), les autres présents.', action: 'Enregistrer')) return null;
    final cle = _cleCache(vue);
    final corps = {
      'classeId': vue['classeId'],
      'date': vue['date'],
      'sequenceId': _sequence ?? vue['sequenceProposee'],
      'absences': [
        for (final c in _cases) {'creneauId': c.split('|')[0].substring(2), 'inscriptionId': c.split('|')[1]},
      ],
    };
    final r = await _appeler(() async {
      final v = await Api.i.post('/appel', corps);
      await Api.i.prefs.remove(cle);
      return v;
    }, 'Appel enregistré.');
    if (r != null) _garder();
    return r;
  }

  Future<void> _corriger() async {
    final vue = _vue!;
    final cle = _cleCache(vue);
    final corps = {
      'absences': [
        for (final c in _cases) {'seanceId': c.split('|')[0], 'inscriptionId': c.split('|')[1]},
      ],
      'sequenceId': _sequenceModifiee ? _sequence : null,
    };
    await _appeler(() async {
      final v = await Api.i.put('/appel/${vue['fiche']['id']}/absences', corps);
      await Api.i.prefs.remove(cle);
      return v;
    }, 'Correction enregistrée.');
  }

  List<Map> _filtres(List<Map> eleves) {
    String sans(String t) => t.toLowerCase().replaceAll(RegExp('[éèêë]'), 'e').replaceAll(RegExp('[àâä]'), 'a').replaceAll(RegExp('[îï]'), 'i').replaceAll(RegExp('[ôö]'), 'o').replaceAll(RegExp('[ûüù]'), 'u').replaceAll('ç', 'c');
    final q = sans(_recherche.text.trim());
    return eleves
        .where((e) => q.isEmpty || '${e['numero']}' == q || sans('${e['nom']} ${e['prenoms']} ${e['matricule']}').contains(q))
        .where((e) => !_seulementAbsents || _minutes(e) > 0)
        .toList();
  }

  /// Retirer une absence justifiée supprime aussi sa justification à l'enregistrement : on demande d'abord.
  Future<void> _basculerCase(String k) async {
    if (_cases.contains(k) && _justifiees.contains(k)) {
      if (!await confirmer(context, 'Absence justifiée', "La retirer supprimera aussi sa justification à l'enregistrement.", action: 'Retirer', danger: true)) return;
    }
    _maj(() => _cases.contains(k) ? _cases.remove(k) : _cases.add(k));
  }

  Future<void> _toutLaSeance(Map s, bool absents) async {
    final cibles = [for (final e in (_vue!['eleves'] as List).cast<Map>().where((e) => e['renvoye'] != true)) '${_colonne(s)}|${e['inscriptionId']}'];
    if (!absents && cibles.any((k) => _cases.contains(k) && _justifiees.contains(k))) {
      if (!await confirmer(context, 'Absences justifiées', "Les absences justifiées seront retirées avec leur justification à l'enregistrement.", action: 'Continuer', danger: true)) return;
    }
    _maj(() => absents ? _cases.addAll(cibles) : _cases.removeAll(cibles));
  }

  int get _nbModifications =>
      _cases.where((c) => !_enregistrees.contains(c)).length + _enregistrees.where((c) => !_cases.contains(c)).length + (_sequenceModifiee ? 1 : 0);

  int _minutes(Map e) =>
      _actives(_vue!).where((s) => _cases.contains('${_colonne(s)}|${e['inscriptionId']}')).fold<int>(0, (n, s) => n + (s['duree'] as int));

  void _basculerJournee(Map e) {
    final actives = _actives(_vue!);
    final toutes = actives.every((s) => _cases.contains('${_colonne(s)}|${e['inscriptionId']}'));
    _maj(() {
      for (final s in actives) {
        final k = '${_colonne(s)}|${e['inscriptionId']}';
        toutes ? _cases.remove(k) : _cases.add(k);
      }
    });
    message(context, toutes ? '${e['nom']} de nouveau présent toute la journée.' : '${e['nom']} absent toute la journée.');
  }

  // ---------- Séances ----------

  /// Une séance se modifie sur l'appel enregistré : s'il ne l'est pas encore, on l'enregistre d'abord.
  Future<void> _modifierSeance(Map? s) async {
    var seance = s;
    if (_vue!['fiche'] == null) {
      if (!await confirmer(context, "Enregistrer l'appel d'abord", "Pour modifier une séance, l'appel doit être enregistré, avec les absences déjà cochées.",
          action: 'Enregistrer')) {
        return;
      }
      final vue = await _enregistrerAppel(demander: false);
      if (vue == null) return;
      if (s != null) seance = (vue['seances'] as List).cast<Map>().where((x) => x['creneauId'] == s['creneauId']).firstOrNull;
    }
    if (mounted) await _formulaireSeance(seance);
  }

  /// Toucher l'en-tête de la séance : l'enseignant prévu est marqué absent, ou de nouveau présent.
  Future<void> _basculerEnseignant(Map s) async {
    if (s['statut'] == 'ANNULEE') {
      message(context, 'Séance annulée : passez par « Modifier la séance… » pour la rétablir.');
      return;
    }
    if (s['remplacant'] != null) {
      message(context, 'Remplacé par ${_personne(s['remplacant'] as Map)} : la séance a été assurée. Pour changer, « Modifier la séance… ».');
      return;
    }
    final qui = _personne(s['enseignant'] as Map?).isEmpty ? "L'enseignant" : _personne(s['enseignant'] as Map?);
    final absent = s['enseignantAbsent'] != true;
    final sansFiche = _vue!['fiche'] == null;
    final texte = absent
        ? '$qui absent en ${s['matiere']} (${s['debut']} – ${s['fin']}) ? La séance comptera comme non assurée ; les élèves absents restent comptés absents.'
        : '$qui de nouveau présent en ${s['matiere']} (${s['debut']} – ${s['fin']}) ?';
    if (!await confirmer(context, absent ? 'Enseignant absent' : 'Enseignant présent',
        sansFiche ? "$texte\n\nL'appel sera d'abord enregistré, avec les absences déjà cochées." : texte,
        action: absent ? 'Marquer absent' : 'Remettre présent')) {
      return;
    }
    Map? seance = s;
    if (sansFiche) {
      final vue = await _enregistrerAppel(demander: false);
      if (vue == null) return;
      seance = (vue['seances'] as List).cast<Map>().where((x) => x['creneauId'] == s['creneauId']).firstOrNull;
    }
    if (seance == null || seance['id'] == null || !mounted) return;
    Map? resultat;
    final ok = await agir(
      context,
      () async => resultat = await Api.i.put('/appel/seances/${seance!['id']}', {
        'debut': seance['debut'],
        'fin': seance['fin'],
        'remplacantId': null,
        'enseignantAbsent': absent,
        'annulee': false,
        'motif': seance['motif'],
      }) as Map,
      succes: absent ? '$qui marqué absent.' : '$qui de nouveau présent.',
    );
    if (ok && resultat != null && mounted) {
      setState(() => _recevoir(resultat!));
      _garder();
    }
  }

  Future<void> _formulaireSeance(Map? s) async {
    final fiche = _vue!['fiche'] as Map;
    final profs = (await Api.i.get('/utilisateurs?role=PROFESSEUR') as List).cast<Map>().where((p) => p['actif'] == true).toList();
    final matieres = s == null ? (await Api.i.get('/matieres?classeId=${_vue!['classeId']}') as List).cast<Map>() : <Map>[];
    if (!mounted) return;
    var matiereId = '';
    var debut = s?['debut'] as String? ?? '';
    var fin = s?['fin'] as String? ?? '';
    var remplacant = (s?['remplacant'] as Map?)?['id'] as String? ?? '';
    var enseignantAbsent = s?['enseignantAbsent'] == true;
    var annulee = s?['statut'] == 'ANNULEE';
    final motif = TextEditingController(text: s?['motif'] as String? ?? '');
    Map? resultat;
    final ok = await feuilleFormulaire(
      context,
      s == null ? 'Ajouter une séance pour ce jour' : '${s['matiere']}, ce jour-là',
      (ctx, maj) {
        Future<void> heure(bool estDebut) async {
          final actuelle = (estDebut ? debut : fin).isEmpty ? '07:30' : (estDebut ? debut : fin);
          final p = actuelle.split(':');
          final t = await showTimePicker(
            context: ctx,
            initialTime: TimeOfDay(hour: int.parse(p[0]), minute: int.parse(p[1])),
            builder: (c, enfant) => MediaQuery(data: MediaQuery.of(c).copyWith(alwaysUse24HourFormat: true), child: enfant!),
          );
          if (t != null) {
            final h = '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
            maj(() => estDebut ? debut = h : fin = h);
          }
        }

        return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          if (s == null)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Choix<String>(
                libelle: 'Matière',
                valeur: matiereId,
                options: [for (final m in matieres) (m['id'] as String, m['nom'] as String)],
                changer: (v) => maj(() => matiereId = v ?? ''),
              ),
            ),
          Row(children: [
            Expanded(child: OutlinedButton(onPressed: () => heure(true), child: Text('Début : ${debut.isEmpty ? '—' : debut}'))),
            const SizedBox(width: 8),
            Expanded(child: OutlinedButton(onPressed: () => heure(false), child: Text('Fin : ${fin.isEmpty ? '—' : fin}'))),
          ]),
          if (s != null) ...[
            const SizedBox(height: 12),
            Choix<String>(
              libelle: 'Remplaçant',
              valeur: remplacant,
              options: [
                ('', 'Pas de remplaçant'),
                for (final p in profs.where((p) => p['id'] != (s['enseignant'] as Map?)?['id'])) (p['id'] as String, '${p['prenom']} ${p['nom']}'),
              ],
              changer: (v) => maj(() {
                remplacant = v ?? '';
                if (remplacant.isNotEmpty) enseignantAbsent = false;
              }),
            ),
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              value: enseignantAbsent,
              onChanged: remplacant.isNotEmpty || annulee ? null : (v) => maj(() => enseignantAbsent = v ?? false),
              title: const Text('Enseignant absent'),
              subtitle: const Text('Séance non assurée ; les élèves absents restent comptés absents.'),
            ),
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              value: annulee,
              onChanged: (v) => maj(() {
                annulee = v ?? false;
                if (annulee) enseignantAbsent = false;
              }),
              title: const Text('Séance annulée'),
              subtitle: const Text("Elle n'a pas eu lieu : personne n'y est compté absent."),
            ),
          ],
          const SizedBox(height: 8),
          TextField(controller: motif, maxLength: 300, decoration: const InputDecoration(labelText: 'Motif (facultatif)')),
          if (s?['ajoutee'] == true)
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                style: TextButton.styleFrom(foregroundColor: context.c.danger),
                icon: const Icon(Icons.delete_outline, size: 18),
                label: const Text('Retirer cette séance'),
                onPressed: () async {
                  if (await agir(ctx, () async => resultat = await Api.i.delete('/appel/seances/${s!['id']}') as Map, succes: 'Séance retirée.') && ctx.mounted) {
                    Navigator.pop(ctx, true);
                  }
                },
              ),
            ),
        ]);
      },
      () async {
        if (s == null && matiereId.isEmpty) throw ErreurApi(400, 'Choisissez la matière.');
        if (debut.isEmpty || fin.isEmpty) throw ErreurApi(400, "Choisissez l'heure de début et de fin.");
        final m = motif.text.trim().isEmpty ? null : motif.text.trim();
        resultat = s == null
            ? await Api.i.post('/appel/${fiche['id']}/seances', {'matiereId': matiereId, 'debut': debut, 'fin': fin, 'motif': m}) as Map
            : await Api.i.put('/appel/seances/${s['id']}', {
                'debut': debut,
                'fin': fin,
                'remplacantId': remplacant.isEmpty ? null : remplacant,
                'enseignantAbsent': enseignantAbsent,
                'annulee': annulee,
                'motif': m,
              }) as Map;
      },
    );
    if (ok && resultat != null && mounted) {
      setState(() => _recevoir(resultat!));
      _garder();
    }
  }

  Future<void> _historique() async {
    final liste = (await Api.i.get('/appel/${_vue!['fiche']['id']}/historique') as List).cast<Map>();
    if (!mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.7,
        builder: (ctx, defilement) => ListView(controller: defilement, padding: const EdgeInsets.fromLTRB(16, 0, 16, 24), children: [
          const Text('Historique de la feuille', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
          for (final h in liste)
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text('${h['libelle']}'),
              subtitle: Text('${_heureLocale(h['creeLe'] as String)}${h['par'] == null ? '' : ' · ${h['par']}'}'),
            ),
        ]),
      ),
    );
  }

  // ---------- Affichage ----------

  @override
  Widget build(BuildContext context) {
    return Charge<List<Map<String, dynamic>>>(
      charger: chargerClasses,
      construire: (context, toutes, _) {
        if (toutes.isEmpty) return const Defilement(enfants: [Carte(enfant: Vide('Aucune classe'))]);
        final classes = [...toutes]..sort((x, y) {
            final n = (x['niveau'] as int).compareTo(y['niveau'] as int);
            return n != 0 ? n : (x['nom'] as String).compareTo(y['nom'] as String);
          });
        final classeId = _classe ?? classes.first['id'] as String;
        return Charge<Map>(
          key: ValueKey('$classeId|${_iso(_date)}|$_rechargement'),
          charger: () async {
            final v = await Api.i.get('/appel?classeId=$classeId&date=${_iso(_date)}') as Map;
            final etats = (await Api.i.get('/appel/etat?date=${_iso(_date)}') as List).cast<Map>();
            _etats = {for (final e in etats) e['classeId'] as String: e};
            _recevoir(v);
            return v;
          },
          construire: (context, _, recharger) => _page(context, classes, classeId, recharger),
        );
      },
    );
  }

  Widget _page(BuildContext context, List<Map<String, dynamic>> classes, String classeId, Future<void> Function() recharger) {
    final vue = _vue!;
    final sg = Etat.i.estSG;
    final c = context.c;
    final seances = (vue['seances'] as List).cast<Map>();
    final eleves = (vue['eleves'] as List).cast<Map>();
    final courante = seances.where((s) => _colonne(s) == _seance).firstOrNull;
    final dimanche = (vue['jour'] as int) >= 6; // week-end : pas de cours
    final barre = sg && !dimanche && (seances.isNotEmpty || vue['fiche'] != null);
    return Stack(children: [
      RefreshIndicator(
        onRefresh: recharger,
        child: CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
              sliver: SliverList.list(children: [
                _choix(context, classes, classeId),
                const SizedBox(height: 12),
                if (dimanche) const Carte(enfant: Vide('Week-end', texte: "Les cours ont lieu du lundi au vendredi : pas d'appel le samedi ni le dimanche.")) else _entete(context, vue, sg),
                const SizedBox(height: 12),
                if (!dimanche && seances.isNotEmpty) ...[
                  Row(children: [
                    Expanded(
                      child: TextField(
                        controller: _recherche,
                        decoration: const InputDecoration(labelText: 'Rechercher un élève', prefixIcon: Icon(Icons.search), isDense: true),
                        onChanged: (_) => setState(() {}),
                      ),
                    ),
                    const SizedBox(width: 8),
                    FilterChip(
                      label: const Text('Absents'),
                      tooltip: 'Seulement les absents',
                      selected: _seulementAbsents,
                      onSelected: (v) => setState(() => _seulementAbsents = v),
                    ),
                  ]),
                  const SizedBox(height: 8),
                ],
                if (!dimanche && seances.isEmpty)
                  Carte(
                    enfant: Vide(
                      'Aucune séance ce jour-là',
                      texte: vue['emploiDuTemps'] == true
                          ? "L'emploi du temps ne prévoit pas de cours ce jour-là. Ajoutez les séances qui ont eu lieu."
                          : "Cette classe n'a pas encore d'emploi du temps : saisissez-le, ou ajoutez les séances de ce jour.",
                    ),
                  ),
              ]),
            ),
            // Les séances restent épinglées en haut pendant qu'on fait défiler les élèves.
            if (!dimanche && seances.isNotEmpty)
              SliverPersistentHeader(pinned: true, delegate: _EnteteSeances(hauteur: 64 + 96 * MediaQuery.textScalerOf(context).scale(1).clamp(1.0, 1.6), enfant: _bandeSeances(context, vue, courante, sg))),
            if (!dimanche && courante != null)
              SliverPadding(
                padding: EdgeInsets.fromLTRB(12, 0, 12, barre ? 96 : 24),
                sliver: Builder(builder: (context) {
                  final vus = _filtres(eleves);
                  if (vus.isEmpty) {
                    return SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Text(_seulementAbsents ? 'Aucun élève absent pour le moment.' : 'Aucun élève ne correspond à la recherche.',
                            textAlign: TextAlign.center, style: TextStyle(color: c.encre2)),
                      ),
                    );
                  }
                  return SliverList.builder(
                    itemCount: vus.length,
                    itemBuilder: (context, i) => _ligne(context, vus[i], courante, sg, i == vus.length - 1),
                  );
                }),
              ),
          ],
        ),
      ),
      if (barre) Positioned(left: 12, right: 12, bottom: 12, child: _barre(context, vue, c)),
    ]);
  }

  /// « · fait, 2 absents », « · à faire », « · pas de cours » : l'état se lit sans dépendre de la couleur.
  String _etat(String classeId) {
    final e = _etats[classeId];
    if (e == null) return '';
    if (e['fait'] == true) return ' · fait, ${e['elevesAbsents']} absent(s)';
    if ((e['seancesPrevues'] as int) > 0) return ' · à faire';
    return e['emploiDuTemps'] == true ? ' · pas de cours' : " · pas d'emploi du temps";
  }

  Widget _choix(BuildContext context, List<Map<String, dynamic>> classes, String classeId) {
    final auj = _iso(_jourDeCours(DateTime.now(), -1)) == _iso(_date);
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Choix<String>(
            libelle: 'Classe',
            valeur: classeId,
            options: [for (final c in classes) (c['id'] as String, '${c['nom']}${_etat(c['id'] as String)}')],
            changer: (v) => _changer(classe: v),
          ),
          const SizedBox(height: 8),
          Row(children: [
            IconButton(
              tooltip: 'Jour précédent',
              icon: const Icon(Icons.chevron_left),
              onPressed: () => _changer(date: _jourDeCours(_date.subtract(const Duration(days: 1)), -1)),
            ),
            Expanded(
              child: OutlinedButton.icon(
                icon: const Icon(Icons.event, size: 18),
                label: Text(_dateLongue(_iso(_date), _date.weekday)),
                onPressed: () async {
                  final d = await showDatePicker(context: context, firstDate: DateTime(2020), lastDate: DateTime.now(), initialDate: _date);
                  if (d != null) _changer(date: d);
                },
              ),
            ),
            IconButton(
              tooltip: 'Jour suivant',
              icon: const Icon(Icons.chevron_right),
              onPressed: _jourDeCours(_date.add(const Duration(days: 1)), 1).isAfter(DateTime.now()) ? null : () => _changer(date: _jourDeCours(_date.add(const Duration(days: 1)), 1)),
            ),
            TextButton(onPressed: auj ? null : () => _changer(date: _jourDeCours(DateTime.now(), -1)), child: const Text("Aujourd'hui")),
          ]),
          if (_etats.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Builder(builder: (context) {
                final faites = _etats.values.where((e) => e['fait'] == true).length;
                final aFaire = _etats.values.where((e) => e['fait'] != true && (e['seancesPrevues'] as int) > 0).length;
                return Text(
                  '$faites classe(s) faite(s)${aFaire > 0 ? ' · $aFaire à faire' : " · rien d'autre à faire"} ce jour-là.',
                  style: TextStyle(color: context.c.encre2, fontSize: 12.5),
                );
              }),
            ),
        ]),
      ),
    );
  }

  Widget _entete(BuildContext context, Map vue, bool sg) {
    final c = context.c;
    final fiche = vue['fiche'] as Map?;
    final sequences = (vue['sequences'] as List).cast<Map>();
    final absents = (vue['eleves'] as List).cast<Map>().where((e) => _minutes(e) > 0).length;
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text('${vue['classe']}', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
          Text(_dateLongue(vue['date'] as String, vue['jour'] as int), style: TextStyle(color: c.encre2)),
          const SizedBox(height: 6),
          if (fiche != null)
            Text(
              'Appel enregistré${fiche['creePar'] == null ? '' : ' par ${fiche['creePar']}'} le ${_heureLocale(fiche['creeLe'] as String)}'
              '${fiche['modifieLe'] == null ? '' : ', corrigé le ${_heureLocale(fiche['modifieLe'] as String)}'}.',
              style: TextStyle(color: c.succes, fontSize: 13),
            )
          else if (!sg)
            Text("L'appel de ce jour n'a pas encore été enregistré.", style: TextStyle(color: c.encre3, fontSize: 13)),
          if (_reprise)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text("Saisie reprise depuis ce téléphone : elle n'est pas encore enregistrée.", style: TextStyle(color: c.alerte, fontSize: 13, fontWeight: FontWeight.w600)),
            ),
          const SizedBox(height: 8),
          if (sg)
            Choix<String>(
              libelle: 'Séquence',
              valeur: _sequence,
              options: [for (final s in sequences) (s['id'] as String, 'Séquence ${s['numero']}${s['ouverte'] == true ? ' · ouverte' : ''}')],
              // Gardée sur le téléphone comme une case cochée : envoyée avec l'appel ou la correction.
              changer: (v) {
                if (v != null) _maj(() => _sequence = v);
              },
            ),
          if (_sequenceModifiee)
            Text('Séquence changée : enregistrez la correction pour la garder.', style: TextStyle(color: c.alerte, fontSize: 12.5, fontWeight: FontWeight.w600)),
          Wrap(spacing: 4, crossAxisAlignment: WrapCrossAlignment.center, children: [
            Text('$absents élève${absents > 1 ? 's' : ''} absent${absents > 1 ? 's' : ''}', style: TextStyle(color: c.encre2)),
            if (fiche != null) TextButton.icon(onPressed: _historique, icon: const Icon(Icons.history, size: 18), label: const Text('Historique')),
            if (sg) TextButton.icon(onPressed: () => _modifierSeance(null), icon: const Icon(Icons.add, size: 18), label: const Text('Séance')),
          ]),
        ]),
      ),
    );
  }

  Widget _bandeSeances(BuildContext context, Map vue, Map? courante, bool sg) {
    final c = context.c;
    final seances = (vue['seances'] as List).cast<Map>();
    final eleves = (vue['eleves'] as List).cast<Map>();
    final primaire = Theme.of(context).colorScheme.primary;
    final sur = Theme.of(context).brightness == Brightness.dark ? const Color(0xFF0C1826) : Colors.white;
    return Container(
      color: c.fond,
      padding: const EdgeInsets.fromLTRB(12, 6, 12, 6),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        SizedBox(
          height: 76 * MediaQuery.textScalerOf(context).scale(1).clamp(1.0, 1.6),
          // Une flèche au bord tant que des séances sont cachées à droite (ou à gauche).
          child: _AvecFleches(
            construire: (controleur) => ListView.separated(
            controller: controleur,
            scrollDirection: Axis.horizontal,
            itemCount: seances.length,
            separatorBuilder: (_, _) => const SizedBox(width: 8),
            itemBuilder: (context, i) {
              final s = seances[i];
              final annulee = s['statut'] == 'ANNULEE';
              final choisie = _colonne(s) == _seance;
              final n = eleves.where((e) => _cases.contains('${_colonne(s)}|${e['inscriptionId']}')).length;
              final fond = annulee ? c.surface2 : (choisie ? primaire : primaire.withValues(alpha: 0.12));
              final texte = annulee ? c.encre3 : (choisie ? sur : primaire);
              return Material(
                color: fond,
                borderRadius: BorderRadius.circular(10),
                child: InkWell(
                  borderRadius: BorderRadius.circular(10),
                  onTap: annulee ? (sg ? () => _modifierSeance(s) : null) : () => setState(() => _seance = _colonne(s)),
                  child: Container(
                    width: 150,
                    padding: const EdgeInsets.all(9),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text('${s['debut']} – ${s['fin']}', style: TextStyle(color: texte, fontWeight: FontWeight.w700, fontSize: 13)),
                      Text('${s['matiere']}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(color: texte, fontWeight: FontWeight.w600, decoration: annulee ? TextDecoration.lineThrough : null)),
                      Text(annulee ? 'Annulée' : (s['enseignantAbsent'] == true ? 'Ens. absent · $n abs.' : '$n absent${n > 1 ? 's' : ''}'),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(color: texte, fontSize: 12)),
                    ]),
                  ),
                ),
              );
            },
          ),
          ),
        ),
        const SizedBox(height: 6),
        if (courante != null)
          Material(
            color: primaire.withValues(alpha: 0.10),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(10)),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 6, 4, 6),
              child: Row(children: [
                Expanded(
                  // Le SG marque l'enseignant absent (ou présent) en touchant la matière ou l'enseignant.
                  child: InkWell(
                    onTap: sg ? () => _basculerEnseignant(courante) : null,
                    borderRadius: BorderRadius.circular(6),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('${courante['matiere']}, ${courante['debut']} – ${courante['fin']} (${duree(courante['duree'] as int)})',
                        maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700)),
                    Text(
                      [
                        courante['remplacant'] != null ? 'Remplacé par ${_personne(courante['remplacant'] as Map)}' : _personne(courante['enseignant'] as Map?),
                        if (courante['enseignantAbsent'] == true) 'enseignant absent',
                        if (courante['ajoutee'] == true) 'ajoutée',
                      ].join(' · '),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: c.encre2, fontSize: 12.5),
                    ),
                  ]),
                  ),
                ),
                if (sg)
                  PopupMenuButton<String>(
                    tooltip: 'Actions de la séance',
                    onSelected: (v) => switch (v) {
                      'absents' => _toutLaSeance(courante, true),
                      'presents' => _toutLaSeance(courante, false),
                      _ => _modifierSeance(courante),
                    },
                    itemBuilder: (_) => const [
                      PopupMenuItem(value: 'absents', child: Text('Tous absents')),
                      PopupMenuItem(value: 'presents', child: Text('Tous présents')),
                      PopupMenuItem(value: 'modifier', child: Text('Modifier la séance…')),
                    ],
                  ),
              ]),
            ),
          ),
      ]),
    );
  }

  Widget _ligne(BuildContext context, Map e, Map seance, bool sg, bool derniere) {
    final c = context.c;
    final k = '${_colonne(seance)}|${e['inscriptionId']}';
    final absent = _cases.contains(k);
    final renvoye = e['renvoye'] == true;
    final minutes = _minutes(e);
    final actif = sg && !renvoye;
    return Material(
      color: absent ? Color.alphaBlend(c.danger.withValues(alpha: 0.10), Theme.of(context).colorScheme.surface) : Theme.of(context).colorScheme.surface,
      borderRadius: derniere ? const BorderRadius.vertical(bottom: Radius.circular(10)) : null,
      child: InkWell(
        onTap: actif ? () => _basculerCase(k) : null,
        onLongPress: actif ? () => _basculerJournee(e) : null,
        child: Container(
          decoration: BoxDecoration(border: Border(bottom: BorderSide(color: c.bord))),
          padding: const EdgeInsets.fromLTRB(14, 8, 8, 8),
          child: Row(children: [
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text.rich(TextSpan(children: [
                  TextSpan(text: '${e['numero']}. ', style: TextStyle(color: c.encre2, fontWeight: FontWeight.w700)),
                  TextSpan(text: '${e['nom']} ', style: const TextStyle(fontWeight: FontWeight.w600)),
                  TextSpan(text: '${e['prenoms']}', style: TextStyle(color: c.encre2)),
                ])),
                if (renvoye) Text('Renvoyé(e) ce jour-là', style: TextStyle(color: c.encre3, fontSize: 12)),
                if (minutes > 0) Text("Absent ${duree(minutes)} aujourd'hui", style: TextStyle(color: c.danger, fontSize: 12, fontWeight: FontWeight.w600)),
              ]),
            ),
            if (!renvoye)
              Builder(builder: (context) {
                final justifiee = absent && _justifiees.contains(k);
                final primaire = Theme.of(context).colorScheme.primary;
                final sur = Theme.of(context).brightness == Brightness.dark ? const Color(0xFF0C1826) : Colors.white;
                final (fond, bord, texte, icone, mot) = justifiee
                    ? (c.primairePale, primaire, primaire, Icons.check, 'Justifiée')
                    : absent
                        ? (c.danger, c.danger, sur, Icons.close, 'Absent')
                        : (Colors.transparent, c.bord, c.encre3, null, 'Présent');
                return Container(
                  width: 96,
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  decoration: BoxDecoration(color: fond, borderRadius: BorderRadius.circular(6), border: Border.all(color: bord)),
                  child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                    if (icone != null) ...[Icon(icone, size: 15, color: texte), const SizedBox(width: 3)],
                    Text(mot, style: TextStyle(color: texte, fontWeight: FontWeight.w600, fontSize: 13)),
                  ]),
                );
              }),
          ]),
        ),
      ),
    );
  }

  Widget _barre(BuildContext context, Map vue, Couleurs c) {
    final fiche = vue['fiche'];
    final n = _nbModifications;
    final texte = _envoi
        ? 'Enregistrement…'
        : _erreurEnvoi ??
            (fiche == null
                ? 'Pas encore enregistré · gardé sur ce téléphone'
                : (_modifie ? '$n modification(s) gardée(s) sur ce téléphone' : 'Tout est enregistré'));
    return Card(
      margin: EdgeInsets.zero,
      elevation: 6,
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Row(children: [
          Expanded(
            child: Text(texte,
                style: TextStyle(
                    color: _erreurEnvoi != null ? c.danger : (_modifie ? c.alerte : c.encre3),
                    fontWeight: _modifie || _erreurEnvoi != null ? FontWeight.w700 : FontWeight.w400,
                    fontSize: 13)),
          ),
          const SizedBox(width: 8),
          FilledButton(
            onPressed: _envoi || (fiche != null && !_modifie) ? null : (fiche == null ? () => _enregistrerAppel() : _corriger),
            child: Text(fiche == null ? "Enregistrer l'appel" : (_modifie ? 'Enregistrer · $n' : 'Enregistrer')),
          ),
        ]),
      ),
    );
  }
}

/// En-tête épinglé : la rangée des séances et la séance choisie restent visibles en faisant défiler les élèves.
class _EnteteSeances extends SliverPersistentHeaderDelegate {
  _EnteteSeances({required this.hauteur, required this.enfant});
  final double hauteur;
  final Widget enfant;

  @override
  double get minExtent => hauteur;
  @override
  double get maxExtent => hauteur;

  @override
  Widget build(BuildContext context, double decalage, bool chevauche) => SizedBox(height: hauteur, child: ClipRect(child: enfant));

  @override
  bool shouldRebuild(_EnteteSeances ancien) => true;
}

/// Liste horizontale avec une flèche au bord tant que des éléments sont cachés à droite (ou à gauche) :
/// elle signale qu'il faut faire défiler, et la toucher le fait.
class _AvecFleches extends StatefulWidget {
  const _AvecFleches({required this.construire});
  final Widget Function(ScrollController controleur) construire;

  @override
  State<_AvecFleches> createState() => _AvecFlechesState();
}

class _AvecFlechesState extends State<_AvecFleches> {
  final _controleur = ScrollController();
  bool _gauche = false;
  bool _droite = false;

  void _maj() {
    if (!_controleur.hasClients) return;
    final p = _controleur.position;
    final g = p.pixels > 4;
    final d = p.pixels < p.maxScrollExtent - 4;
    if (g != _gauche || d != _droite) {
      setState(() {
        _gauche = g;
        _droite = d;
      });
    }
  }

  @override
  void initState() {
    super.initState();
    _controleur.addListener(_maj);
    WidgetsBinding.instance.addPostFrameCallback((_) => _maj());
  }

  @override
  void dispose() {
    _controleur.dispose();
    super.dispose();
  }

  Widget _fleche(IconData icone, double sens, String aide) {
    final primaire = Theme.of(context).colorScheme.primary;
    return Center(
      child: Material(
        color: primaire,
        shape: const CircleBorder(),
        elevation: 3,
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: () {
            final p = _controleur.position;
            _controleur.animateTo((p.pixels + sens * 220).clamp(0, p.maxScrollExtent), duration: const Duration(milliseconds: 250), curve: Curves.easeOut);
          },
          child: Tooltip(
            message: aide,
            child: Padding(
              padding: const EdgeInsets.all(3),
              child: Icon(icone, color: Theme.of(context).brightness == Brightness.dark ? const Color(0xFF0C1826) : Colors.white, size: 18),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return NotificationListener<ScrollMetricsNotification>(
      onNotification: (_) {
        _maj();
        return false;
      },
      child: Stack(children: [
        Positioned.fill(child: widget.construire(_controleur)),
        if (_gauche) Positioned(left: 0, top: 0, bottom: 0, child: _fleche(Icons.chevron_left, -1, 'Séances à gauche')),
        if (_droite) Positioned(right: 0, top: 0, bottom: 0, child: _fleche(Icons.chevron_right, 1, 'Autres séances à droite')),
      ]),
    );
  }
}
