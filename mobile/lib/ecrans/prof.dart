// Écrans du professeur : saisie (avec mode hors connexion), élèves sans note, statistiques.
import 'package:flutter/material.dart';

import '../api.dart';
import '../etat.dart';
import '../file_attente.dart';
import '../format.dart';
import '../theme.dart';
import '../widgets.dart';
import 'graphiques.dart';

Future<List<Map<String, dynamic>>> _mesMatieres() async => (await Api.i.get('/matieres') as List).cast<Map<String, dynamic>>();

class EcranSaisie extends StatefulWidget {
  const EcranSaisie({super.key});
  @override
  State<EcranSaisie> createState() => _EcranSaisieState();
}

class _EcranSaisieState extends State<EcranSaisie> {
  String? _matiere;
  String? _sequence = Etat.i.sequenceOuverte?['id'] as String? ?? (Etat.i.sequences.isEmpty ? null : Etat.i.sequences.first['id'] as String);

  @override
  Widget build(BuildContext context) {
    return Charge<List<Map<String, dynamic>>>(
      charger: _mesMatieres,
      construire: (context, matieres, _) {
        if (matieres.isEmpty) return const Defilement(enfants: [Carte(enfant: Vide('Aucune matière ne vous est attribuée'))]);
        final matiere = _matiere ?? matieres.first['id'] as String;
        return Column(children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(children: [
                  Choix<String>(
                    libelle: 'Matière et classe',
                    valeur: matiere,
                    options: [for (final m in matieres) (m['id'] as String, '${m['nom']} · ${m['classe']['nom']} (coef ${m['coefficient']})')],
                    changer: (v) => setState(() => _matiere = v),
                  ),
                  const SizedBox(height: 10),
                  Choix<String>(
                    libelle: 'Séquence',
                    valeur: _sequence,
                    options: [
                      for (final s in Etat.i.sequences) (s['id'] as String, 'Séquence ${s['numero']} ${s['saisieOuverte'] == true ? '(ouverte)' : '(fermée)'}')
                    ],
                    changer: (v) => setState(() => _sequence = v),
                  ),
                ]),
              ),
            ),
          ),
          if (_sequence != null) Expanded(child: _Feuille(key: ValueKey('$matiere-$_sequence'), matiereId: matiere, sequenceId: _sequence!)),
        ]);
      },
    );
  }
}

class _Feuille extends StatefulWidget {
  const _Feuille({super.key, required this.matiereId, required this.sequenceId});
  final String matiereId;
  final String sequenceId;
  @override
  State<_Feuille> createState() => _FeuilleState();
}

class _FeuilleState extends State<_Feuille> {
  Map? _feuille;
  Object? _erreur;
  final Map<String, TextEditingController> _champs = {};
  final Map<String, double?> _initiales = {};
  final _competence = TextEditingController();
  String _competenceInitiale = '';
  bool _envoi = false;

  @override
  void initState() {
    super.initState();
    _charger();
    FileAttente.i.addListener(_rafraichir);
  }

  @override
  void dispose() {
    FileAttente.i.removeListener(_rafraichir);
    for (final c in _champs.values) {
      c.dispose();
    }
    super.dispose();
  }

  void _rafraichir() => mounted ? setState(() {}) : null;

  Future<void> _charger() async {
    try {
      final f = await Api.i.get('/notes/feuille?matiereId=${widget.matiereId}&sequenceId=${widget.sequenceId}') as Map;
      final attente = FileAttente.i.pour(widget.matiereId, widget.sequenceId);
      for (final e in (f['eleves'] as List).cast<Map>()) {
        final id = e['inscriptionId'] as String;
        final serveur = (e['note'] as num?)?.toDouble();
        _initiales[id] = serveur;
        // Une note en attente d'envoi l'emporte sur la version du serveur.
        final affichee = attente != null && attente.notes.containsKey(id) ? attente.notes[id] : serveur;
        _champs[id] = TextEditingController(text: saisieNote(affichee))..addListener(_rafraichir);
      }
      _competenceInitiale = f['competence'] as String? ?? '';
      _competence.text = attente?.competence ?? _competenceInitiale;
      _competence.addListener(_rafraichir);
      setState(() => _feuille = f);
    } catch (e) {
      setState(() => _erreur = e);
    }
  }

  Map<String, double?> get _modifiees {
    final attente = FileAttente.i.pour(widget.matiereId, widget.sequenceId);
    final r = <String, double?>{};
    _champs.forEach((id, c) {
      final v = lireNote(c.text);
      if (v != null && v.isNaN) return;
      final reference = attente != null && attente.notes.containsKey(id) ? attente.notes[id] : _initiales[id];
      if (v != reference) r[id] = v;
    });
    return r;
  }

  int get _invalides => _champs.values.where((c) => lireNote(c.text)?.isNaN ?? false).length;

  Future<void> _enregistrer() async {
    final notes = _modifiees;
    final competence = _competence.text.trim();
    final m = _feuille!['matiere'] as Map;
    setState(() => _envoi = true);
    try {
      await Api.i.put('/notes/feuille', {
        'matiereId': widget.matiereId,
        'sequenceId': widget.sequenceId,
        'competence': competence,
        'notes': notes.entries.map((e) => {'inscriptionId': e.key, 'valeur': e.value}).toList(),
      });
      _initiales.addAll(notes);
      _competenceInitiale = competence;
      if (mounted) message(context, '${notes.length} note(s) enregistrée(s).');
    } on ErreurApi catch (e) {
      if (e.horsLigne) {
        await FileAttente.i.ajouter(Envoi(
          matiereId: widget.matiereId,
          sequenceId: widget.sequenceId,
          libelle: '${m['nom']} · ${m['classe']['nom']} · S${(_feuille!['sequence'] as Map)['numero']}',
          notes: Map.of(notes),
          competence: competence,
        ));
        if (mounted) message(context, 'Pas de réseau : notes gardées sur le téléphone, elles partiront automatiquement.');
      } else if (mounted) {
        message(context, e.message, erreur: true);
      }
    } finally {
      if (mounted) setState(() => _envoi = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_erreur != null) return Padding(padding: const EdgeInsets.all(12), child: MessageErreur(_erreur!));
    if (_feuille == null) return const Chargement();
    final c = context.c;
    final f = _feuille!;
    final fermee = (f['sequence'] as Map)['saisieOuverte'] != true;
    final eleves = (f['eleves'] as List).cast<Map>();
    final saisies = _champs.values.map((c) => lireNote(c.text)).whereType<double>().where((v) => !v.isNaN).toList();
    final moyenne = saisies.isEmpty ? null : saisies.reduce((a, b) => a + b) / saisies.length;
    final attente = FileAttente.i.pour(widget.matiereId, widget.sequenceId);
    final modifiees = _modifiees.length;
    final aEnregistrer = modifiees > 0 || _competence.text.trim() != (attente?.competence ?? _competenceInitiale);

    return Defilement(
      bas: fermee
          ? null
          : Card(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(14, 8, 8, 8),
                child: Row(children: [
                  Expanded(
                    child: Text(
                      _invalides > 0
                          ? '$_invalides note(s) invalide(s)'
                          : aEnregistrer
                              ? '$modifiees note(s) modifiée(s)'
                              : attente != null
                                  ? 'En attente d\'envoi'
                                  : 'Tout est enregistré',
                      style: TextStyle(color: _invalides > 0 ? c.danger : c.encre2, fontSize: 13),
                    ),
                  ),
                  FilledButton.icon(
                    onPressed: !aEnregistrer || _invalides > 0 || _envoi ? null : _enregistrer,
                    icon: _envoi
                        ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(Icons.save_outlined, size: 18),
                    label: const Text('Enregistrer'),
                  ),
                ]),
              ),
            ),
      enfants: [
        if (fermee)
          Carte(
            enfant: Row(children: [
              Icon(Icons.lock_outline, color: c.encre2, size: 20),
              const SizedBox(width: 10),
              const Expanded(child: Text('Saisie fermée : notes en lecture seule. Le Surveillant Général peut la rouvrir.')),
            ]),
          ),
        if (attente?.erreur != null) MessageErreur('Envoi refusé : ${attente!.erreur}'),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: TextField(
              controller: _competence,
              enabled: !fermee,
              maxLength: 300,
              decoration: const InputDecoration(labelText: 'Compétence visée', helperText: 'Imprimée sur le bulletin de la séquence'),
            ),
          ),
        ),
        Carte(
          titre: '${saisies.length}/${eleves.length} notes · moyenne ${note(moyenne)}',
          sansMarge: true,
          enfant: Column(children: [
            for (var i = 0; i < eleves.length; i++) ...[
              _ligne(context, i, eleves[i], fermee),
              if (i < eleves.length - 1) const Divider(),
            ],
          ]),
        ),
      ],
    );
  }

  Widget _ligne(BuildContext context, int i, Map e, bool fermee) {
    final c = context.c;
    final id = e['inscriptionId'] as String;
    final champ = _champs[id]!;
    final v = lireNote(champ.text);
    final invalide = v?.isNaN ?? false;
    final reference = _initiales[id];
    final modifiee = !invalide && v != reference;
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 6, 10, 6),
      child: Row(children: [
        // Numéro d'ordre dans la classe (le même sur tous les écrans).
        SizedBox(width: 26, child: Text('${e['numero'] ?? i + 1}', style: TextStyle(color: c.encre2, fontSize: 12.5, fontWeight: FontWeight.w600))),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('${e['nom']} ${e['prenoms']}', style: const TextStyle(fontWeight: FontWeight.w500)),
            Text('${e['matricule']} · ${e['sexe']}', style: TextStyle(fontSize: 11.5, color: c.encre3)),
          ]),
        ),
        SizedBox(
          width: 84,
          child: TextField(
            controller: champ,
            enabled: !fermee,
            textAlign: TextAlign.right,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            textInputAction: TextInputAction.next,
            style: const TextStyle(fontFeatures: [FontFeature.tabularFigures()], fontWeight: FontWeight.w600),
            decoration: InputDecoration(
              hintText: '—',
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(6),
                borderSide: BorderSide(color: invalide ? c.danger : (modifiee ? Theme.of(context).colorScheme.primary : c.bord)),
              ),
            ),
          ),
        ),
      ]),
    );
  }
}

class EcranManquantes extends StatefulWidget {
  const EcranManquantes({super.key, this.classeId});
  final String? classeId;
  @override
  State<EcranManquantes> createState() => _EcranManquantesState();
}

class _EcranManquantesState extends State<EcranManquantes> {
  String? _sequence = Etat.i.sequenceOuverte?['id'] as String? ?? (Etat.i.sequences.isEmpty ? null : Etat.i.sequences.first['id'] as String);

  @override
  Widget build(BuildContext context) {
    return Column(children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
        child: Card(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Choix<String>(
              libelle: 'Séquence',
              valeur: _sequence,
              options: [for (final s in Etat.i.sequences) (s['id'] as String, 'Séquence ${s['numero']}')],
              changer: (v) => setState(() => _sequence = v),
            ),
          ),
        ),
      ),
      if (_sequence != null)
        Expanded(
          child: Charge<Map>(
            key: ValueKey(_sequence),
            charger: () async => await Api.i.get('/notes/manquantes?sequenceId=$_sequence${widget.classeId == null ? '' : '&classeId=${widget.classeId}'}') as Map,
            construire: (context, d, recharger) => ListeManquantes(d, rafraichir: recharger, avecProf: !Etat.i.estProf),
          ),
        ),
    ]);
  }
}

class ListeManquantes extends StatelessWidget {
  const ListeManquantes(this.donnees, {super.key, this.rafraichir, this.avecProf = false});
  final Map donnees;
  final Future<void> Function()? rafraichir;
  final bool avecProf;

  @override
  Widget build(BuildContext context) {
    final matieres = (donnees['matieres'] as List).cast<Map>();
    return Defilement(rafraichir: rafraichir, enfants: [
      if (matieres.isEmpty) const Carte(enfant: Vide('Aucune matière')),
      for (final m in matieres)
        Builder(builder: (context) {
          final manquants = (m['manquants'] as List).cast<Map>();
          final mat = m['matiere'] as Map;
          final prof = mat['professeur'] as Map?;
          return Carte(
            titre: '${mat['nom']} · ${mat['classe']['nom']}${avecProf && prof != null ? ' · ${prof['prenom']} ${prof['nom']}' : ''}',
            action: manquants.isEmpty
                ? const EtatTexte('Complet', ton: 'succes')
                : EtatTexte('${manquants.length}/${m['effectif']} sans note', ton: manquants.length == m['effectif'] ? 'neutre' : 'alerte'),
            sansMarge: true,
            enfant: manquants.isEmpty
                ? const Padding(padding: EdgeInsets.all(14), child: Text('Tous les élèves ont une note.'))
                : Column(children: [
                    for (final e in manquants)
                      ListTile(
                        title: Text('${e['nom']} ${e['prenoms']}'),
                        trailing: Text('${e['matricule']}', style: TextStyle(color: context.c.encre3, fontSize: 12)),
                      ),
                  ]),
          );
        }),
    ]);
  }
}

class EcranStatsMesMatieres extends StatefulWidget {
  const EcranStatsMesMatieres({super.key});
  @override
  State<EcranStatsMesMatieres> createState() => _EcranStatsMesMatieresState();
}

class _EcranStatsMesMatieresState extends State<EcranStatsMesMatieres> {
  String? _matiere;
  String _periode = 'S1';

  @override
  Widget build(BuildContext context) {
    return Charge<List<Map<String, dynamic>>>(
      charger: _mesMatieres,
      construire: (context, matieres, _) {
        if (matieres.isEmpty) return const Defilement(enfants: [Carte(enfant: Vide('Aucune matière ne vous est attribuée'))]);
        final matiere = _matiere ?? matieres.first['id'] as String;
        return Column(children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(children: [
                  Choix<String>(
                    libelle: 'Matière et classe',
                    valeur: matiere,
                    options: [for (final m in matieres) (m['id'] as String, '${m['nom']} · ${m['classe']['nom']}')],
                    changer: (v) => setState(() => _matiere = v),
                  ),
                  const SizedBox(height: 10),
                  ChoixPeriode(valeur: _periode, changer: (v) => setState(() => _periode = v)),
                ]),
              ),
            ),
          ),
          Expanded(child: StatsMatiere(key: ValueKey('$matiere-$_periode'), matiereId: matiere, periode: _periode)),
        ]);
      },
    );
  }
}

/// Statistiques d'une matière (partagé avec l'écran de la direction).
class StatsMatiere extends StatelessWidget {
  const StatsMatiere({super.key, required this.matiereId, required this.periode, this.exportable = false});
  final String matiereId;
  final String periode;

  /// Menu d'export (direction seulement : l'export lui est réservé).
  final bool exportable;

  @override
  Widget build(BuildContext context) {
    return Charge<Map>(
      charger: () async => await Api.i.get('/statistiques/matiere?matiereId=$matiereId&periode=$periode') as Map,
      construire: (context, s, recharger) {
        final r = s['resume'] as Map;
        if (r['evaluee'] != true) {
          return const Defilement(enfants: [Carte(enfant: Vide('Pas encore de notes sur cette période'))]);
        }
        final eleves = (s['eleves'] as List).cast<Map>();
        return Defilement(rafraichir: recharger, enfants: [
          if (exportable)
            Align(
              alignment: Alignment.centerRight,
              child: MenuExporterTableau(
                tableau: () => {
                  'titre': 'Statistiques · ${s['matiere']['nom']} · ${s['matiere']['classe']['nom']} · ${libellePeriode(periode)}',
                  'sousTitre':
                      'Coefficient ${s['matiere']['coefficient']} · moyenne ${note(r['moyenne'] as num?)} sur ${r['effectif']} élèves · réussite ${pourcent(r['tauxReussite'] as num?)} · min – max ${note(r['min'] as num?)} – ${note(r['max'] as num?)} · écart-type ${note(r['ecartType'] as num?)}',
                  'colonnes': [
                    {'titre': 'Rang', 'largeur': 0.6},
                    {'titre': 'Élève', 'largeur': 3, 'gras': true},
                    {'titre': 'Sexe', 'largeur': 0.5, 'align': 'centre'},
                    {'titre': 'Note', 'largeur': 0.8, 'align': 'droite'},
                    {'titre': 'Grade', 'largeur': 0.7, 'align': 'centre'},
                  ],
                  'lignes': [
                    {'groupe': 'Notes des élèves, de la meilleure à la plus faible'},
                    for (final e in eleves) {'c': [rang(e['rang'] as Map?), '${e['nom']} ${e['prenoms']}', e['sexe'], note(e['note'] as num?), e['grade']]},
                    {'groupe': 'Grades obtenus'},
                    for (final g in (s['grades'] as List).cast<Map>())
                      {'c': ['', g['grade'], '', g['effectif'], pourcent((r['effectif'] as int) == 0 ? null : (g['effectif'] as int) * 100 / (r['effectif'] as int))]},
                    {'groupe': 'Filles et garçons (effectif · moyenne · réussite)'},
                    for (final x in (s['parSexe'] as List).cast<Map>())
                      {'c': ['', x['sexe'] == 'F' ? 'Filles' : 'Garçons', x['effectif'], note(x['moyenne'] as num?), pourcent(x['tauxReussite'] as num?)]},
                    {'groupe': 'Évolution de la moyenne sur les séquences'},
                    for (final e in (s['evolution'] as List).cast<Map>()) {'c': ['', e['periode'], '', e['evaluee'] == true ? note(e['moyenne'] as num?) : '', '']},
                  ],
                  'fichier': 'statistiques-${s['matiere']['nom']}-${s['matiere']['classe']['nom']}-$periode',
                },
              ),
            ),
          GrilleIndicateurs(enfants: [
            Indicateur(libelle: 'Moyenne', valeur: note(r['moyenne'] as num?), accent: true, detail: 'sur ${r['effectif']} élèves'),
            Indicateur(libelle: 'Réussite', valeur: pourcent(r['tauxReussite'] as num?), detail: '${r['reussis']} à 10 ou plus'),
            Indicateur(libelle: 'Min – max', valeur: '${note(r['min'] as num?)} – ${note(r['max'] as num?)}'),
            Indicateur(libelle: 'Écart-type', valeur: note(r['ecartType'] as num?)),
          ]),
          Carte(titre: 'Répartition des notes', enfant: Repartition(s['repartition'] as List)),
          Carte(
            titre: 'Évolution sur les séquences',
            enfant: Evolution([
              for (final e in (s['evolution'] as List).cast<Map>()) {'periode': e['periode'], 'moyenne': e['evaluee'] == true ? e['moyenne'] : null}
            ]),
          ),
          Carte(titre: 'Filles et garçons', enfant: ParSexe(s['parSexe'] as List)),
          Carte(
            titre: 'Grades',
            enfant: Wrap(spacing: 16, runSpacing: 8, children: [
              for (final g in (s['grades'] as List).cast<Map>())
                Text.rich(TextSpan(children: [
                  TextSpan(text: '${g['grade']} ', style: const TextStyle(fontWeight: FontWeight.w700)),
                  TextSpan(text: '${g['effectif']}', style: TextStyle(color: context.c.encre2)),
                ])),
            ]),
          ),
          Carte(
            titre: 'Notes des élèves',
            sansMarge: true,
            enfant: Column(children: [
              for (final e in eleves)
                ListTile(
                  leading: SizedBox(width: 44, child: Text(rang(e['rang'] as Map?), style: TextStyle(color: context.c.encre2))),
                  title: Text('${e['nom']} ${e['prenoms']}'),
                  trailing: Text('${note(e['note'] as num?)}  ${e['grade']}',
                      style: TextStyle(fontWeight: FontWeight.w700, color: couleurNote(context, e['note'] as num?))),
                ),
            ]),
          ),
        ]);
      },
    );
  }
}
