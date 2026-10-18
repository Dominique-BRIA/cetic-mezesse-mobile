import 'package:flutter/material.dart';

import '../api.dart';
import '../theme.dart';
import '../widgets.dart';

// Journal des décisions du SG (RG-30), réservé au Directeur : désapprobation possible pendant 4 semaines.

const _domaines = {'ORGANISATION': 'Organisation', 'SCOLARITE': 'Scolarité', 'ADMINISTRATION': 'Administration'};
const _statuts = [
  ('', 'Toutes les décisions'),
  ('EN_DELAI', 'Encore désapprouvables'),
  ('APPROUVEE', 'Approuvées'),
  ('DESAPPROUVEE', 'Désapprouvées'),
];

String _dateHeure(String iso) {
  final d = DateTime.parse(iso).toLocal();
  String deux(int n) => n.toString().padLeft(2, '0');
  return '${deux(d.day)}/${deux(d.month)}/${d.year} ${deux(d.hour)}:${deux(d.minute)}';
}

String _delaiRestant(String limite) {
  final jours = (DateTime.parse(limite).difference(DateTime.now()).inHours / 24).ceil();
  return jours <= 1 ? 'dernier jour' : 'encore $jours jours';
}

class EcranDecisions extends StatefulWidget {
  const EcranDecisions({super.key});
  @override
  State<EcranDecisions> createState() => _EcranDecisionsState();
}

class _EcranDecisionsState extends State<EcranDecisions> {
  String _domaine = '';
  String _statut = '';
  final List<Map<String, dynamic>> _lignes = [];
  Map<String, dynamic>? _page;
  Object? _erreur;
  bool _charge = false;

  @override
  void initState() {
    super.initState();
    _recharger();
  }

  Future<void> _recharger() => _charger(depuisDebut: true);

  Future<void> _charger({bool depuisDebut = false}) async {
    setState(() {
      _charge = true;
      _erreur = null;
    });
    try {
      final p = <String, String>{
        if (_domaine.isNotEmpty) 'domaine': _domaine,
        if (_statut.isNotEmpty) 'statut': _statut,
        if (!depuisDebut && _page?['suivant'] != null) 'apres': _page!['suivant'] as String,
      };
      final r = await Api.i.get('/decisions${p.isEmpty ? '' : '?${Uri(queryParameters: p).query}'}', annee: false) as Map<String, dynamic>;
      setState(() {
        if (depuisDebut) _lignes.clear();
        _lignes.addAll((r['decisions'] as List).cast<Map<String, dynamic>>());
        _page = r;
      });
    } catch (e) {
      setState(() => _erreur = e);
    } finally {
      if (mounted) setState(() => _charge = false);
    }
  }

  // Désapprouver défait l'action du SG ; c'est définitif.
  Future<void> _arbitrer(Map<String, dynamic> d) async {
    final motif = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Désapprouver la décision'),
        content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text(d['libelle'] as String),
          const SizedBox(height: 12),
          Text(d['effetPrevu'] as String? ?? "La décision sera marquée désapprouvée, sans que l'action soit défaite automatiquement.",
              style: const TextStyle(fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          TextField(controller: motif, maxLines: 3, maxLength: 500, autofocus: true, decoration: const InputDecoration(labelText: 'Motif (obligatoire)')),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Annuler')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: ctx.c.danger),
            onPressed: () async {
              if (motif.text.trim().isEmpty) return;
              Map? r;
              final fait = await agir(
                ctx,
                () async => r = await Api.i.envoyer('POST', '/decisions/${d['id']}/desapprouver', corps: {'motif': motif.text.trim()}, annee: false) as Map,
              );
              if (fait && ctx.mounted) {
                message(ctx, r?['annulee'] == true ? 'Décision désapprouvée. ${r?['effet']}' : 'Décision désapprouvée.');
                Navigator.pop(ctx, true);
              }
            },
            child: const Text('Désapprouver'),
          ),
        ],
      ),
    );
    if (ok == true) _recharger();
  }

  @override
  Widget build(BuildContext context) {
    final totaux = _page?['totaux'] as Map?;
    return Defilement(
      rafraichir: _recharger,
      enfants: [
        Text(
          "Décisions du Surveillant Général, approuvées d'office. Vous pouvez en désapprouver une pendant 4 semaines ; "
          'passé ce délai, elle reste approuvée.',
          style: TextStyle(color: context.c.encre2),
        ),
        const SizedBox(height: 10),
        GrilleIndicateurs(enfants: [
          Indicateur(libelle: 'Encore désapprouvables', valeur: '${totaux?['enDelai'] ?? '…'}', accent: true),
          Indicateur(libelle: 'Désapprouvées', valeur: '${totaux?['desapprouvees'] ?? '…'}'),
        ]),
        const SizedBox(height: 10),
        Choix<String>(
          libelle: 'Domaine',
          valeur: _domaine,
          options: [('', 'Tous les domaines'), for (final e in _domaines.entries) (e.key, e.value)],
          changer: (v) {
            _domaine = v ?? '';
            _recharger();
          },
        ),
        const SizedBox(height: 10),
        Choix<String>(
          libelle: 'Statut',
          valeur: _statut,
          options: _statuts,
          changer: (v) {
            _statut = v ?? '';
            _recharger();
          },
        ),
        const SizedBox(height: 10),
        if (_erreur != null) MessageErreur(_erreur!, reessayer: _recharger),
        if (_lignes.isEmpty && _charge) const Chargement(),
        if (_lignes.isEmpty && !_charge && _erreur == null) const Carte(enfant: Vide('Aucune décision')),
        for (final d in _lignes) _carte(d),
        if (_page?['suivant'] != null)
          Center(
            child: OutlinedButton(
              onPressed: _charge ? null : () => _charger(),
              child: const Text('Afficher les décisions plus anciennes'),
            ),
          ),
      ],
    );
  }

  Widget _carte(Map<String, dynamic> d) {
    final c = context.c;
    final approuvee = d['statut'] == 'APPROUVEE';
    final auteur = d['auteur'] as Map;
    return Carte(
      enfant: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text(
          '${_domaines[d['domaine']]?.toUpperCase()} · ${_dateHeure(d['creeLe'] as String)} · ${auteur['prenom']} ${auteur['nom']}',
          style: TextStyle(fontSize: 11, color: c.encre3, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 4),
        Text(d['libelle'] as String),
        const SizedBox(height: 8),
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              EtatTexte(approuvee ? 'Approuvée' : 'Désapprouvée', ton: approuvee ? 'succes' : 'danger'),
              if (!approuvee && d['motifDesapprobation'] != null)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(d['motifDesapprobation'] as String, style: TextStyle(fontSize: 12, color: c.encre2)),
                ),
              if (!approuvee)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(d['annulee'] == true ? 'Action annulée : ${d['effet']}' : 'Action non annulée automatiquement.',
                      style: TextStyle(fontSize: 11, color: c.encre3)),
                ),
            ]),
          ),
          if (!approuvee)
            const SizedBox()
          else if (d['modifiable'] == true)
            Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
              OutlinedButton(onPressed: () => _arbitrer(d), child: const Text('Désapprouver')),
              Text(_delaiRestant(d['limite'] as String), style: TextStyle(fontSize: 11, color: c.encre3)),
            ])
          else
            Text('Délai écoulé', style: TextStyle(fontSize: 11, color: c.encre3)),
        ]),
      ]),
    );
  }
}
