import 'package:flutter/material.dart';

import '../api.dart';
import '../doublons.dart';
import '../etat.dart';
import '../theme.dart';
import '../widgets.dart';
import 'eleves.dart';
import 'organisation.dart';

// « À vérifier » : doublons probables, matières sans enseignant, fiches incomplètes. Rien n'est
// bloquant ; chaque point se corrige depuis sa page, se fusionne, ou se marque « C'est normal ».

class EcranAVerifier extends StatefulWidget {
  const EcranAVerifier({super.key});
  @override
  State<EcranAVerifier> createState() => _EcranAVerifierState();
}

/// Rangement de chaque catégorie : section et couleur selon l'urgence (rouge : notes impossibles à saisir).
const _categories = {
  'matieres-sans-enseignant': ('notes', 'danger'),
  'matieres-enseignant-desactive': ('notes', 'danger'),
  'classes-sans-pp': ('notes', 'alerte'),
  'enseignants-doublons': ('doublons', 'alerte'),
  'eleves-doublons': ('doublons', 'alerte'),
  'matieres-doublons': ('doublons', 'alerte'),
  'eleves-naissance': ('fiches', 'info'),
  'eleves-sans-parent': ('fiches', 'info'),
};

const _themes = [
  ('notes', 'Saisie des notes et bulletins', Icons.menu_book_outlined),
  ('doublons', 'Doublons', Icons.content_copy_outlined),
  ('fiches', "Fiches d'élèves", Icons.person_off_outlined),
];

const _lignesVisibles = 5;

(String, String) _rangement(Map cat) => _categories[cat['code']] ?? ('fiches', 'info');

/// « Français (4e année Électricité) » → nom et classe.
(String, String?) _separer(String titre) {
  final m = RegExp(r'^(.*) \(([^()]+)\)$').firstMatch(titre);
  return m == null ? (titre, null) : (m.group(1)!, m.group(2));
}

class _EcranAVerifierState extends State<EcranAVerifier> {
  int _version = 0;
  bool _avecIgnores = false;
  String? _filtre;
  final _deplies = <String>{};

  Future<void> _marquer(Map p) async {
    final ok = await agir(context, () async {
      if (p['ignore'] == true) {
        await Api.i.delete('/verifications/ignorees?cle=${Uri.encodeQueryComponent(p['cle'] as String)}');
      } else {
        await Api.i.post('/verifications/ignorees', {'cle': p['cle'], 'libelle': p['titre']});
      }
    });
    if (ok) setState(() => _version++);
  }

  Future<void> _agir(Map action) async {
    final type = action['type'] as String;
    if (type == 'ouvrir') return ouvrirLien(context, action['lien'] as String?);
    final fait = await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (_) => EcranFusion(type: type == 'fusionner-enseignants' ? 'enseignants' : 'eleves', a: action['a'] as String, b: action['b'] as String)),
    );
    if (fait == true) setState(() => _version++);
  }

  /// Couleur pleine du bandeau, et texte lisible dessus (foncé en thème sombre, où ces couleurs sont claires).
  Color _couleur(BuildContext context, String ton) => switch (ton) {
        'danger' => context.c.danger,
        'alerte' => context.c.alerte,
        _ => Theme.of(context).colorScheme.primary,
      };
  Color _surCouleur(BuildContext context) => Theme.of(context).brightness == Brightness.dark ? const Color(0xFF0C1826) : Colors.white;

  int _actifs(Map cat) => (cat['points'] as List).where((p) => p['ignore'] != true).length;

  @override
  Widget build(BuildContext context) {
    return Charge<Map>(
      key: ValueKey('$_version-$_avecIgnores'),
      charger: () async => await Api.i.get('/verifications?ignores=$_avecIgnores') as Map,
      construire: (context, r, recharger) {
        final c = context.c;
        // Même ordre que les sections : les urgences d'abord.
        int rang(Map cat) => _themes.indexWhere((t) => t.$1 == _rangement(cat).$1) * 100 + _categories.keys.toList().indexOf(cat['code'] as String);
        final categories = (r['categories'] as List).cast<Map>().toList()..sort((x, y) => rang(x) - rang(y));
        final visibles = categories.where((cat) => _filtre == null || cat['code'] == _filtre).toList();
        return Defilement(rafraichir: recharger, enfants: [
          Text(
            "Ce qui mérite un coup d'œil, sans rien bloquer. Corrigez depuis la page concernée, ou marquez « C'est normal » pour ne plus le voir.",
            style: TextStyle(color: c.encre2),
          ),
          if ((r['ignores'] as num) > 0)
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: Text('Afficher les ${r['ignores']} point(s) jugés normaux'),
              value: _avecIgnores,
              onChanged: (v) => setState(() => _avecIgnores = v),
            ),
          if (categories.isEmpty) const Carte(enfant: Vide('Rien à vérifier', texte: 'Aucun doublon probable, aucune matière sans enseignant, aucune fiche incomplète.')),
          if (categories.isNotEmpty) _filtres(context, categories),
          for (final t in _themes)
            if (visibles.any((cat) => _rangement(cat).$1 == t.$1))
              Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Padding(
                  padding: const EdgeInsets.only(top: 4, bottom: 8),
                  child: Row(children: [
                    Icon(t.$3, size: 16, color: c.encre2),
                    const SizedBox(width: 6),
                    Text(t.$2.toUpperCase(), style: TextStyle(color: c.encre2, fontSize: 12, fontWeight: FontWeight.w700, letterSpacing: 0.6)),
                  ]),
                ),
                for (final cat in visibles.where((cat) => _rangement(cat).$1 == t.$1))
                  Padding(padding: const EdgeInsets.only(bottom: 12), child: _bloc(context, cat)),
              ]),
        ]);
      },
    );
  }

  /// Un bouton par catégorie, dans sa couleur : sert de résumé et de filtre.
  Widget _filtres(BuildContext context, List<Map> categories) {
    Widget puce(String texte, Color couleur, bool choisi, VoidCallback surAppui) => Padding(
          padding: const EdgeInsets.only(right: 8),
          child: Material(
            color: choisi ? couleur : couleur.withValues(alpha: 0.12),
            shape: const StadiumBorder(),
            child: InkWell(
              customBorder: const StadiumBorder(),
              onTap: surAppui,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                child: Text(texte, style: TextStyle(color: choisi ? _surCouleur(context) : couleur, fontWeight: FontWeight.w600, fontSize: 13)),
              ),
            ),
          ),
        );
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(children: [
        puce('Tout · ${categories.fold<int>(0, (n, cat) => n + _actifs(cat))}', Theme.of(context).colorScheme.onSurface, _filtre == null,
            () => setState(() => _filtre = null)),
        for (final cat in categories)
          puce('${cat['titre']} · ${_actifs(cat)}', _couleur(context, _rangement(cat).$2), _filtre == cat['code'],
              () => setState(() => _filtre = _filtre == cat['code'] ? null : cat['code'] as String)),
      ]),
    );
  }

  Widget _bloc(BuildContext context, Map cat) {
    final c = context.c;
    final ton = _rangement(cat).$2;
    final couleur = _couleur(context, ton);
    final sur = _surCouleur(context);
    final code = cat['code'] as String;
    final doublonsDeComptes = code == 'enseignants-doublons' || code == 'eleves-doublons';
    final points = (cat['points'] as List).cast<Map>().toList()
      ..sort((x, y) => (_separer(x['titre'] as String).$2 ?? '').compareTo(_separer(y['titre'] as String).$2 ?? ''));
    final tout = _deplies.contains(code);
    final montres = tout ? points : points.take(_lignesVisibles).toList();
    final reste = points.length - _lignesVisibles;

    final lignes = <Widget>[];
    String? classePrecedente;
    for (final p in montres) {
      final (nom, classe) = _separer(p['titre'] as String);
      // Rangés par classe : la classe n'est écrite qu'une fois pour ses points.
      if (!doublonsDeComptes && classe != null && classe != classePrecedente) {
        lignes.add(Container(
          width: double.infinity,
          color: c.surface2,
          padding: const EdgeInsets.fromLTRB(14, 8, 14, 8),
          child: Text(classe, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
        ));
      }
      classePrecedente = classe;
      lignes.add(_point(context, p, doublonsDeComptes ? p['titre'] as String : nom, doublonsDeComptes));
      lignes.add(Divider(height: 1, color: c.bord));
    }
    if (lignes.isNotEmpty) lignes.removeLast();

    return Card(
      clipBehavior: Clip.antiAlias,
      margin: EdgeInsets.zero,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Container(
          color: couleur,
          padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              if (ton == 'danger') ...[Icon(Icons.warning_amber_rounded, size: 18, color: sur), const SizedBox(width: 6)],
              Flexible(child: Text('${cat['titre']}', style: TextStyle(color: sur, fontWeight: FontWeight.w700, fontSize: 15))),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(color: sur.withValues(alpha: 0.22), borderRadius: BorderRadius.circular(20)),
                child: Text('${_actifs(cat)}', style: TextStyle(color: sur, fontWeight: FontWeight.w700, fontSize: 12)),
              ),
            ]),
            const SizedBox(height: 3),
            Text('${cat['explication']}', style: TextStyle(color: sur.withValues(alpha: 0.92), fontSize: 13)),
          ]),
        ),
        ...lignes,
        if (reste > 0)
          Material(
            color: couleur.withValues(alpha: 0.12),
            child: InkWell(
              onTap: () => setState(() => tout ? _deplies.remove(code) : _deplies.add(code)),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                  Icon(tout ? Icons.expand_less : Icons.expand_more, color: couleur, size: 20),
                  const SizedBox(width: 6),
                  Text(tout ? 'Voir moins' : 'Voir plus · $reste autre${reste > 1 ? 's' : ''}',
                      style: TextStyle(color: couleur, fontWeight: FontWeight.w700)),
                ]),
              ),
            ),
          ),
      ]),
    );
  }

  Widget _point(BuildContext context, Map p, String nom, bool doublonsDeComptes) {
    final c = context.c;
    final action = p['action'] as Map;
    final type = action['type'] as String;
    final noms = (p['titre'] as String).split(' et ');
    final fiches = (p['detail'] as String).split(' — ');
    final comparer = doublonsDeComptes && noms.length == 2 && fiches.length == 2;
    return Opacity(
      opacity: p['ignore'] == true ? 0.6 : 1,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 10, 8, 4),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          if (comparer)
            for (final i in [0, 1])
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Wrap(crossAxisAlignment: WrapCrossAlignment.center, spacing: 8, children: [
                    Text(noms[i], style: const TextStyle(fontWeight: FontWeight.w600)),
                    if (i == 0) Text('compte proposé à garder', style: TextStyle(color: c.succes, fontSize: 12, fontWeight: FontWeight.w600)),
                  ]),
                  Text(fiches[i], style: TextStyle(color: c.encre2, fontSize: 12.5)),
                ]),
              )
          else ...[
            Text(nom, style: const TextStyle(fontWeight: FontWeight.w600)),
            Text('${p['detail']}', style: TextStyle(color: c.encre2, fontSize: 12.5)),
          ],
          const SizedBox(height: 4),
          p['ignore'] == true
              ? const EtatTexte('Jugé normal')
              : p['gravite'] == 'FORTE'
                  ? const EtatTexte('À traiter', ton: 'alerte')
                  : const EtatTexte('À confirmer'),
          Wrap(spacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
            if (type == 'ouvrir' || type == 'fusionner-eleves' || Etat.i.estSG)
              OutlinedButton.icon(
                icon: Icon(type == 'ouvrir' ? Icons.edit_outlined : Icons.merge_type, size: 18),
                label: Text(type == 'ouvrir' ? 'Corriger' : 'Fusionner'),
                onPressed: () => _agir(action),
              ),
            TextButton.icon(
              icon: Icon(p['ignore'] == true ? Icons.undo : Icons.check, size: 18),
              label: Text(p['ignore'] == true ? 'Signaler de nouveau' : "C'est normal"),
              onPressed: () => _marquer(p),
            ),
          ]),
        ]),
      ),
    );
  }
}

/// Ouvre l'écran correspondant à une adresse du site (« /eleves/… », « /matieres?… »).
Future<void> ouvrirLien(BuildContext context, String? lien) async {
  if (lien == null) return;
  Widget? ecran;
  String titre = '';
  final eleve = RegExp(r'^/eleves/([^/?]+)').firstMatch(lien);
  if (eleve != null) {
    await Navigator.push(context, MaterialPageRoute(builder: (_) => FicheEleve(id: eleve.group(1)!)));
    return;
  }
  if (lien.startsWith('/matieres')) (ecran, titre) = (const EcranMatieres(), 'Matières');
  if (lien.startsWith('/classes')) (ecran, titre) = (const EcranClasses(), 'Classes');
  if (lien.startsWith('/enseignants')) (ecran, titre) = (const EcranEnseignants(), 'Enseignants');
  if (ecran == null) return;
  final page = ecran;
  await Navigator.push(
    context,
    MaterialPageRoute(builder: (ctx) => Scaffold(appBar: AppBar(title: Text(titre)), backgroundColor: ctx.c.fond, body: page)),
  );
}

// ---------------- Fusion ----------------

/// Fusion de deux fiches en double : la fiche gardée reprend tout ce qui était rattaché à l'autre.
class EcranFusion extends StatefulWidget {
  const EcranFusion({super.key, required this.type, required this.a, required this.b});

  /// « enseignants » ou « eleves »
  final String type;
  final String a, b;
  @override
  State<EcranFusion> createState() => _EcranFusionState();
}

class _EcranFusionState extends State<EcranFusion> {
  late List<String> _ids = [widget.a, widget.b];
  final Map<String, String> _choix = {};
  String _notes = 'garde';
  final _cle = nouvelleCleEnvoi();
  bool _envoi = false;

  Future<void> _fusionner() async {
    setState(() => _envoi = true);
    final ok = await agir(context, () async {
      final r = await Api.i.envoyer('POST', '/fusions/${widget.type}',
          corps: {'garde': _ids[0], 'autre': _ids[1], 'choix': _choix, if (widget.type == 'eleves') 'notes': _notes}, entetes: {'X-Envoi': _cle});
      if (mounted) message(context, r['message'] as String);
    });
    if (!mounted) return;
    setState(() => _envoi = false);
    if (ok) Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Scaffold(
      appBar: AppBar(title: Text(widget.type == 'enseignants' ? 'Fusionner deux comptes' : 'Fusionner deux fiches')),
      backgroundColor: c.fond,
      body: Charge<Map>(
        key: ValueKey(_ids.join(':')),
        copieImmediate: false,
        charger: () async => await Api.i.get('/fusions/${widget.type}?garde=${_ids[0]}&autre=${_ids[1]}') as Map,
        construire: (context, ap, recharger) {
          final differences = (ap['differences'] as List).cast<Map>();
          final possible = ap['possible'] != false;
          Widget cote(String titre, Map f, bool garde) => Expanded(
                child: Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: garde ? c.primairePale : c.surface2,
                    border: Border.all(color: c.bord),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(titre.toUpperCase(), style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: c.encre2)),
                    Text('${f['libelle']}', style: const TextStyle(fontWeight: FontWeight.w600)),
                    Text('${f['detail']}', style: TextStyle(fontSize: 12, color: c.encre2)),
                  ]),
                ),
              );
          return Defilement(
            rafraichir: recharger,
            bas: FilledButton.icon(
              icon: _envoi ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.merge_type),
              label: const Text('Fusionner'),
              onPressed: possible && !_envoi ? _fusionner : null,
            ),
            enfants: [
              Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                cote('Fiche gardée', ap['garde'] as Map, true),
                IconButton(
                  tooltip: "Garder plutôt l'autre fiche",
                  icon: const Icon(Icons.swap_horiz),
                  onPressed: () => setState(() {
                    _ids = [_ids[1], _ids[0]];
                    _choix.clear();
                  }),
                ),
                cote('Fiche absorbée', ap['autre'] as Map, false),
              ]),
              Carte(
                titre: 'Informations à garder',
                enfant: differences.isEmpty
                    ? Text('Les deux fiches portent les mêmes informations.', style: TextStyle(color: c.encre2))
                    : Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        for (final d in differences) ...[
                          Text('${d['libelle']}', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: c.encre2)),
                          RadioGroup<String>(
                            groupValue: _choix[d['cle']] ?? d['parDefaut'] as String,
                            onChanged: (v) => setState(() => _choix[d['cle'] as String] = v!),
                            child: Column(children: [
                              RadioListTile<String>(dense: true, contentPadding: EdgeInsets.zero, value: 'garde', title: Text('${d['garde']}')),
                              RadioListTile<String>(dense: true, contentPadding: EdgeInsets.zero, value: 'autre', title: Text('${d['autre']}')),
                            ]),
                          ),
                        ],
                      ]),
              ),
              if (ap['deplacements'] != null)
                Carte(
                  titre: 'Repris par la fiche gardée',
                  enfant: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    if ((ap['deplacements'] as List).isEmpty) Text("Rien n'est rattaché à la fiche absorbée.", style: TextStyle(color: c.encre2)),
                    for (final d in (ap['deplacements'] as List).cast<Map>()) Text('• ${d['nombre']} ${d['libelle']}'),
                  ]),
                ),
              if (ap['annees'] != null && (ap['annees'] as List).isNotEmpty)
                Carte(
                  titre: 'Inscriptions de la fiche absorbée',
                  enfant: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    for (final x in (ap['annees'] as List).cast<Map>())
                      Text('${x['annee']} · ${x['classeAutre']}, ${x['notesAutre']} note(s) : '
                          '${x['sort'] == 'déplacée' ? 'reprise telle quelle' : x['sort'] == 'réunie' ? "réunie avec l'inscription gardée" : 'classes différentes, fusion impossible'}'),
                  ]),
                ),
              if ((ap['conflits'] as num? ?? 0) > 0)
                Carte(
                  titre: 'Notes en double (même matière, même séquence)',
                  enfant: RadioGroup<String>(
                    groupValue: _notes,
                    onChanged: (v) => setState(() => _notes = v!),
                    child: const Column(children: [
                      RadioListTile<String>(dense: true, contentPadding: EdgeInsets.zero, value: 'garde', title: Text('Garder celles de la fiche gardée')),
                      RadioListTile<String>(dense: true, contentPadding: EdgeInsets.zero, value: 'autre', title: Text('Garder celles de la fiche absorbée')),
                    ]),
                  ),
                ),
              for (final m in (ap['avertissements'] as List).cast<String>())
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(border: Border.all(color: c.alerte.withValues(alpha: 0.4)), borderRadius: BorderRadius.circular(6)),
                  child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Icon(Icons.warning_amber_rounded, size: 18, color: c.alerte),
                    const SizedBox(width: 8),
                    Expanded(child: Text(m)),
                  ]),
                ),
              Text(
                "La fiche absorbée n'est pas effacée. Si la fusion était une erreur, le Proviseur peut la défaire en désapprouvant la décision.",
                style: TextStyle(fontSize: 12, color: c.encre3),
              ),
            ],
          );
        },
      ),
    );
  }
}

/// Choix du second compte de la même personne, puis fusion.
Future<bool> fusionnerEnseignant(BuildContext context, Map moi, List<Map> comptes) async {
  final autres = comptes.where((p) => p['id'] != moi['id'] && p['fusionneDansId'] == null).toList();
  final choisi = await showDialog<String>(
    context: context,
    builder: (ctx) => SimpleDialog(
      title: Text('Fusionner ${moi['prenom']} ${moi['nom']} avec…'),
      children: [
        for (final p in autres)
          SimpleDialogOption(
            onPressed: () => Navigator.pop(ctx, p['id'] as String),
            child: Text('${p['nom']} ${p['prenom']}${p['discipline'] != null ? ' · ${p['discipline']}' : ''}${p['actif'] == true ? '' : ' (désactivé)'}'),
          ),
      ],
    ),
  );
  if (choisi == null || !context.mounted) return false;
  return await Navigator.push<bool>(context, MaterialPageRoute(builder: (_) => EcranFusion(type: 'enseignants', a: moi['id'] as String, b: choisi))) ==
      true;
}

/// Recherche de la seconde fiche de l'élève, puis fusion.
Future<bool> fusionnerEleve(BuildContext context, String moi, String nom) async {
  final choisi = await showDialog<String>(context: context, builder: (_) => _RechercheEleve(moi: moi, nom: nom));
  if (choisi == null || !context.mounted) return false;
  return await Navigator.push<bool>(context, MaterialPageRoute(builder: (_) => EcranFusion(type: 'eleves', a: moi, b: choisi))) == true;
}

class _RechercheEleve extends StatefulWidget {
  const _RechercheEleve({required this.moi, required this.nom});
  final String moi, nom;
  @override
  State<_RechercheEleve> createState() => _RechercheEleveState();
}

class _RechercheEleveState extends State<_RechercheEleve> {
  late final _q = TextEditingController(text: widget.nom.split(' ').first);
  List<Map> _resultats = [];
  bool _charge = false;

  @override
  void initState() {
    super.initState();
    _chercher();
  }

  Future<void> _chercher() async {
    final t = _q.text.trim();
    if (t.length < 2) return setState(() => _resultats = []);
    setState(() => _charge = true);
    try {
      final r = await Api.i.get('/eleves?statut=TOUS&q=${Uri.encodeQueryComponent(t)}') as List;
      if (mounted) setState(() => _resultats = r.cast<Map>().where((i) => i['eleveId'] != widget.moi).toList());
    } catch (_) {
      if (mounted) setState(() => _resultats = []);
    } finally {
      if (mounted) setState(() => _charge = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('Fusionner ${widget.nom} avec…'),
      content: SizedBox(
        width: double.maxFinite,
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(
            controller: _q,
            decoration: const InputDecoration(labelText: "Nom de l'autre fiche", prefixIcon: Icon(Icons.search)),
            onSubmitted: (_) => _chercher(),
          ),
          const SizedBox(height: 8),
          if (_charge) const LinearProgressIndicator(),
          Flexible(
            child: ListView(shrinkWrap: true, children: [
              for (final i in _resultats)
                ListTile(
                  dense: true,
                  title: Text('${i['eleve']['nom']} ${i['eleve']['prenoms']}'),
                  subtitle: Text('${i['eleve']['matricule']} · ${i['classe']['nom']}'),
                  onTap: () => Navigator.pop(context, i['eleveId'] as String),
                ),
              if (!_charge && _resultats.isEmpty) const Padding(padding: EdgeInsets.all(8), child: Text('Aucune autre fiche trouvée.')),
            ]),
          ),
        ]),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Annuler')),
        FilledButton(onPressed: _chercher, child: const Text('Chercher')),
      ],
    );
  }
}
