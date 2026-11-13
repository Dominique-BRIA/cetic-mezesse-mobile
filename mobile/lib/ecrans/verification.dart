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

class _EcranAVerifierState extends State<EcranAVerifier> {
  int _version = 0;
  bool _avecIgnores = false;

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

  @override
  Widget build(BuildContext context) {
    final sg = Etat.i.estSG;
    return Charge<Map>(
      key: ValueKey('$_version-$_avecIgnores'),
      charger: () async => await Api.i.get('/verifications?ignores=$_avecIgnores') as Map,
      construire: (context, r, recharger) {
        final c = context.c;
        final categories = (r['categories'] as List).cast<Map>();
        return Defilement(rafraichir: recharger, enfants: [
          Text("Ce qui mérite un coup d'œil, sans rien bloquer.", style: TextStyle(color: c.encre2)),
          if ((r['ignores'] as num) > 0)
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: Text('Afficher les ${r['ignores']} point(s) jugés normaux'),
              value: _avecIgnores,
              onChanged: (v) => setState(() => _avecIgnores = v),
            ),
          if (categories.isEmpty) const Carte(enfant: Vide('Rien à vérifier', texte: 'Aucun doublon probable, aucune matière sans enseignant, aucune fiche incomplète.')),
          for (final cat in categories)
            Carte(
              titre: '${cat['titre']} (${(cat['points'] as List).where((p) => p['ignore'] != true).length})',
              enfant: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('${cat['explication']}', style: TextStyle(color: c.encre2, fontSize: 13)),
                for (final p in (cat['points'] as List).cast<Map>())
                  Opacity(
                    opacity: p['ignore'] == true ? 0.6 : 1,
                    child: Padding(
                      padding: const EdgeInsets.only(top: 12),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text('${p['titre']}', style: const TextStyle(fontWeight: FontWeight.w600)),
                        Text('${p['detail']}', style: TextStyle(color: c.encre2, fontSize: 12.5)),
                        const SizedBox(height: 4),
                        p['ignore'] == true
                            ? const EtatTexte('Jugé normal')
                            : p['gravite'] == 'FORTE'
                                ? const EtatTexte('À traiter', ton: 'alerte')
                                : const EtatTexte('À confirmer'),
                        Wrap(spacing: 8, children: [
                          if (p['action']['type'] == 'ouvrir' || p['action']['type'] == 'fusionner-eleves' || sg)
                            TextButton.icon(
                              icon: Icon(p['action']['type'] == 'ouvrir' ? Icons.open_in_new : Icons.merge_type, size: 18),
                              label: Text(p['action']['type'] == 'ouvrir' ? 'Ouvrir' : 'Fusionner'),
                              onPressed: () => _agir(p['action'] as Map),
                            ),
                          TextButton.icon(
                            icon: Icon(p['ignore'] == true ? Icons.undo : Icons.check, size: 18),
                            label: Text(p['ignore'] == true ? 'Signaler de nouveau' : "C'est normal"),
                            onPressed: () => _marquer(p),
                          ),
                        ]),
                      ]),
                    ),
                  ),
              ]),
            ),
        ]);
      },
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
