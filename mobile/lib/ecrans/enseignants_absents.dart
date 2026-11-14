import 'package:flutter/material.dart';

import '../api.dart';
import '../theme.dart';
import '../widgets.dart';
import 'emploi_du_temps.dart' show duree;

// Séances non assurées (enseignant absent, marqué sur la feuille d'appel) : totaux par enseignant et détail.
// Une séance confiée à un remplaçant ou annulée n'y figure pas.

String _iso(DateTime d) => '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

String _date(String iso) {
  const jours = ['', 'lun.', 'mar.', 'mer.', 'jeu.', 'ven.', 'sam.', 'dim.'];
  final d = DateTime.parse(iso);
  return '${jours[d.weekday]} ${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';
}

class EcranEnseignantsAbsents extends StatefulWidget {
  const EcranEnseignantsAbsents({super.key});
  @override
  State<EcranEnseignantsAbsents> createState() => _EcranEnseignantsAbsentsState();
}

class _EcranEnseignantsAbsentsState extends State<EcranEnseignantsAbsents> {
  DateTime? _du;
  DateTime? _au;
  String? _enseignant; // filtre : un enseignant, ou tous
  List<Map>? _enseignants;

  @override
  void initState() {
    super.initState();
    // Tous les enseignants, pour le filtre (pas seulement ceux qui ont des séances non assurées).
    Api.i.get('/utilisateurs?role=PROFESSEUR').then((l) {
      final liste = (l as List).cast<Map>()..sort((x, y) => '${x['nom']} ${x['prenom']}'.compareTo('${y['nom']} ${y['prenom']}'));
      if (mounted) setState(() => _enseignants = liste);
    }, onError: (_) {});
  }

  @override
  Widget build(BuildContext context) {
    final p = {if (_du != null) 'du': _iso(_du!), if (_au != null) 'au': _iso(_au!), 'enseignantId': ?_enseignant};
    return Charge<Map>(
      key: ValueKey('${p['du']}|${p['au']}|$_enseignant'),
      charger: () async => await Api.i.get('/absences/enseignants?${Uri(queryParameters: p).query}') as Map,
      construire: (context, d, recharger) {
        final c = context.c;
        // Avec un enseignant choisi, seulement son total.
        final totaux = (d['totaux'] as List).cast<Map>().where((t) => _enseignant == null || t['id'] == _enseignant).toList();
        final seances = (d['seances'] as List).cast<Map>();
        final total = totaux.fold<int>(0, (n, t) => n + (t['minutes'] as int));
        return Defilement(rafraichir: recharger, enfants: [
          Card(
            margin: EdgeInsets.zero,
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Row(children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () async {
                        final x = await showDatePicker(context: context, firstDate: DateTime(2020), lastDate: _au ?? DateTime.now(), initialDate: _du ?? _au ?? DateTime.now());
                        setState(() => _du = x);
                      },
                      child: Text(_du == null ? 'Du…' : 'Du ${_date(_iso(_du!))}'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () async {
                        final x = await showDatePicker(context: context, firstDate: _du ?? DateTime(2020), lastDate: DateTime.now(), initialDate: _au ?? DateTime.now());
                        setState(() => _au = x);
                      },
                      child: Text(_au == null ? 'Au…' : 'Au ${_date(_iso(_au!))}'),
                    ),
                  ),
                ]),
                const SizedBox(height: 10),
                Choix<String>(
                  libelle: 'Enseignant',
                  valeur: _enseignant ?? '',
                  options: [('', 'Tous les enseignants'), for (final e in _enseignants ?? const <Map>[]) (e['id'] as String, '${e['nom']} ${e['prenom']}')],
                  changer: (v) => setState(() => _enseignant = v == null || v.isEmpty ? null : v),
                ),
              ]),
            ),
          ),
          if (totaux.isEmpty)
            Carte(
              enfant: Vide('Aucune séance non assurée',
                  texte: _enseignant == null
                      ? "Aucun enseignant n'a été marqué absent sur les feuilles d'appel de cette période."
                      : "Cet enseignant n'a été marqué absent sur aucune feuille d'appel de cette période."),
            )
          else ...[
            Carte(
              titre: 'Par enseignant · ${duree(total)} au total',
              sansMarge: true,
              enfant: Column(children: [
                for (final t in totaux)
                  ListTile(
                    dense: true,
                    title: Text.rich(TextSpan(children: [
                      TextSpan(text: '${t['nom']} ', style: const TextStyle(fontWeight: FontWeight.w700)),
                      TextSpan(text: '${t['prenom']}', style: TextStyle(color: c.encre2)),
                    ])),
                    subtitle: Text('${t['seances']} séance${(t['seances'] as int) > 1 ? 's' : ''} non assurée${(t['seances'] as int) > 1 ? 's' : ''}'),
                    trailing: Text(duree(t['minutes'] as int), style: TextStyle(color: c.danger, fontWeight: FontWeight.w700)),
                  ),
              ]),
            ),
            Carte(
              titre: 'Séances non assurées',
              sansMarge: true,
              enfant: Column(children: [
                for (final s in seances)
                  ListTile(
                    dense: true,
                    title: Text('${_date(s['date'] as String)} · ${s['classe']}'),
                    subtitle: Text([
                      '${s['matiere']} · ${s['debut']} – ${s['fin']} (${duree(s['duree'] as int)})',
                      if (_enseignant == null && s['enseignant'] != null) '${s['enseignant']}',
                      if (s['motif'] != null) '${s['motif']}',
                    ].join(' · ')),
                  ),
              ]),
            ),
          ],
        ]);
      },
    );
  }
}
