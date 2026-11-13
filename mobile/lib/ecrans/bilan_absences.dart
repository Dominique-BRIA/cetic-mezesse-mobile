import 'package:flutter/material.dart';

import '../api.dart';
import '../theme.dart';
import '../widgets.dart';
import 'emploi_du_temps.dart' show duree;

// Bilan des absences d'une classe pour une période : heures de chaque élève et sanction que portera le
// bulletin (décidée sur les heures non justifiées cumulées depuis la rentrée).

String _h(int m) => m == 0 ? '—' : duree(m);

class EcranBilanAbsences extends StatefulWidget {
  const EcranBilanAbsences({super.key});
  @override
  State<EcranBilanAbsences> createState() => _EcranBilanAbsencesState();
}

class _EcranBilanAbsencesState extends State<EcranBilanAbsences> {
  String? _classe;
  String _periode = 'A';

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
          key: ValueKey('$classeId|$_periode'),
          charger: () async => await Api.i.get('/absences/bilan?classeId=$classeId&periode=$_periode') as Map,
          construire: (context, b, recharger) {
            final c = context.c;
            final eleves = (b['eleves'] as List).cast<Map>();
            final sanctions = (b['sanctions'] as List).cast<Map>();
            return Defilement(rafraichir: recharger, enfants: [
              Card(
                margin: EdgeInsets.zero,
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                    Choix<String>(
                      libelle: 'Classe',
                      valeur: classeId,
                      options: [for (final x in classes) (x['id'] as String, x['nom'] as String)],
                      changer: (v) => setState(() => _classe = v),
                    ),
                    const SizedBox(height: 10),
                    ChoixPeriode(valeur: _periode, changer: (v) => setState(() => _periode = v)),
                    const SizedBox(height: 8),
                    Text(
                      sanctions.isEmpty
                          ? "Aucune sanction n'est réglée : le SG les règle dans Paramètres."
                          : 'Sanctions (non justifiées depuis la rentrée) : ${sanctions.map((s) => '${s['libelle']} dès ${duree(s['minutes'] as int)}').join(' · ')}.',
                      style: TextStyle(color: c.encre2, fontSize: 12.5),
                    ),
                  ]),
                ),
              ),
              if (eleves.isEmpty) const Carte(enfant: Vide('Aucun élève')),
              for (final e in eleves) _carte(context, e),
            ]);
          },
        );
      },
    );
  }

  Widget _carte(BuildContext context, Map e) {
    final c = context.c;
    final nom = e['libelleSanction'] as String? ?? '';
    final jours = e['joursExclusion'] as int;
    final (texte, ton) = switch (e['sanction']) {
      'EXCLUSION' => ('$nom · $jours jour${jours > 1 ? 's' : ''}', 'danger'),
      'BLAME' => (nom, 'danger'),
      _ => (nom, 'alerte'),
    };
    final rien = (e['minutes'] as int) == 0 && (e['cumulNonJustifiees'] as int) == 0;
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(
              child: Text.rich(TextSpan(children: [
                TextSpan(text: '${e['nom']} ', style: const TextStyle(fontWeight: FontWeight.w700)),
                TextSpan(text: '${e['prenoms']}', style: TextStyle(color: c.encre2)),
              ])),
            ),
            if (texte.isNotEmpty) EtatTexte(texte, ton: ton),
          ]),
          if (rien)
            Text('Aucune absence', style: TextStyle(color: c.encre3, fontSize: 12.5))
          else ...[
            const SizedBox(height: 4),
            Wrap(spacing: 14, runSpacing: 2, children: [
              Text('${e['seances']} séance${(e['seances'] as int) > 1 ? 's' : ''} · ${_h(e['minutes'] as int)}', style: const TextStyle(fontSize: 13)),
              Text('justifiées ${_h(e['justifiees'] as int)}', style: TextStyle(color: c.succes, fontSize: 13)),
              Text('non justifiées ${_h(e['nonJustifiees'] as int)}', style: TextStyle(color: c.danger, fontSize: 13, fontWeight: FontWeight.w600)),
            ]),
            Text('Non justifiées depuis la rentrée : ${_h(e['cumulNonJustifiees'] as int)}', style: TextStyle(color: c.encre2, fontSize: 12.5)),
          ],
          if (e['palierExclusion'] == true && e['sanction'] != 'EXCLUSION')
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Row(children: [
                Icon(Icons.notifications_active_outlined, size: 15, color: c.danger),
                const SizedBox(width: 4),
                Expanded(
                  child: Text("Palier d'exclusion atteint${e['proviseurPrevenu'] == true ? ' · Proviseur prévenu' : ''}",
                      style: TextStyle(color: c.danger, fontSize: 12.5)),
                ),
              ]),
            ),
        ]),
      ),
    );
  }
}
