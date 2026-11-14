import 'package:flutter/material.dart';

import '../api.dart';
import '../etat.dart';
import '../theme.dart';
import '../widgets.dart';
import 'emploi_du_temps.dart' show duree;

// Bilan des absences d'une classe pour une période : heures de chaque élève et sanction que portera le
// bulletin (décidée sur les heures non justifiées cumulées depuis la rentrée). Quand un élève atteint les
// heures d'exclusion, le Directeur est prévenu et décide ici : exclusion temporaire, définitive, ou sursis.

String _h(int m) => m == 0 ? '—' : duree(m);
String _jours(int n) => '$n jour${n > 1 ? 's' : ''}';
String _jjmm(String iso) => iso.split('-').reversed.join('/');

/// La décision en une phrase (« exclusion temporaire de 3 jours à partir du 16/11/2026 »).
String _resume(Map d) => switch (d['type']) {
      'TEMPORAIRE' => 'exclusion temporaire de ${_jours(d['jours'] as int)} à partir du ${_jjmm(d['date'] as String)}',
      'DEFINITIVE' => "exclusion définitive de l'établissement à partir du ${_jjmm(d['date'] as String)}",
      _ => 'sursis accordé le ${_jjmm(d['date'] as String)}',
    };

String _iso(DateTime d) => '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

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
              for (final e in eleves) _carte(context, e, recharger),
            ]);
          },
        );
      },
    );
  }

  Widget _carte(BuildContext context, Map e, Future<void> Function() recharger) {
    final c = context.c;
    final rien = (e['minutes'] as int) == 0 && (e['cumulNonJustifiees'] as int) == 0;
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text.rich(TextSpan(children: [
            TextSpan(text: '${e['numero']}. ', style: TextStyle(color: c.encre2, fontWeight: FontWeight.w700)),
            TextSpan(text: '${e['nom']} ', style: const TextStyle(fontWeight: FontWeight.w700)),
            TextSpan(text: '${e['prenoms']}', style: TextStyle(color: c.encre2)),
          ])),
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
          SanctionEleve(e: e, change: recharger),
        ]),
      ),
    );
  }
}

/// Sanction d'un élève, la décision du Directeur (annulable par lui) ou l'alerte « heures d'exclusion atteintes »
/// avec « Décider » : bilan des absences et liste des élèves.
class SanctionEleve extends StatelessWidget {
  const SanctionEleve({super.key, required this.e, required this.change});
  final Map e;
  final Future<void> Function() change;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final directeur = Etat.i.estProviseur;
    final nom = e['libelleSanction'] as String? ?? '';
    final jours = e['joursExclusion'] as int;
    final decision = e['decision'] as Map?;
    final (texte, ton) = switch (e['sanction']) {
      'EXCLUSION' => (nom == 'Exclusion temporaire' ? '$nom · ${_jours(jours)}' : nom, 'danger'),
      'BLAME' => (nom, 'danger'),
      _ => (nom, 'alerte'),
    };
    return Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
      if (texte.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 4), child: EtatTexte(texte, ton: ton)),
      if (decision != null) ...[
        Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Icon(Icons.gavel, size: 15, color: c.encre2),
            const SizedBox(width: 4),
            Expanded(child: Text('Décision de la direction : ${_resume(decision)}', style: TextStyle(color: c.encre2, fontSize: 12.5))),
          ]),
        ),
        if (directeur)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: OutlinedButton(
              style: OutlinedButton.styleFrom(foregroundColor: c.danger, side: BorderSide(color: c.danger), visualDensity: VisualDensity.compact),
              onPressed: () async {
                if (!await confirmer(context, 'Annuler la décision', "${e['nom']} ${e['prenoms']} : ${_resume(decision)}. À n'utiliser qu'en cas d'erreur : l'élève n'est plus exclu.",
                    action: 'Annuler la décision', danger: true)) {
                  return;
                }
                if (!context.mounted) return;
                if (await agir(context, () => Api.i.delete('/absences/exclusions/${decision['id']}'), succes: 'Décision annulée.')) await change();
              },
              child: const Text('Annuler la décision'),
            ),
          ),
      ] else if (e['palierExclusion'] == true) ...[
        Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Row(children: [
            Icon(Icons.notifications_active_outlined, size: 15, color: c.danger),
            const SizedBox(width: 4),
            Expanded(
              child: Text("Heures d'exclusion atteintes${e['proviseurPrevenu'] == true ? ' · Directeur prévenu' : ''}", style: TextStyle(color: c.danger, fontSize: 12.5)),
            ),
          ]),
        ),
        if (directeur)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: FilledButton.icon(
              style: FilledButton.styleFrom(backgroundColor: c.danger, visualDensity: VisualDensity.compact),
              onPressed: () async {
                if (await deciderExclusion(context, e) == true) await change();
              },
              icon: const Icon(Icons.gavel, size: 16),
              label: const Text('Décider'),
            ),
          ),
      ],
    ]);
  }
}

/// Décision du Directeur : exclusion temporaire (nombre de jours ouvrés), définitive (pour toujours), ou sursis.
Future<bool?> deciderExclusion(BuildContext context, Map e) {
  var type = 'TEMPORAIRE';
  final nbJours = TextEditingController(text: '3');
  var date = DateTime.now();
  while (date.weekday >= 6) {
    date = date.add(const Duration(days: 1));
  }
  final motif = TextEditingController();
  const choix = [
    ('TEMPORAIRE', 'Exclusion temporaire', 'Renvoyé pendant le nombre de jours ouvrés indiqué, puis reprend les cours de lui-même.', 'Bulletin : exclusion, nombre de jours'),
    ('DEFINITIVE', 'Exclusion définitive', "Radié de l'établissement pour toujours : il figure parmi les élèves renvoyés et ne peut plus être réinscrit.", 'Bulletin : exclusion définitive'),
    ('SURSIS', 'Sursis (maintien sous condition)', 'Reste en classe ; exclusion suspendue, avertissement solennel aux parents.', 'Bulletin : blâme, avec la mention du sursis'),
  ];
  return showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, maj) => Padding(
        padding: EdgeInsets.fromLTRB(16, 0, 16, MediaQuery.of(ctx).viewInsets.bottom + 16),
        child: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            const Text("Décision d'exclusion", style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
            const SizedBox(height: 4),
            Text("${e['nom']} ${e['prenoms']} : ${duree(e['cumulNonJustifiees'] as int)} d'absences non justifiées depuis la rentrée.",
                style: TextStyle(color: ctx.c.encre2, fontSize: 13)),
            const SizedBox(height: 8),
            RadioGroup<String>(
              groupValue: type,
              onChanged: (v) => maj(() => type = v ?? type),
              child: Column(children: [
                for (final (code, titre, consequence, bulletin) in choix)
                  RadioListTile<String>(
                    value: code,
                    contentPadding: EdgeInsets.zero,
                    title: Text(titre, style: const TextStyle(fontWeight: FontWeight.w600)),
                    subtitle: Text('$consequence\n$bulletin', style: const TextStyle(fontSize: 12.5)),
                    isThreeLine: true,
                  ),
              ]),
            ),
            if (type == 'TEMPORAIRE')
              TextField(
                controller: nbJours,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Nombre de jours ouvrés'),
                onChanged: (_) => maj(() {}),
              ),
            const SizedBox(height: 10),
            OutlinedButton.icon(
              icon: const Icon(Icons.event, size: 18),
              label: Text('${type == 'SURSIS' ? 'Date de la décision' : "Début de l'exclusion"} : ${_jjmm(_iso(date))}'),
              onPressed: () async {
                final d = await showDatePicker(context: ctx, firstDate: DateTime(2020), lastDate: DateTime(2100), initialDate: date);
                if (d != null) maj(() => date = d);
              },
            ),
            const SizedBox(height: 10),
            TextField(controller: motif, maxLength: 500, maxLines: 2, decoration: const InputDecoration(labelText: 'Motif ou observation (facultatif)')),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: type == 'SURSIS' ? null : ctx.c.danger),
              onPressed: type == 'TEMPORAIRE' && (int.tryParse(nbJours.text.trim()) ?? 0) < 1
                  ? null
                  : () async {
                      final ok = await agir(
                        ctx,
                        () => Api.i.post('/absences/exclusions', {
                          'inscriptionId': e['inscriptionId'],
                          'type': type,
                          'jours': type == 'TEMPORAIRE' ? int.parse(nbJours.text.trim()) : null,
                          'date': _iso(date),
                          'motif': motif.text.trim().isEmpty ? null : motif.text.trim(),
                        }),
                        succes: 'Décision enregistrée.',
                      );
                      if (ok && ctx.mounted) Navigator.pop(ctx, true);
                    },
              child: const Text('Enregistrer la décision'),
            ),
          ]),
        ),
      ),
    ),
  );
}
