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

  @override
  Widget build(BuildContext context) {
    final p = {if (_du != null) 'du': _iso(_du!), if (_au != null) 'au': _iso(_au!)};
    return Charge<Map>(
      key: ValueKey('${p['du']}|${p['au']}'),
      charger: () async => await Api.i.get('/absences/enseignants?${Uri(queryParameters: p).query}') as Map,
      construire: (context, d, recharger) {
        final c = context.c;
        final totaux = (d['totaux'] as List).cast<Map>();
        final seances = (d['seances'] as List).cast<Map>();
        final total = totaux.fold<int>(0, (n, t) => n + (t['minutes'] as int));
        return Defilement(rafraichir: recharger, enfants: [
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
          if (totaux.isEmpty)
            const Carte(enfant: Vide('Aucune séance non assurée', texte: "Aucun enseignant n'a été marqué absent sur les feuilles d'appel de cette période."))
          else
            Text('  ${duree(total)} de cours non assurés', style: TextStyle(color: c.encre2)),
          for (final t in totaux)
            Card(
              margin: EdgeInsets.zero,
              clipBehavior: Clip.antiAlias,
              child: ExpansionTile(
                title: Text.rich(TextSpan(children: [
                  TextSpan(text: '${t['nom']} ', style: const TextStyle(fontWeight: FontWeight.w700)),
                  TextSpan(text: '${t['prenom']}', style: TextStyle(color: c.encre2)),
                ])),
                subtitle: Text('${t['seances']} séance(s) non assurée(s)'),
                trailing: Text(duree(t['minutes'] as int), style: TextStyle(color: c.danger, fontWeight: FontWeight.w700)),
                children: [
                  for (final s in seances.where((s) => s['enseignantId'] == t['id']))
                    ListTile(
                      dense: true,
                      title: Text('${_date(s['date'] as String)} · ${s['classe']}'),
                      subtitle: Text('${s['matiere']} · ${s['debut']} – ${s['fin']} (${duree(s['duree'] as int)})${s['motif'] == null ? '' : ' · ${s['motif']}'}'),
                    ),
                ],
              ),
            ),
        ]);
      },
    );
  }
}
