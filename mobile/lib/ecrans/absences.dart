import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../api.dart';
import '../etat.dart';
import '../theme.dart';
import '../widgets.dart';
import 'emploi_du_temps.dart' show duree;
import 'organisation.dart';

// Absences et justifications : filtres combinables, totaux en heures et minutes, détail et historique de
// chaque absence. Le SG justifie une ou plusieurs absences d'un même élève (une justification pour chacune),
// avec des pièces : photo prise sur le moment, image de la galerie ou PDF.

const _taille = 50;
const _maxPieces = 5;

String _iso(DateTime d) => '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

String _date(String iso) {
  const jours = ['', 'lun.', 'mar.', 'mer.', 'jeu.', 'ven.', 'sam.', 'dim.'];
  final d = DateTime.parse(iso);
  return '${jours[d.weekday]} ${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';
}

String _pluriel(int n, String mot, [String? pluriel]) => '$n ${n > 1 ? (pluriel ?? '${mot}s') : mot}';

/// Pastille d'état : fond, icône et mot (la couleur seule ne suffit pas).
class _PastilleEtat extends StatelessWidget {
  const _PastilleEtat(this.justification);
  final Map? justification;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final j = justification;
    final couleur = j == null ? c.danger : c.succes;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(color: couleur.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(999)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(j == null ? Icons.error_outline : Icons.check_circle_outline, size: 14, color: couleur),
          const SizedBox(width: 4),
          Flexible(
            child: Text(
              j == null ? 'Non justifiée' : 'Justifiée · ${j['motif']}',
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: couleur, fontSize: 12, fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
  }
}

String _dateLongue(String iso) {
  const jours = ['', 'Lundi', 'Mardi', 'Mercredi', 'Jeudi', 'Vendredi', 'Samedi', 'Dimanche'];
  final d = DateTime.parse(iso);
  return '${jours[d.weekday]} ${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';
}

String _quand(String iso) {
  final d = DateTime.parse(iso).toLocal();
  return '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year} à ${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
}

class EcranAbsences extends StatefulWidget {
  const EcranAbsences({super.key, this.etat});

  /// « NON_JUSTIFIEE » : l'entrée « Justifications » du menu.
  final String? etat;

  @override
  State<EcranAbsences> createState() => _EcranAbsencesState();
}

class _EcranAbsencesState extends State<EcranAbsences> with _ActionsAbsences<EcranAbsences> {
  @override
  void _change() => setState(() => _version++);

  String? _classe;
  String? _matiere; // nom : la même matière existe dans plusieurs classes
  late String? _etat = widget.etat;
  String _tri = 'date';
  DateTime? _du;
  DateTime? _au;
  final _recherche = TextEditingController();
  int _version = 0;
  final _selection = <String, Map>{};
  final _lignes = <Map>[];
  Map? _page;
  bool _charge = false;

  String _chemin(int page) {
    final p = {
      'classeId': ?_classe,
      'matiere': ?_matiere,
      'etat': ?_etat,
      'tri': _tri,
      'sens': _tri == 'date' ? 'desc' : 'asc',
      if (_du != null) 'du': _iso(_du!),
      if (_au != null) 'au': _iso(_au!),
      if (_recherche.text.trim().isNotEmpty) 'q': _recherche.text.trim(),
      'page': '$page',
      'taille': '$_taille',
    };
    return '/absences?${Uri(queryParameters: p).query}';
  }

  bool get _filtreActif => _classe != null || _matiere != null || _etat != null || _du != null || _au != null || _recherche.text.trim().isNotEmpty;

  void _reinitialiser() => _filtrer(() {
    _classe = null;
    _matiere = null;
    _etat = null;
    _du = null;
    _au = null;
    _recherche.clear();
  });

  /// Mêmes filtres que la liste, au format demandé.
  Future<void> _exporter(String format) {
    final q = Uri.parse(_chemin(0)).queryParameters.map((k, v) => MapEntry(k, v))
      ..remove('page')
      ..remove('taille')
      ..['format'] = format;
    return agir(context, () => Api.i.ouvrirDocument('/absences/export?${Uri(queryParameters: q).query}'));
  }

  /// Raccourcis de période : aujourd'hui, la semaine (depuis lundi), le mois, toute l'année.
  List<(String, DateTime?, DateTime?)> get _periodes {
    final n = DateTime.now();
    final auj = DateTime(n.year, n.month, n.day);
    return [
      ("Aujourd'hui", auj, auj),
      ('Cette semaine', auj.subtract(Duration(days: auj.weekday - 1)), auj),
      ('Ce mois', DateTime(auj.year, auj.month), auj),
      ("Toute l'année", null, null),
    ];
  }

  Future<Map> _premiere() async {
    final p = await Api.i.get(_chemin(0)) as Map;
    _page = p;
    _lignes
      ..clear()
      ..addAll((p['lignes'] as List).cast<Map>());
    _selection.clear();
    return p;
  }

  Future<void> _suite() async {
    if (_charge || _page == null) return;
    setState(() => _charge = true);
    try {
      final p = await Api.i.get(_chemin((_page!['page'] as int) + 1)) as Map;
      setState(() {
        _page = p;
        _lignes.addAll((p['lignes'] as List).cast<Map>());
      });
    } finally {
      if (mounted) setState(() => _charge = false);
    }
  }

  void _filtrer(VoidCallback f) => setState(() {
    f();
    _version++;
  });

  void _basculer(Map l) {
    final autre = _selection.isNotEmpty && _selection.values.first['inscriptionId'] != l['inscriptionId'];
    if (autre) {
      message(context, 'Une justification concerne les absences d\'un seul élève.', erreur: true);
      return;
    }
    setState(() => _selection.containsKey(l['id']) ? _selection.remove(l['id']) : _selection[l['id'] as String] = l);
  }

  @override
  Widget build(BuildContext context) {
    final sg = Etat.i.estSG;
    return Charge<List<Map<String, dynamic>>>(
      charger: chargerClasses,
      construire: (context, toutes, _) {
        final classes = [...toutes]
          ..sort((x, y) {
            final n = (x['niveau'] as int).compareTo(y['niveau'] as int);
            return n != 0 ? n : (x['nom'] as String).compareTo(y['nom'] as String);
          });
        return Charge<Map>(
          key: ValueKey('$_version'),
          charger: _premiere,
          construire: (context, _, recharger) {
            final c = context.c;
            final p = _page!;
            final t = p['totaux'] as Map;
            final eleve = _selection.isEmpty ? null : _selection.values.first;
            final minutesSel = _selection.values.fold<int>(0, (n, l) => n + (l['duree'] as int));
            return Defilement(
              rafraichir: recharger,
              bas: sg && eleve != null
                  ? Card(
                      margin: EdgeInsets.zero,
                      elevation: 6,
                      child: Padding(
                        padding: const EdgeInsets.all(10),
                        child: Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    '${_pluriel(_selection.length, 'absence sélectionnée', 'absences sélectionnées')} · ${duree(minutesSel)}',
                                    style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
                                  ),
                                  Text(
                                    '${eleve['nom']} ${eleve['prenoms']} · une justification couvre un seul élève',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(color: c.encre2, fontSize: 11.5),
                                  ),
                                ],
                              ),
                            ),
                            TextButton(onPressed: () => setState(_selection.clear), child: const Text('Annuler')),
                            FilledButton.icon(
                              onPressed: () => _justifier([..._selection.values]),
                              icon: const Icon(Icons.verified_user_outlined, size: 18),
                              label: const Text('Justifier'),
                            ),
                          ],
                        ),
                      ),
                    )
                  : null,
              enfants: [
                _filtres(context, classes),
                Row(
                  children: [
                    Expanded(child: _total(context, 'Total', t['minutes'] as int, null, _pluriel(t['absences'] as int, 'séance', 'séances'), null)),
                    const SizedBox(width: 8),
                    Expanded(child: _total(context, 'Justifiées', t['minutesJustifiees'] as int, c.succes, null, 'JUSTIFIEE')),
                    const SizedBox(width: 8),
                    Expanded(child: _total(context, 'Non justifiées', t['minutesNonJustifiees'] as int, c.danger, null, 'NON_JUSTIFIEE')),
                  ],
                ),
                Row(
                  children: [
                    PopupMenuButton<String>(
                      tooltip: 'Trier',
                      initialValue: _tri,
                      onSelected: (v) => _filtrer(() => _tri = v),
                      itemBuilder: (_) => const [
                        PopupMenuItem(value: 'date', child: Text('Par date (récentes)')),
                        PopupMenuItem(value: 'eleve', child: Text('Par élève')),
                        PopupMenuItem(value: 'duree', child: Text('Par durée')),
                        PopupMenuItem(value: 'etat', child: Text('Par état')),
                      ],
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.sort, size: 18, color: c.encre2),
                            const SizedBox(width: 4),
                            Text(switch (_tri) {
                              'eleve' => 'Par élève',
                              'duree' => 'Par durée',
                              'etat' => 'Par état',
                              _ => 'Par date',
                            }, style: const TextStyle(fontWeight: FontWeight.w600)),
                            const Icon(Icons.arrow_drop_down),
                          ],
                        ),
                      ),
                    ),
                    const Spacer(),
                    if ((p['total'] as int) > 0)
                      PopupMenuButton<String>(
                        tooltip: 'Exporter',
                        onSelected: _exporter,
                        itemBuilder: (_) => const [PopupMenuItem(value: 'xlsx', child: Text('Excel')), PopupMenuItem(value: 'pdf', child: Text('PDF'))],
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.download, size: 18, color: Theme.of(context).colorScheme.primary),
                              const SizedBox(width: 4),
                              Text(
                                'Exporter',
                                style: TextStyle(fontWeight: FontWeight.w600, color: Theme.of(context).colorScheme.primary),
                              ),
                            ],
                          ),
                        ),
                      ),
                  ],
                ),
                if (_lignes.isEmpty)
                  Carte(
                    enfant: Column(
                      children: [
                        Vide(
                          _filtreActif ? 'Aucune absence avec ces filtres' : 'Aucune absence relevée',
                          texte: _filtreActif ? null : "Les absences apparaissent ici dès qu'un appel est enregistré.",
                        ),
                        if (_filtreActif) TextButton(onPressed: _reinitialiser, child: const Text('Réinitialiser les filtres')),
                      ],
                    ),
                  ),
                for (final (i, l) in _lignes.indexed) ...[
                  if (_tri == 'date' && (i == 0 || _lignes[i - 1]['date'] != l['date']))
                    Padding(
                      padding: const EdgeInsets.only(top: 4, left: 2),
                      child: Text(
                        '${_dateLongue(l['date'] as String)} · ${_pluriel(_lignes.where((x) => x['date'] == l['date']).length, 'absence')}',
                        style: TextStyle(color: c.encre2, fontSize: 12.5, fontWeight: FontWeight.w700),
                      ),
                    ),
                  _carte(context, l, sg),
                ],
                if (_lignes.length < (p['total'] as int))
                  Center(
                    child: TextButton.icon(
                      onPressed: _charge ? null : _suite,
                      icon: _charge ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.expand_more),
                      label: Text('Voir plus (${_lignes.length} sur ${p['total']})'),
                    ),
                  ),
                if (sg)
                  Center(
                    child: TextButton.icon(onPressed: _motifs, icon: const Icon(Icons.tune, size: 18), label: const Text('Gérer les motifs')),
                  ),
              ],
            );
          },
        );
      },
    );
  }

  Widget _filtres(BuildContext context, List<Map<String, dynamic>> classes) {
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Choix<String>(
                    libelle: 'Classe',
                    valeur: _classe ?? '',
                    options: [('', 'Toutes'), for (final c in classes) (c['id'] as String, c['nom'] as String)],
                    changer: (v) => _filtrer(() => _classe = v == null || v.isEmpty ? null : v),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Charge<List>(
                    key: const ValueKey('matieres'),
                    charger: () async => await Api.i.get('/matieres') as List,
                    construire: (context, matieres, _) {
                      final noms = {for (final m in matieres.cast<Map>()) m['nom'] as String}.toList()..sort();
                      return Choix<String>(
                        libelle: 'Matière',
                        valeur: _matiere ?? '',
                        options: [('', 'Toutes'), for (final m in noms) (m, m)],
                        changer: (v) => _filtrer(() => _matiere = v == null || v.isEmpty ? null : v),
                      );
                    },
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            SegmentedButton<String>(
              segments: const [
                ButtonSegment(value: '', label: Text('Toutes')),
                ButtonSegment(value: 'NON_JUSTIFIEE', label: Text('Non justifiées')),
                ButtonSegment(value: 'JUSTIFIEE', label: Text('Justifiées')),
              ],
              selected: {_etat ?? ''},
              showSelectedIcon: false,
              onSelectionChanged: (s) => _filtrer(() => _etat = s.first.isEmpty ? null : s.first),
            ),
            const SizedBox(height: 10),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  for (final (libelle, du, au) in _periodes) ...[
                    ChoiceChip(
                      label: Text(libelle),
                      showCheckmark: false,
                      selected: _du == du && _au == au,
                      onSelected: (_) => _filtrer(() {
                        _du = du;
                        _au = au;
                      }),
                    ),
                    const SizedBox(width: 6),
                  ],
                  Builder(
                    builder: (context) {
                      // Plage choisie à la main : la pastille la montre.
                      final libre = _du != null && !_periodes.any((x) => x.$2 == _du && x.$3 == _au);
                      String court(DateTime d) => '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}';
                      return ChoiceChip(
                        avatar: const Icon(Icons.date_range, size: 18),
                        label: Text(libre ? '${court(_du!)} – ${court(_au ?? DateTime.now())}' : 'Dates…'),
                        showCheckmark: false,
                        selected: libre,
                        onSelected: (_) async {
                          final n = DateTime.now();
                          final plage = await showDateRangePicker(
                            context: context,
                            firstDate: DateTime(2020),
                            lastDate: DateTime(n.year, n.month, n.day),
                            initialDateRange: _du == null ? null : DateTimeRange(start: _du!, end: _au ?? DateTime(n.year, n.month, n.day)),
                            helpText: 'Période',
                            saveText: 'Appliquer',
                          );
                          if (plage == null) return;
                          _filtrer(() {
                            _du = plage.start;
                            _au = plage.end;
                          });
                        },
                      );
                    },
                  ),
                ],
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _recherche,
              textInputAction: TextInputAction.search,
              decoration: InputDecoration(
                labelText: 'Nom, prénom ou matricule',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _recherche.text.isEmpty ? null : IconButton(icon: const Icon(Icons.clear), onPressed: () => _filtrer(_recherche.clear)),
              ),
              onSubmitted: (_) => _filtrer(() {}),
            ),
            if (_filtreActif)
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(onPressed: _reinitialiser, child: const Text('Réinitialiser les filtres')),
              ),
          ],
        ),
      ),
    );
  }

  Widget _total(BuildContext context, String titre, int minutes, Color? couleur, String? detail, String? etat) {
    final c = context.c;
    final actif = _etat == etat;
    final primaire = Theme.of(context).colorScheme.primary;
    return Card(
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: BorderSide(color: actif ? primaire : c.bord, width: actif ? 2 : 1),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => _filtrer(() => _etat = etat),
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                titre.toUpperCase(),
                style: TextStyle(color: c.encre2, fontSize: 10.5, fontWeight: FontWeight.w700, letterSpacing: 0.4),
              ),
              const SizedBox(height: 2),
              Text(
                minutes == 0 ? '0 h' : duree(minutes),
                style: TextStyle(color: couleur, fontSize: 18, fontWeight: FontWeight.w800),
              ),
              if (detail != null) Text(detail, style: TextStyle(color: c.encre2, fontSize: 11)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _carte(BuildContext context, Map l, bool sg) {
    final c = context.c;
    final j = l['justification'] as Map?;
    final choisie = _selection.containsKey(l['id']);
    return Card(
      margin: EdgeInsets.zero,
      color: choisie ? Theme.of(context).colorScheme.primary.withValues(alpha: 0.10) : null,
      child: InkWell(
        onTap: () => _detail(l['id'] as String),
        onLongPress: sg && j == null ? () => _basculer(l) : null,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 6, 10),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text.rich(
                      TextSpan(
                        children: [
                          TextSpan(
                            text: '${l['nom']} ',
                            style: const TextStyle(fontWeight: FontWeight.w700),
                          ),
                          TextSpan(
                            text: '${l['prenoms']}',
                            style: TextStyle(color: c.encre2),
                          ),
                        ],
                      ),
                    ),
                    Text(
                      _tri == 'date' ? '${l['classe']}' : '${l['classe']} · ${_date(l['date'] as String)}',
                      style: TextStyle(color: c.encre2, fontSize: 12.5),
                    ),
                    Text('${l['matiere']} · ${l['debut']} – ${l['fin']} · ${duree(l['duree'] as int)}', style: const TextStyle(fontSize: 13.5)),
                    if (l['enseignantAbsent'] == true)
                      Text(
                        'Enseignant absent',
                        style: TextStyle(color: c.alerte, fontSize: 12, fontWeight: FontWeight.w600),
                      ),
                    const SizedBox(height: 4),
                    _PastilleEtat(j),
                  ],
                ),
              ),
              if (sg && j == null) Checkbox(value: choisie, onChanged: (_) => _basculer(l)) else Icon(Icons.chevron_right, color: c.encre3),
            ],
          ),
        ),
      ),
    );
  }

  // ---------- Motifs ----------

  Future<void> _motifs() async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) {
        final nouveau = TextEditingController();
        return StatefulBuilder(
          builder: (ctx, maj) => Charge<List>(
            charger: () async => await Api.i.get('/motifs-justification', annee: false) as List,
            construire: (ctx, liste, recharger) => Padding(
              padding: EdgeInsets.fromLTRB(16, 0, 16, MediaQuery.of(ctx).viewInsets.bottom + 16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text('Motifs de justification', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
                  Text(
                    'Un motif déjà utilisé n\'est jamais supprimé : retiré de la liste, il n\'est plus proposé.',
                    style: TextStyle(color: ctx.c.encre2, fontSize: 13),
                  ),
                  for (final m in liste.cast<Map>())
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text('${m['libelle']}'),
                      subtitle: Text(m['actif'] == true ? 'Proposé' : 'Retiré de la liste'),
                      value: m['actif'] == true,
                      onChanged: (v) async {
                        if (await agir(ctx, () => Api.i.put('/motifs-justification/${m['id']}', {'libelle': m['libelle'], 'actif': v}))) await recharger();
                      },
                    ),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: nouveau,
                          maxLength: 80,
                          decoration: const InputDecoration(labelText: 'Nouveau motif'),
                        ),
                      ),
                      const SizedBox(width: 8),
                      FilledButton(
                        onPressed: () async {
                          if (nouveau.text.trim().isEmpty) return;
                          if (await agir(ctx, () => Api.i.post('/motifs-justification', {'libelle': nouveau.text.trim()}))) {
                            nouveau.clear();
                            await recharger();
                          }
                        },
                        child: const Text('Ajouter'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

/// Justifier, corriger, consulter : commun aux écrans « Absences » et « Justifications ».
mixin _ActionsAbsences<T extends StatefulWidget> on State<T> {
  /// Après une justification, une correction ou un retrait : recharger la liste.
  void _change();

  // ---------- Justifier ----------

  Future<void> _justifier(List<Map> absences, {Map? existante}) async {
    final motifs = (await Api.i.get('/motifs-justification', annee: false) as List).cast<Map>();
    if (!mounted) return;
    var motifId = existante?['motifId'] as String? ?? '';
    var reception = existante == null ? DateTime.now() : DateTime.parse(existante['dateReception'] as String);
    final description = TextEditingController(text: existante?['description'] as String? ?? '');
    final fichiers = <File>[];
    final retirees = <String>{};
    final anciennes = existante == null ? <Map>[] : (existante['pieces'] as List).cast<Map>();
    final e = absences.first;
    final ok = await feuilleFormulaire(
      context,
      existante != null ? 'Corriger la justification' : 'Justifier ${_pluriel(absences.length, 'absence')}',
      (ctx, maj) {
        final c = ctx.c;
        Future<void> ajouter(Future<File?> Function() choisir) async {
          if (fichiers.length + anciennes.length - retirees.length >= _maxPieces) {
            message(ctx, 'Au plus $_maxPieces pièces justificatives.', erreur: true);
            return;
          }
          final f = await choisir();
          if (f == null) return;
          if (await f.length() > 3 * 1024 * 1024) {
            if (ctx.mounted) message(ctx, 'Ce fichier dépasse 3 Mo.', erreur: true);
            return;
          }
          maj(() => fichiers.add(f));
        }

        Future<File?> photo(ImageSource s) async {
          final x = await ImagePicker().pickImage(source: s, maxWidth: 1800, imageQuality: 80);
          return x == null ? null : File(x.path);
        }

        Future<File?> pdf() async {
          final r = await FilePicker.pickFiles(type: FileType.custom, allowedExtensions: ['pdf']);
          final chemin = r.isEmpty ? null : r.single.path;
          return chemin == null ? null : File(chemin);
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(color: c.surface2, borderRadius: BorderRadius.circular(8)),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('${e['nom']} ${e['prenoms']} · ${e['classe']}', style: const TextStyle(fontWeight: FontWeight.w700)),
                  for (final a in absences)
                    Text('${_date(a['date'] as String)} · ${a['matiere']} · ${a['debut']} – ${a['fin']}', style: TextStyle(color: c.encre2, fontSize: 12.5)),
                  if (absences.length > 1) Text('Chaque absence reçoit sa propre justification.', style: TextStyle(color: c.encre3, fontSize: 12)),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Choix<String>(
              libelle: 'Motif',
              valeur: motifId,
              options: [for (final m in motifs.where((m) => m['actif'] == true || m['id'] == motifId)) (m['id'] as String, m['libelle'] as String)],
              changer: (v) => maj(() => motifId = v ?? ''),
            ),
            const SizedBox(height: 10),
            OutlinedButton.icon(
              icon: const Icon(Icons.event, size: 18),
              label: Text('Justificatif reçu le ${_date(_iso(reception))}'),
              onPressed: () async {
                final d = await showDatePicker(context: ctx, firstDate: DateTime(2020), lastDate: DateTime.now(), initialDate: reception);
                if (d != null) maj(() => reception = d);
              },
            ),
            const SizedBox(height: 10),
            TextField(
              controller: description,
              maxLength: 1000,
              maxLines: 3,
              minLines: 1,
              decoration: const InputDecoration(labelText: 'Description (facultative)'),
            ),
            Text(
              'Pièces justificatives (facultatives)',
              style: TextStyle(color: c.encre2, fontWeight: FontWeight.w600, fontSize: 13),
            ),
            for (final p in anciennes)
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                dense: true,
                value: !retirees.contains(p['id']),
                title: Text('${p['nom']}', style: TextStyle(decoration: retirees.contains(p['id']) ? TextDecoration.lineThrough : null)),
                onChanged: (v) => maj(() => v == true ? retirees.remove(p['id']) : retirees.add(p['id'] as String)),
              ),
            for (final (i, f) in fichiers.indexed)
              ListTile(
                contentPadding: EdgeInsets.zero,
                dense: true,
                leading: const Icon(Icons.attach_file),
                title: Text(f.path.split(Platform.pathSeparator).last, overflow: TextOverflow.ellipsis),
                trailing: IconButton(icon: const Icon(Icons.close), onPressed: () => maj(() => fichiers.removeAt(i))),
              ),
            Wrap(
              spacing: 8,
              children: [
                OutlinedButton.icon(
                  onPressed: () => ajouter(() => photo(ImageSource.camera)),
                  icon: const Icon(Icons.photo_camera_outlined, size: 18),
                  label: const Text('Photo'),
                ),
                OutlinedButton.icon(
                  onPressed: () => ajouter(() => photo(ImageSource.gallery)),
                  icon: const Icon(Icons.photo_library_outlined, size: 18),
                  label: const Text('Galerie'),
                ),
                OutlinedButton.icon(onPressed: () => ajouter(pdf), icon: const Icon(Icons.picture_as_pdf_outlined, size: 18), label: const Text('PDF')),
              ],
            ),
          ],
        );
      },
      () async {
        if (motifId.isEmpty) throw ErreurApi(400, 'Choisissez le motif.');
        final donnees = existante == null
            ? {
                'absenceIds': [for (final a in absences) a['id']],
                'motifId': motifId,
                'description': description.text.trim().isEmpty ? null : description.text.trim(),
                'dateReception': _iso(reception),
              }
            : {
                'motifId': motifId,
                'description': description.text.trim().isEmpty ? null : description.text.trim(),
                'dateReception': _iso(reception),
                'piecesRetirees': retirees.toList(),
              };
        final r = await Api.i.envoyerFormulaire(
          existante == null ? '/absences/justifier' : '/justifications/${existante['id']}',
          champs: {'donnees': jsonEncode(donnees)},
          fichiers: {for (final (i, f) in fichiers.indexed) 'piece_$i': f},
        );
        if (mounted) message(context, existante == null ? (r['message'] as String? ?? 'Absences justifiées.') : 'Justification corrigée.');
      },
    );
    if (ok && mounted) _change();
  }

  // ---------- Détail ----------

  Future<void> _detail(String id) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.75,
        builder: (ctx, defilement) => Charge<Map>(
          charger: () async => await Api.i.get('/absences/$id') as Map,
          construire: (ctx, d, recharger) {
            final c = ctx.c;
            final l = d['absence'] as Map;
            final j = l['justification'] as Map?;
            final historique = (d['historique'] as List).cast<Map>();
            final sg = Etat.i.estSG;
            return ListView(
              controller: defilement,
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
              children: [
                Text('${l['nom']} ${l['prenoms']}', style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
                Text('${l['classe']} · matricule ${l['matricule']}', style: TextStyle(color: c.encre2)),
                const SizedBox(height: 8),
                LigneInfo('Date', _date(l['date'] as String)),
                LigneInfo('Séance', '${l['matiere']}, ${l['debut']} – ${l['fin']}'),
                LigneInfo('Durée', duree(l['duree'] as int)),
                if (l['enseignantAbsent'] == true) LigneInfo('Remarque', 'Enseignant absent (séance non assurée)'),
                const SizedBox(height: 10),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: (j == null ? c.danger : c.succes).withValues(alpha: 0.10),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: (j == null ? c.danger : c.succes).withValues(alpha: 0.4)),
                  ),
                  child: j == null
                      ? Text(
                          'Non justifiée',
                          style: TextStyle(color: c.danger, fontWeight: FontWeight.w700),
                        )
                      : Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Justifiée · ${j['motif']}',
                              style: TextStyle(color: c.succes, fontWeight: FontWeight.w700),
                            ),
                            if (j['description'] != null) Text('${j['description']}'),
                            Text(
                              'Justificatif reçu le ${_date(j['dateReception'] as String)}${j['par'] == null ? '' : ', enregistré par ${j['par']}'} le ${_quand(j['creeLe'] as String)}'
                              '${j['modifieLe'] == null ? '' : ', corrigé le ${_quand(j['modifieLe'] as String)}'}.',
                              style: TextStyle(color: c.encre2, fontSize: 12.5),
                            ),
                            for (final p in (j['pieces'] as List).cast<Map>())
                              TextButton.icon(
                                style: TextButton.styleFrom(padding: EdgeInsets.zero, alignment: Alignment.centerLeft),
                                onPressed: () => agir(ctx, () => Api.i.ouvrirDocument('/justifications/pieces/${p['id']}')),
                                icon: const Icon(Icons.description_outlined, size: 18),
                                label: Text('${p['nom']}', overflow: TextOverflow.ellipsis),
                              ),
                            if (sg)
                              Wrap(
                                spacing: 8,
                                children: [
                                  OutlinedButton(
                                    onPressed: () async {
                                      Navigator.pop(ctx);
                                      await _justifier([l], existante: j);
                                    },
                                    child: const Text('Corriger'),
                                  ),
                                  TextButton.icon(
                                    style: TextButton.styleFrom(foregroundColor: c.danger),
                                    onPressed: () async {
                                      if (!await confirmer(
                                        ctx,
                                        'Retirer la justification ?',
                                        "L'absence redeviendra non justifiée.",
                                        action: 'Retirer',
                                        danger: true,
                                      )) {
                                        return;
                                      }
                                      if (ctx.mounted && await agir(ctx, () => Api.i.delete('/justifications/${j['id']}'), succes: 'Justification retirée.')) {
                                        await recharger();
                                        if (mounted) _change();
                                      }
                                    },
                                    icon: const Icon(Icons.delete_outline, size: 18),
                                    label: const Text('Retirer'),
                                  ),
                                ],
                              ),
                          ],
                        ),
                ),
                const SizedBox(height: 14),
                Text(
                  'Historique',
                  style: TextStyle(color: c.encre2, fontWeight: FontWeight.w700),
                ),
                if (historique.isEmpty) Text("Aucune opération sur cette absence depuis l'appel.", style: TextStyle(color: c.encre3)),
                for (final h in historique)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text('${h['libelle']}'),
                    subtitle: Text('${_quand(h['creeLe'] as String)}${h['par'] == null ? '' : ' · ${h['par']}'}'),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }
}

/// Justifications : les absences non justifiées regroupées par élève, chacun avec « Justifier » ; et les
/// justifications enregistrées (motif, réception, pièces), à ouvrir pour corriger ou retirer.
class EcranJustifications extends StatefulWidget {
  const EcranJustifications({super.key});
  @override
  State<EcranJustifications> createState() => _EcranJustificationsState();
}

class _EcranJustificationsState extends State<EcranJustifications> with _ActionsAbsences<EcranJustifications> {
  static const _max = 200;
  String _onglet = 'NON_JUSTIFIEE';
  String? _classe;
  final _recherche = TextEditingController();
  int _version = 0;
  // Rien n'est coché au départ : le SG coche les absences que couvre le justificatif reçu.
  final _cochees = <String>{};

  @override
  void _change() => setState(() {
    _version++;
    _cochees.clear();
  });

  @override
  Widget build(BuildContext context) {
    final sg = Etat.i.estSG;
    return Charge<List<Map<String, dynamic>>>(
      charger: chargerClasses,
      construire: (context, toutes, _) {
        final classes = [...toutes]
          ..sort((x, y) {
            final n = (x['niveau'] as int).compareTo(y['niveau'] as int);
            return n != 0 ? n : (x['nom'] as String).compareTo(y['nom'] as String);
          });
        final p = {'etat': _onglet, 'classeId': ?_classe, if (_recherche.text.trim().isNotEmpty) 'q': _recherche.text.trim(), 'taille': '$_max'};
        return Charge<Map>(
          key: ValueKey('$_onglet|$_classe|${_recherche.text}|$_version'),
          charger: () async => await Api.i.get('/absences?${Uri(queryParameters: p).query}') as Map,
          construire: (context, page, recharger) {
            final c = context.c;
            final lignes = (page['lignes'] as List).cast<Map>();
            final total = page['total'] as int;
            final aJustifier = _onglet == 'NON_JUSTIFIEE';
            return Defilement(
              rafraichir: recharger,
              enfants: [
                SegmentedButton<String>(
                  segments: [
                    ButtonSegment(value: 'NON_JUSTIFIEE', label: Text(aJustifier ? 'À justifier · $total' : 'À justifier')),
                    ButtonSegment(value: 'JUSTIFIEE', label: Text(!aJustifier ? 'Enregistrées · $total' : 'Enregistrées')),
                  ],
                  selected: {_onglet},
                  showSelectedIcon: false,
                  onSelectionChanged: (s) => setState(() {
                    _onglet = s.first;
                    _cochees.clear();
                  }),
                ),
                Card(
                  margin: EdgeInsets.zero,
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      children: [
                        Choix<String>(
                          libelle: 'Classe',
                          valeur: _classe ?? '',
                          options: [('', 'Toutes les classes'), for (final x in classes) (x['id'] as String, x['nom'] as String)],
                          changer: (v) => setState(() => _classe = v == null || v.isEmpty ? null : v),
                        ),
                        const SizedBox(height: 10),
                        TextField(
                          controller: _recherche,
                          textInputAction: TextInputAction.search,
                          decoration: const InputDecoration(labelText: 'Élève (nom, prénom ou matricule)', prefixIcon: Icon(Icons.search)),
                          onSubmitted: (_) => setState(() {}),
                        ),
                      ],
                    ),
                  ),
                ),
                if (total > lignes.length)
                  Text(
                    '  $total absences : seules les ${lignes.length} plus récentes sont affichées. Choisissez une classe ou un élève.',
                    style: TextStyle(color: c.alerte, fontSize: 12.5),
                  ),
                if (lignes.isEmpty)
                  Carte(
                    enfant: Vide(
                      aJustifier ? 'Rien à justifier' : 'Aucune justification',
                      texte: aJustifier
                          ? 'Aucune absence non justifiée ne correspond à ces filtres.'
                          : 'Aucune justification enregistrée ne correspond à ces filtres.',
                    ),
                  ),
                if (aJustifier) ..._parEleve(context, lignes, sg) else ..._enregistrees(context, lignes),
              ],
            );
          },
        );
      },
    );
  }

  List<Widget> _parEleve(BuildContext context, List<Map> lignes, bool sg) {
    final c = context.c;
    final groupes = <String, List<Map>>{};
    for (final l in lignes) {
      groupes.putIfAbsent(l['inscriptionId'] as String, () => []).add(l);
    }
    final liste = groupes.values.toList()..sort((x, y) => '${x.first['nom']} ${x.first['prenoms']}'.compareTo('${y.first['nom']} ${y.first['prenoms']}'));
    return [
      for (final abs in liste)
        Card(
          margin: EdgeInsets.zero,
          clipBehavior: Clip.antiAlias,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                color: c.surface2,
                padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text.rich(
                            TextSpan(
                              children: [
                                TextSpan(
                                  text: '${abs.first['nom']} ',
                                  style: const TextStyle(fontWeight: FontWeight.w700),
                                ),
                                TextSpan(
                                  text: '${abs.first['prenoms']}',
                                  style: TextStyle(color: c.encre2),
                                ),
                              ],
                            ),
                          ),
                          Text(
                            '${abs.first['classe']} · ${_pluriel(abs.length, 'absence')} · ${duree(abs.fold<int>(0, (n, l) => n + (l['duree'] as int)))}',
                            style: TextStyle(color: c.danger, fontSize: 12.5, fontWeight: FontWeight.w600),
                          ),
                        ],
                      ),
                    ),
                    if (sg)
                      Builder(
                        builder: (context) {
                          final choisies = abs.where((l) => _cochees.contains(l['id'])).toList();
                          return FilledButton(
                            onPressed: choisies.isEmpty ? null : () => _justifier(choisies),
                            child: Text(choisies.isEmpty ? 'Justifier' : 'Justifier (${choisies.length})'),
                          );
                        },
                      ),
                  ],
                ),
              ),
              if (sg && abs.length > 1)
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton(
                    onPressed: () => setState(() {
                      final toutes = abs.every((l) => _cochees.contains(l['id']));
                      for (final l in abs) {
                        toutes ? _cochees.remove(l['id']) : _cochees.add(l['id'] as String);
                      }
                    }),
                    child: Text(abs.every((l) => _cochees.contains(l['id'])) ? 'Tout décocher' : 'Tout cocher'),
                  ),
                ),
              for (final l in abs)
                InkWell(
                  onTap: () => _detail(l['id'] as String),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(4, 2, 12, 2),
                    child: Row(
                      children: [
                        if (sg)
                          Checkbox(
                            value: _cochees.contains(l['id']),
                            onChanged: (v) => setState(() => v == true ? _cochees.add(l['id'] as String) : _cochees.remove(l['id'])),
                          )
                        else
                          const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('${_date(l['date'] as String)} · ${l['matiere']}', style: const TextStyle(fontSize: 13.5)),
                              Text('${l['debut']} – ${l['fin']} · ${duree(l['duree'] as int)}', style: TextStyle(color: c.encre2, fontSize: 12.5)),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
    ];
  }

  List<Widget> _enregistrees(BuildContext context, List<Map> lignes) {
    final c = context.c;
    return [
      for (final l in lignes)
        Card(
          margin: EdgeInsets.zero,
          child: InkWell(
            onTap: () => _detail(l['id'] as String),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Builder(
                builder: (context) {
                  final j = l['justification'] as Map;
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text.rich(
                        TextSpan(
                          children: [
                            TextSpan(
                              text: '${l['nom']} ',
                              style: const TextStyle(fontWeight: FontWeight.w700),
                            ),
                            TextSpan(
                              text: '${l['prenoms']}',
                              style: TextStyle(color: c.encre2),
                            ),
                          ],
                        ),
                      ),
                      Text(
                        '${l['classe']} · ${_date(l['date'] as String)} · ${l['matiere']} ${l['debut']} – ${l['fin']}',
                        style: TextStyle(color: c.encre2, fontSize: 12.5),
                      ),
                      const SizedBox(height: 4),
                      EtatTexte('Justifiée · ${j['motif']}', ton: 'succes'),
                      Text(
                        'Reçu le ${_date(j['dateReception'] as String)} · ${_pluriel((j['pieces'] as List).length, 'pièce')}${j['par'] == null ? '' : ' · ${j['par']}'}',
                        style: TextStyle(color: c.encre2, fontSize: 12.5),
                      ),
                    ],
                  );
                },
              ),
            ),
          ),
        ),
    ];
  }
}
