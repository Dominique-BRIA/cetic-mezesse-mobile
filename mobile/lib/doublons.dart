import 'dart:math';

import 'package:flutter/material.dart';

import 'api.dart';
import 'theme.dart';

// Doublons probables et opérations répétées : l'API prévient (409 « DOUBLON » ou « REPETITION ») au
// lieu de refuser. L'utilisateur voit les fiches semblables et choisit d'enregistrer quand même ou de
// renoncer.

/// L'utilisateur a renoncé à enregistrer après un avertissement : rien à afficher.
class Abandon implements Exception {
  @override
  String toString() => 'Enregistrement abandonné.';
}

final _hasard = Random();

/// Identifiant d'un formulaire : le même tant qu'il n'a pas abouti. Un second envoi (double appui, réseau
/// lent qui fait recommencer) est reconnu par l'API et n'enregistre rien de plus.
String nouvelleCleEnvoi() => '${DateTime.now().microsecondsSinceEpoch}-${_hasard.nextInt(1 << 30)}';

/// Envoie en demandant à l'API de signaler les doublons ; si elle en signale, demande confirmation et
/// renvoie avec « confirme ». Renoncer lève [Abandon].
Future<T> envoyerVerifie<T>(BuildContext context, Future<T> Function(Map<String, String> entetes) appel, {String? cle}) async {
  final k = cle ?? nouvelleCleEnvoi();
  try {
    return await appel({'X-Doublons': 'verifier', 'X-Envoi': k});
  } on ErreurApi catch (e) {
    final d = e.details;
    if (e.statut != 409 || d is! Map || (d['code'] != 'DOUBLON' && d['code'] != 'REPETITION')) rethrow;
    if (!context.mounted) throw Abandon();
    final oui = await showDialog<bool>(context: context, builder: (_) => _Question(d, e.message)) ?? false;
    if (!oui) throw Abandon();
    return appel({'X-Doublons': 'confirme', 'X-Envoi': k});
  }
}

const _conseils = {
  'enseignant': "S'il s'agit de la même personne, ouvrez son compte plutôt que d'en créer un second.",
  'eleve': "S'il s'agit du même élève, ouvrez sa fiche plutôt que d'en créer une seconde.",
  'matiere': "S'il s'agit de la même matière, modifiez celle qui existe.",
  'classe': 'Une classe de plus au même niveau et dans la même spécialité renommera les classes en A, B…',
  'ligne': 'Deux lignes de cet envoi se ressemblent.',
};

String? _depuis(Object? iso) {
  if (iso is! String) return null;
  final minutes = DateTime.now().difference(DateTime.parse(iso)).inMinutes;
  if (minutes < 1) return "créé à l'instant";
  if (minutes < 60) return 'créé il y a $minutes min';
  return null;
}

class _Question extends StatelessWidget {
  const _Question(this.d, this.message);
  final Map d;
  final String message;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final repetition = d['code'] == 'REPETITION';
    final candidats = ((d['candidats'] as List?) ?? const []).cast<Map>();
    final conseils = {for (final x in candidats) _conseils[x['type']]}.whereType<String>();
    return AlertDialog(
      title: Text((d['titre'] as String?) ?? 'Vérification'),
      content: SizedBox(
        width: double.maxFinite,
        child: repetition
            ? Text(message)
            : ListView(shrinkWrap: true, children: [
                for (final t in conseils) Padding(padding: const EdgeInsets.only(bottom: 8), child: Text(t, style: TextStyle(color: c.encre2))),
                for (final x in candidats)
                  Container(
                    margin: const EdgeInsets.only(bottom: 8),
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(border: Border.all(color: c.bord), borderRadius: BorderRadius.circular(6)),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      if (x['ligne'] != null) Text('Ligne ${x['ligne']}', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: c.encre2)),
                      Text('${x['libelle']}', style: const TextStyle(fontWeight: FontWeight.w600)),
                      Text(x['force'] == 'FORTE' ? 'Très probablement la même' : 'Nom proche',
                          style: TextStyle(fontSize: 12, color: x['force'] == 'FORTE' ? c.alerte : c.encre3)),
                      if (x['detail'] != null || _depuis(x['creeLe']) != null)
                        Text([x['detail'], _depuis(x['creeLe'])].whereType<String>().join(' · '), style: TextStyle(fontSize: 12.5, color: c.encre2)),
                    ]),
                  ),
              ]),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Annuler')),
        FilledButton(onPressed: () => Navigator.pop(context, true), child: Text(repetition ? 'Recommencer' : 'Enregistrer quand même')),
      ],
    );
  }
}
