import 'package:flutter/material.dart';

import '../api.dart';
import '../etat.dart';
import '../format.dart';
import '../theme.dart';
import '../widgets.dart';
import 'graphiques.dart';
import 'prof.dart';
import 'selection.dart';

/// Sélecteurs en tête d'écran, sur une carte.
Widget _filtres(List<Widget> champs) => Padding(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(children: [
            for (var i = 0; i < champs.length; i++) ...[if (i > 0) const SizedBox(height: 10), champs[i]],
          ]),
        ),
      ),
    );

// ---------------- Notes ----------------

class EcranNotes extends StatefulWidget {
  const EcranNotes({super.key});
  @override
  State<EcranNotes> createState() => _EcranNotesState();
}

class _EcranNotesState extends State<EcranNotes> {
  String? _classe;
  String _periode = 'S1';
  bool _manquantes = false;

  @override
  Widget build(BuildContext context) {
    return Charge<List<Map<String, dynamic>>>(
      charger: chargerClasses,
      construire: (context, classes, _) {
        if (classes.isEmpty) return const Defilement(enfants: [Carte(enfant: Vide('Aucune classe'))]);
        final classeId = _classe ?? classes.first['id'] as String;
        final estSequence = _periode.startsWith('S');
        return Column(children: [
          _filtres([
            Choix<String>(
              libelle: 'Classe',
              valeur: classeId,
              options: [for (final c in classes) (c['id'] as String, c['nom'] as String)],
              changer: (v) => setState(() => _classe = v),
            ),
            ChoixPeriode(
              valeur: _periode,
              changer: (v) => setState(() {
                _periode = v;
                if (!v.startsWith('S')) _manquantes = false;
              }),
            ),
            Row(children: [
              Expanded(
                child: SegmentedButton<bool>(
                  segments: [
                    const ButtonSegment(value: false, label: Text('Relevé')),
                    ButtonSegment(value: true, label: const Text('Manquantes'), enabled: estSequence),
                  ],
                  selected: {_manquantes},
                  onSelectionChanged: (s) => setState(() => _manquantes = s.first),
                ),
              ),
              IconButton(
                tooltip: 'Exporter en Excel',
                icon: const Icon(Icons.table_chart_outlined),
                onPressed: () => agir(context, () => Api.i.ouvrirDocument('/documents/releve?classeId=$classeId&periode=$_periode')),
              ),
            ]),
          ]),
          Expanded(
            child: _manquantes
                ? Charge<Map>(
                    key: ValueKey('m|$classeId|$_periode'),
                    charger: () async {
                      final seq = Etat.i.sequences.firstWhere((s) => 'S${s['numero']}' == _periode);
                      return await Api.i.get('/notes/manquantes?sequenceId=${seq['id']}&classeId=$classeId') as Map;
                    },
                    construire: (context, d, recharger) => ListeManquantes(d, rafraichir: recharger, avecProf: true),
                  )
                : Charge<Map>(
                    key: ValueKey('r|$classeId|$_periode'),
                    charger: () async => await Api.i.get('/notes/classe?classeId=$classeId&periode=$_periode') as Map,
                    construire: (context, r, recharger) => _Releve(r, recharger),
                  ),
          ),
        ]);
      },
    );
  }
}

class _Releve extends StatelessWidget {
  const _Releve(this.r, this.recharger);
  final Map r;
  final Future<void> Function() recharger;

  @override
  Widget build(BuildContext context) {
    final matieres = (r['matieres'] as List).cast<Map>();
    final eleves = (r['eleves'] as List).cast<Map>()
      ..sort((a, b) => ((a['rang']?['rang'] as int?) ?? 999).compareTo((b['rang']?['rang'] as int?) ?? 999));
    final profil = r['profil'] as Map;
    return Defilement(rafraichir: recharger, enfants: [
      GrilleIndicateurs(enfants: [
        Indicateur(libelle: 'Moyenne de classe', valeur: note(profil['moyenneGenerale'] as num?), accent: true),
        Indicateur(libelle: 'Réussite', valeur: pourcent(profil['tauxReussite'] as num?), detail: '${profil['nombreMoyennes']} moyennes'),
      ]),
      if (eleves.isEmpty) const Carte(enfant: Vide('Aucun élève')),
      Carte(
        titre: '${eleves.length} élèves · touchez un élève pour ses notes',
        sansMarge: true,
        enfant: Column(children: [
          for (final e in eleves)
            ExpansionTile(
              shape: const Border(),
              leading: SizedBox(width: 44, child: Text(rang(e['rang'] as Map?), style: TextStyle(color: context.c.encre2))),
              title: Text('${e['nom']} ${e['prenoms']}', style: const TextStyle(fontWeight: FontWeight.w500, fontSize: 14.5)),
              trailing: Text(note(e['moyenne'] as num?),
                  style: TextStyle(fontWeight: FontWeight.w700, color: couleurNote(context, e['moyenne'] as num?))),
              childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
              children: [
                for (var i = 0; i < matieres.length; i++)
                  if (matieres[i]['evaluee'] == true)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 2),
                      child: Row(children: [
                        Expanded(child: Text('${matieres[i]['nom']} (${matieres[i]['coefficient']})', style: TextStyle(color: context.c.encre2, fontSize: 13))),
                        Text(note((e['notes'] as List)[i] as num?),
                            style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13, color: couleurNote(context, (e['notes'] as List)[i] as num?))),
                      ]),
                    ),
              ],
            ),
        ]),
      ),
      Carte(
        titre: 'Moyennes de classe par matière',
        enfant: BarresMoyennes([for (final m in matieres) (m['nom'] as String, m['evaluee'] == true ? m['moyenne'] as num? : null)]),
      ),
    ]);
  }
}

// ---------------- Bulletins ----------------

class EcranBulletins extends StatefulWidget {
  const EcranBulletins({super.key});
  @override
  State<EcranBulletins> createState() => _EcranBulletinsState();
}

class _EcranBulletinsState extends State<EcranBulletins> {
  String _periode = 'S1';
  final _selection = Selection();
  bool _envoi = false;

  @override
  Widget build(BuildContext context) {
    return Charge<List<Map<String, dynamic>>>(
      charger: chargerClasses,
      construire: (context, classes, _) {
        final nombre = _selection.nombre(classes);
        return Defilement(
          bas: FilledButton.icon(
            icon: _envoi
                ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.picture_as_pdf_outlined),
            label: Text(nombre == 0 ? 'Choisissez des classes ou des élèves' : 'Générer $nombre bulletin(s)'),
            onPressed: nombre == 0 || _envoi
                ? null
                : () async {
                    setState(() => _envoi = true);
                    await agir(
                      context,
                      () => Api.i.ouvrirDocument('/documents/bulletins', methode: 'POST', corps: {'periode': _periode, ..._selection.corps()}),
                    );
                    if (mounted) setState(() => _envoi = false);
                  },
          ),
          enfants: [
            Text('Un seul PDF, une page A4 par élève, prêt à imprimer.', style: TextStyle(color: context.c.encre2)),
            const SizedBox(height: 8),
            Carte(
              enfant: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                ChoixPeriode(valeur: _periode, changer: (v) => setState(() => _periode = v)),
                const SizedBox(height: 10),
                ChoixSelection(selection: _selection, classes: classes, changer: setState),
              ]),
            ),
          ],
        );
      },
    );
  }
}

// ---------------- Statistiques ----------------

class EcranStatistiques extends StatefulWidget {
  const EcranStatistiques({super.key});
  @override
  State<EcranStatistiques> createState() => _EcranStatistiquesState();
}

class _EcranStatistiquesState extends State<EcranStatistiques> {
  String _vue = 'etablissement';
  String _periode = 'S1';
  String? _classe;
  String? _matiere;

  @override
  Widget build(BuildContext context) {
    return Charge<List<Map<String, dynamic>>>(
      charger: chargerClasses,
      construire: (context, classes, _) {
        final classeId = _classe ?? (classes.isEmpty ? null : classes.first['id'] as String);
        return Column(children: [
          _filtres([
            SegmentedButton<String>(
              segments: const [
                ButtonSegment(value: 'etablissement', label: Text('Établ.')),
                ButtonSegment(value: 'classe', label: Text('Classe')),
                ButtonSegment(value: 'matiere', label: Text('Matière')),
              ],
              selected: {_vue},
              onSelectionChanged: (s) => setState(() => _vue = s.first),
            ),
            ChoixPeriode(valeur: _periode, changer: (v) => setState(() => _periode = v)),
            if (_vue != 'etablissement' && classeId != null)
              Choix<String>(
                libelle: 'Classe',
                valeur: classeId,
                options: [for (final c in classes) (c['id'] as String, c['nom'] as String)],
                changer: (v) => setState(() {
                  _classe = v;
                  _matiere = null;
                }),
              ),
            if (_vue == 'matiere' && classeId != null)
              Charge<List>(
                key: ValueKey('mat|$classeId'),
                charger: () async => await Api.i.get('/matieres?classeId=$classeId') as List,
                construire: (context, matieres, _) => Choix<String>(
                  libelle: 'Matière',
                  valeur: _matiere,
                  options: [for (final m in matieres.cast<Map>()) (m['id'] as String, m['nom'] as String)],
                  changer: (v) => setState(() => _matiere = v),
                ),
              ),
          ]),
          Expanded(
            child: switch (_vue) {
              'etablissement' => _StatsEtablissement(key: ValueKey('e|$_periode'), periode: _periode),
              'classe' when classeId != null => _StatsClasse(key: ValueKey('c|$classeId|$_periode'), classeId: classeId, periode: _periode),
              'matiere' when _matiere != null => StatsMatiere(key: ValueKey('m|$_matiere|$_periode'), matiereId: _matiere!, periode: _periode),
              _ => const Defilement(enfants: [Carte(enfant: Vide('Choisissez une matière'))]),
            },
          ),
        ]);
      },
    );
  }
}

class _StatsEtablissement extends StatelessWidget {
  const _StatsEtablissement({super.key, required this.periode});
  final String periode;

  @override
  Widget build(BuildContext context) {
    return Charge<Map>(
      charger: () async => await Api.i.get('/statistiques/etablissement?periode=$periode') as Map,
      construire: (context, s, recharger) {
        final r = s['resume'] as Map;
        if (r['effectif'] == 0) return const Defilement(enfants: [Carte(enfant: Vide('Pas encore de notes sur cette période'))]);
        String eleves(List l) => l.isEmpty ? '—' : l.map((e) => '${e['nom']} ${e['prenoms']} (${e['classe']['nom']}, ${note(e['moyenne'] as num?)})').join('\n');
        String classe(Map? c) => c == null ? '—' : '${c['nom']} (${note(c['moyenneGenerale'] as num?)})';
        return Defilement(rafraichir: recharger, enfants: [
          GrilleIndicateurs(enfants: [
            Indicateur(libelle: 'Moyenne générale', valeur: note(r['moyenne'] as num?), accent: true, detail: '${r['effectif']} élèves'),
            Indicateur(libelle: 'Réussite', valeur: pourcent(r['tauxReussite'] as num?), detail: '${r['reussis']} à 10 ou plus'),
            Indicateur(libelle: 'Min – max', valeur: '${note(r['min'] as num?)} – ${note(r['max'] as num?)}'),
            Indicateur(libelle: 'Écart-type', valeur: note(r['ecartType'] as num?)),
          ]),
          Carte(
            titre: 'Premiers et derniers',
            enfant: Column(children: [
              LigneInfo('Premier', eleves(s['premier'] as List), gras: true),
              LigneInfo('Dernier', eleves(s['dernier'] as List)),
              LigneInfo('Première classe', classe(s['premiereClasse'] as Map?), gras: true),
              LigneInfo('Dernière classe', classe(s['derniereClasse'] as Map?)),
            ]),
          ),
          Carte(titre: 'Répartition des moyennes', enfant: Repartition(s['repartition'] as List)),
          Carte(titre: 'Filles et garçons', enfant: ParSexe(s['parSexe'] as List)),
          Carte(
            titre: 'Classes',
            sansMarge: true,
            enfant: Column(children: [
              for (final c in (s['classes'] as List).cast<Map>())
                ListTile(
                  leading: SizedBox(width: 36, child: Text(rang(c['rang'] as Map?))),
                  title: Text(c['nom'] as String),
                  subtitle: Text('${c['effectif']} élèves · réussite ${pourcent(c['tauxReussite'] as num?)}'),
                  trailing: Text(note(c['moyenneGenerale'] as num?),
                      style: TextStyle(fontWeight: FontWeight.w700, color: couleurNote(context, c['moyenneGenerale'] as num?))),
                ),
            ]),
          ),
          Carte(
            titre: 'Moyenne par matière',
            enfant: BarresMoyennes([for (final m in (s['matieres'] as List).cast<Map>()) (m['nom'] as String, m['moyenne'] as num?)]),
          ),
        ]);
      },
    );
  }
}

class _StatsClasse extends StatelessWidget {
  const _StatsClasse({super.key, required this.classeId, required this.periode});
  final String classeId;
  final String periode;

  @override
  Widget build(BuildContext context) {
    return Charge<Map>(
      charger: () async => await Api.i.get('/statistiques/classe?classeId=$classeId&periode=$periode') as Map,
      construire: (context, s, recharger) {
        final p = s['profil'] as Map;
        if (p['moyenneGenerale'] == null) return const Defilement(enfants: [Carte(enfant: Vide('Pas encore de notes sur cette période'))]);
        return Defilement(rafraichir: recharger, enfants: [
          GrilleIndicateurs(enfants: [
            Indicateur(libelle: 'Moyenne', valeur: note(p['moyenneGenerale'] as num?), accent: true, detail: '${p['effectif']} élèves'),
            Indicateur(libelle: 'Réussite', valeur: pourcent(p['tauxReussite'] as num?), detail: '${p['nombreMoyennes']} moyennes'),
            Indicateur(libelle: 'Min – max', valeur: '${note(p['min'] as num?)} – ${note(p['max'] as num?)}'),
            Indicateur(libelle: 'Écart-type', valeur: note(p['ecartType'] as num?)),
          ]),
          Carte(titre: 'Évolution de la moyenne', enfant: Evolution(s['evolution'] as List)),
          Carte(titre: 'Répartition des moyennes', enfant: Repartition(s['repartition'] as List)),
          Carte(titre: 'Filles et garçons', enfant: ParSexe(s['parSexe'] as List)),
          Carte(
            titre: 'Moyenne par matière',
            enfant: BarresMoyennes([
              for (final m in (s['matieres'] as List).cast<Map>()) (m['nom'] as String, m['evaluee'] == true ? m['moyenne'] as num? : null)
            ]),
          ),
          Carte(
            titre: 'Classement de la classe',
            sansMarge: true,
            enfant: Column(children: [
              for (final e in (s['classement'] as List).cast<Map>())
                ListTile(
                  leading: SizedBox(width: 44, child: Text(rang(e['rang'] as Map?))),
                  title: Text('${e['nom']} ${e['prenoms']}'),
                  trailing: Text(note(e['moyenne'] as num?), style: TextStyle(fontWeight: FontWeight.w700, color: couleurNote(context, e['moyenne'] as num?))),
                ),
            ]),
          ),
        ]);
      },
    );
  }
}

// ---------------- Classement général ----------------

class EcranClassement extends StatefulWidget {
  const EcranClassement({super.key});
  @override
  State<EcranClassement> createState() => _EcranClassementState();
}

class _EcranClassementState extends State<EcranClassement> {
  String _periode = 'S1';
  String _classe = '';

  @override
  Widget build(BuildContext context) {
    return Charge<Map>(
      key: ValueKey(_periode),
      charger: () async => await Api.i.get('/statistiques/etablissement?periode=$_periode') as Map,
      construire: (context, s, recharger) {
        final tous = (s['classement'] as List).cast<Map>();
        final dernierRang = tous.isEmpty ? null : tous.last['rang']['rang'];
        final lignes = tous.where((e) => _classe.isEmpty || e['classe']['id'] == _classe).toList();
        final c = context.c;
        return Column(children: [
          _filtres([
            ChoixPeriode(valeur: _periode, changer: (v) => setState(() => _periode = v)),
            Choix<String>(
              libelle: 'Classe',
              valeur: _classe,
              options: [('', 'Toutes'), for (final k in (s['classes'] as List).cast<Map>()) (k['id'] as String, k['nom'] as String)],
              changer: (v) => setState(() => _classe = v ?? ''),
            ),
          ]),
          Expanded(
            child: Defilement(rafraichir: recharger, enfants: [
              Carte(
                titre: '${libellePeriode(_periode)} · ${tous.length} élèves classés',
                sansMarge: true,
                enfant: lignes.isEmpty
                    ? const Vide('Aucun élève classé')
                    : Column(children: [
                        for (final e in lignes)
                          Container(
                            color: e['rang']['rang'] == 1
                                ? c.succes.withValues(alpha: 0.07)
                                : (e['rang']['rang'] == dernierRang && tous.length > 1 ? c.danger.withValues(alpha: 0.07) : null),
                            child: ListTile(
                              leading: SizedBox(width: 48, child: Text(rang(e['rang'] as Map?), style: const TextStyle(fontWeight: FontWeight.w700))),
                              title: Text('${e['nom']} ${e['prenoms']}'),
                              subtitle: Text('${e['classe']['nom']} · ${rang(e['rangClasse'] as Map?)} de la classe'),
                              trailing: Text(note(e['moyenne'] as num?),
                                  style: TextStyle(fontWeight: FontWeight.w700, color: couleurNote(context, e['moyenne'] as num?))),
                            ),
                          ),
                      ]),
              ),
            ]),
          ),
        ]);
      },
    );
  }
}

// ---------------- Tableau d'honneur ----------------

/// Élèves dont la moyenne de la période atteint le seuil réglé dans les Paramètres.
class EcranTableauHonneur extends StatefulWidget {
  const EcranTableauHonneur({super.key});
  @override
  State<EcranTableauHonneur> createState() => _EcranTableauHonneurState();
}

class _EcranTableauHonneurState extends State<EcranTableauHonneur> {
  String _periode = 'T1';
  String _classe = '';

  String get _filtre => 'periode=$_periode${_classe.isEmpty ? '' : '&classeId=$_classe'}';

  @override
  Widget build(BuildContext context) {
    return Charge<List<Map<String, dynamic>>>(
      charger: chargerClasses,
      construire: (context, classes, _) => Column(
        children: [
          _filtres([
            ChoixPeriode(valeur: _periode, changer: (v) => setState(() => _periode = v)),
            Choix<String>(
              libelle: 'Classe',
              valeur: _classe,
              options: [('', 'Toutes les classes'), for (final k in classes) (k['id'] as String, k['nom'] as String)],
              changer: (v) => setState(() => _classe = v ?? ''),
            ),
          ]),
          Expanded(
            child: Charge<Map>(
              key: ValueKey(_filtre),
              charger: () async => await Api.i.get('/tableau-honneur?$_filtre') as Map,
              construire: (context, t, recharger) {
                final c = context.c;
                final total = t['total'] as int? ?? 0;
                final avecEleves = (t['classes'] as List).cast<Map>().where((k) => (k['eleves'] as List).isNotEmpty).toList();
                return Defilement(
                  rafraichir: recharger,
                  enfants: [
                    Carte(
                      enfant: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Text(
                            '$total élève(s) au tableau d\'honneur · ${libellePeriode(_periode)} · ${t['annee']}',
                            style: const TextStyle(fontWeight: FontWeight.w600),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Moyenne minimale : ${note(t['seuil'] as num?)}. Elle se règle dans les Paramètres.',
                            style: TextStyle(color: c.encre2, fontSize: 13),
                          ),
                          const SizedBox(height: 12),
                          Row(
                            children: [
                              Expanded(
                                child: OutlinedButton.icon(
                                  icon: const Icon(Icons.description_outlined, size: 18),
                                  label: const Text('Liste PDF'),
                                  onPressed: total == 0 ? null : () => agir(context, () => Api.i.ouvrirDocument('/tableau-honneur/pdf?$_filtre&format=liste')),
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: FilledButton.icon(
                                  icon: const Icon(Icons.military_tech_outlined, size: 18),
                                  label: const Text('Certificats'),
                                  onPressed: total == 0
                                      ? null
                                      : () => agir(context, () => Api.i.ouvrirDocument('/tableau-honneur/pdf?$_filtre&format=certificats')),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    if (total == 0)
                      Carte(
                        enfant: Vide("Aucun élève au tableau d'honneur", texte: "Aucune moyenne n'atteint ${note(t['seuil'] as num?)} pour cette période."),
                      ),
                    for (final k in avecEleves)
                      Carte(
                        titre: '${k['nom']} · ${(k['eleves'] as List).length} sur ${k['effectif']}',
                        sansMarge: true,
                        enfant: Column(
                          children: [
                            for (final e in (k['eleves'] as List).cast<Map>())
                              ListTile(
                                leading: SizedBox(
                                  width: 48,
                                  child: Text(rang(e['rang'] as Map?), style: const TextStyle(fontWeight: FontWeight.w700)),
                                ),
                                title: Text('${e['nom']} ${e['prenoms']}'),
                                subtitle: Text('${e['matricule']} · ${e['sexe']}'),
                                trailing: Text(note(e['moyenne'] as num?), style: const TextStyle(fontWeight: FontWeight.w700)),
                              ),
                          ],
                        ),
                      ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
