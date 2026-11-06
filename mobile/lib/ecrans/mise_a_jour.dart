import 'package:flutter/material.dart';

import '../mise_a_jour.dart';
import '../motif.dart';
import '../theme.dart';
import '../widgets.dart';

/// « Installer maintenant », « Réessayer » : reprend la mise à jour là où elle en est.
Future<void> lancerMiseAJour(BuildContext context) async {
  final m = MiseAJour.i;
  final erreur = m.etape == EtapeMiseAJour.prete ? await m.installer() : await m.telecharger();
  if (erreur != null && context.mounted) message(context, erreur, erreur: true);
}

String _pourcentage(MiseAJour m) => '${((m.progression ?? 0) * 100).round()} %';

/// Bandeau en bas de l'écran : la mise à jour suit son cours toute seule, il en donne l'avancement.
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
        final apk = m.disponible;
        final v = m.publiee;
        final (String titre, String detail, IconData icone, Widget? action) = !apk
            ? ('Correctif installé', 'Fermez puis rouvrez l’application pour l’appliquer.', Icons.restart_alt,
                TextButton(onPressed: m.masquerCorrectif, child: const Text('OK')))
            : switch (m.etape) {
                EtapeMiseAJour.telechargement => ('Version ${v!.nom} en cours de téléchargement', _pourcentage(m), Icons.downloading, null),
                EtapeMiseAJour.prete => (
                    'Version ${v!.nom} prête',
                    'Elle s’installe d’elle-même quand vous quittez l’application.',
                    Icons.system_update_outlined,
                    FilledButton(onPressed: () => lancerMiseAJour(context), child: const Text('Installer'))
                  ),
                EtapeMiseAJour.installation => ('Installation de la version ${v!.nom}…', 'L’application va se fermer puis se rouvrir à jour.', Icons.system_update_outlined, null),
                EtapeMiseAJour.attente => m.erreur != null
                    ? ('Mise à jour ${v!.nom} interrompue', m.erreur!, Icons.cloud_off_outlined,
                        TextButton(onPressed: () => lancerMiseAJour(context), child: const Text('Réessayer')))
                    : ('Nouvelle version ${v!.nom}${v.tailleLisible.isEmpty ? '' : ' (${v.tailleLisible})'}', 'Téléchargement automatique…', Icons.downloading, null),
              };
        return Material(
          color: c.primairePale,
          child: SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 8, 10),
              child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Row(children: [
                  Icon(icone, color: p),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(titre, style: const TextStyle(fontWeight: FontWeight.w700)),
                      Text(detail, style: TextStyle(fontSize: 12.5, color: c.encre2), maxLines: 3, overflow: TextOverflow.ellipsis),
                    ]),
                  ),
                  ?action,
                ]),
                if (apk && m.etape == EtapeMiseAJour.telechargement) ...[
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

/// Version trop ancienne pour le serveur : l'application ne sert plus ; la nouvelle version se
/// télécharge et s'installe tout de suite.
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
                        'Cette version ($nomVersion) ne fonctionne plus avec le serveur. La version ${v.nom}'
                        '${v.tailleLisible.isEmpty ? '' : ' (${v.tailleLisible})'} s’installe : vos données et vos notes en attente sont conservées.',
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
                        Text('Téléchargement… ${_pourcentage(m)}', textAlign: TextAlign.center),
                      ] else if (m.etape == EtapeMiseAJour.installation)
                        const Text('Installation…', textAlign: TextAlign.center)
                      else ...[
                        if (m.erreur != null) ...[
                          Text(m.erreur!, textAlign: TextAlign.center, style: TextStyle(color: c.danger)),
                          const SizedBox(height: 8),
                        ],
                        FilledButton.icon(
                          icon: const Icon(Icons.download),
                          label: Text(m.etape == EtapeMiseAJour.prete ? 'Installer' : 'Mettre à jour'),
                          onPressed: () => lancerMiseAJour(context),
                        ),
                      ],
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
