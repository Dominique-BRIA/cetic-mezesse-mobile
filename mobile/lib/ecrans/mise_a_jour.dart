import 'package:flutter/material.dart';

import '../file_attente.dart';
import '../mise_a_jour.dart';
import '../motif.dart';
import '../theme.dart';
import '../widgets.dart';

/// Lance la mise à jour : envoie d'abord les notes en attente si le réseau le permet. Celles qui
/// restent sont gardées, une mise à jour ne vide pas le téléphone.
Future<void> lancerMiseAJour(BuildContext context) async {
  if (FileAttente.i.envois.isNotEmpty) await FileAttente.i.synchroniser();
  final erreur = await MiseAJour.i.installer();
  if (erreur != null && context.mounted) message(context, erreur, erreur: true);
}

/// Bandeau en bas de l'écran : nouvelle version à installer, ou correctif prêt au prochain lancement.
class BandeauMiseAJour extends StatelessWidget {
  const BandeauMiseAJour({super.key});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: MiseAJour.i,
      builder: (context, _) {
        final m = MiseAJour.i;
        if (!m.bandeauVisible) return const SizedBox.shrink();
        final c = context.c;
        final p = Theme.of(context).colorScheme.primary;
        final apk = m.disponible && !m.reportee;
        final v = m.publiee;
        return Material(
          color: c.primairePale,
          child: SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 8, 10),
              child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Row(children: [
                  Icon(apk ? Icons.system_update_outlined : Icons.restart_alt, color: p),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(
                        apk ? 'Nouvelle version ${v!.nom}${v.tailleLisible.isEmpty ? '' : ' (${v.tailleLisible})'}' : 'Correctif installé',
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                      Text(
                        apk
                            ? (m.etape == EtapeMiseAJour.telechargement
                                ? 'Téléchargement… ${((m.progression ?? 0) * 100).round()} %'
                                : m.etape == EtapeMiseAJour.installation
                                    ? 'Ouverture de l’installation…'
                                    : (v!.notes.isEmpty ? 'Elle garde vos données et vos notes en attente.' : v.notes))
                            : 'Fermez puis rouvrez l’application pour l’appliquer.',
                        style: TextStyle(fontSize: 12.5, color: c.encre2),
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ]),
                  ),
                  if (m.etape == EtapeMiseAJour.attente) ...[
                    TextButton(onPressed: m.reporter, child: Text(apk ? 'Plus tard' : 'OK')),
                    if (apk) FilledButton(onPressed: () => lancerMiseAJour(context), child: const Text('Mettre à jour')),
                  ],
                ]),
                if (m.etape == EtapeMiseAJour.telechargement) ...[
                  const SizedBox(height: 8),
                  LinearProgressIndicator(value: m.progression),
                ],
              ]),
            ),
          ),
        );
      },
    );
  }
}

/// Version trop ancienne pour le serveur : l'application ne sert plus tant qu'elle n'est pas à jour.
class EcranMiseAJourObligatoire extends StatelessWidget {
  const EcranMiseAJourObligatoire({super.key});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: MiseAJour.i,
      builder: (context, _) {
        final m = MiseAJour.i;
        final v = m.publiee!;
        final c = context.c;
        return MotifFond(
          child: Scaffold(
            body: SafeArea(
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 420),
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                      Icon(Icons.system_update_outlined, size: 48, color: Theme.of(context).colorScheme.primary),
                      const SizedBox(height: 16),
                      const Text('Mise à jour nécessaire', textAlign: TextAlign.center, style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
                      const SizedBox(height: 8),
                      Text(
                        'Cette version ($nomVersion) ne fonctionne plus avec le serveur. Installez la version ${v.nom}'
                        '${v.tailleLisible.isEmpty ? '' : ' (${v.tailleLisible})'} : vos données et vos notes en attente sont conservées.',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: c.encre2),
                      ),
                      if (v.notes.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        Text(v.notes, textAlign: TextAlign.center, style: TextStyle(fontSize: 13, color: c.encre3)),
                      ],
                      const SizedBox(height: 24),
                      if (m.etape == EtapeMiseAJour.telechargement) ...[
                        LinearProgressIndicator(value: m.progression),
                        const SizedBox(height: 8),
                        Text('Téléchargement… ${((m.progression ?? 0) * 100).round()} %', textAlign: TextAlign.center),
                      ] else
                        FilledButton.icon(
                          icon: const Icon(Icons.download),
                          label: Text(m.etape == EtapeMiseAJour.installation ? 'Ouverture de l’installation…' : 'Mettre à jour'),
                          onPressed: m.etape == EtapeMiseAJour.attente ? () => lancerMiseAJour(context) : null,
                        ),
                    ]),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
