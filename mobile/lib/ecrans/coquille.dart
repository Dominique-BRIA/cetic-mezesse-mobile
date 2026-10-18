import 'package:flutter/material.dart';

import '../api.dart';
import '../etat.dart';
import '../file_attente.dart';
import '../format.dart';
import '../motif.dart';
import '../theme.dart';
import '../widgets.dart';
import 'accueil.dart';
import 'admin.dart';
import 'attestations.dart';
import 'cartes.dart';
import 'connexion.dart';
import 'decisions.dart';
import 'notifications.dart';
import 'eleves.dart';
import 'evaluations.dart';
import 'organisation.dart';
import 'prof.dart';
import 'profil.dart';

class Destination {
  const Destination(this.cle, this.libelle, this.icone, this.roles, this.ecran, {this.section});
  final String cle;
  final String libelle;
  final IconData icone;
  final List<String> roles;
  final Widget Function() ecran;
  final String? section;
}

const _p = 'PROVISEUR';
const _sg = 'SURVEILLANT_GENERAL';
const _pr = 'PROFESSEUR';

final destinations = <Destination>[
  Destination('accueil', 'Tableau de bord', Icons.space_dashboard_outlined, [_p, _sg, _pr], () => const EcranAccueil()),
  Destination('saisie', 'Saisie des notes', Icons.edit_note, [_pr], () => const EcranSaisie(), section: 'Mes cours'),
  Destination('manquantes', 'Élèves sans note', Icons.checklist, [_pr], () => const EcranManquantes(), section: 'Mes cours'),
  Destination('stats-prof', 'Statistiques', Icons.bar_chart, [_pr], () => const EcranStatsMesMatieres(), section: 'Mes cours'),
  Destination('eleves', 'Élèves', Icons.people_outline, [_p, _sg], () => const EcranEleves(), section: 'Scolarité'),
  Destination('cartes', 'Cartes scolaires', Icons.credit_card, [_p, _sg], () => const EcranCartes(), section: 'Scolarité'),
  Destination('renvoyes', 'Élèves renvoyés', Icons.person_remove_outlined, [_p, _sg], () => const EcranRenvoyes(), section: 'Scolarité'),
  Destination('reinscription', 'Réinscriptions', Icons.person_add_alt, [_sg], () => const EcranReinscription(), section: 'Scolarité'),
  Destination('classes', 'Classes', Icons.school_outlined, [_p, _sg], () => const EcranClasses(), section: 'Organisation'),
  Destination('groupes', 'Groupes de matières', Icons.layers_outlined, [_p, _sg], () => const EcranGroupes(), section: 'Organisation'),
  Destination('matieres', 'Matières', Icons.menu_book_outlined, [_p, _sg], () => const EcranMatieres(), section: 'Organisation'),
  Destination('enseignants', 'Enseignants', Icons.badge_outlined, [_p, _sg], () => const EcranEnseignants(), section: 'Organisation'),
  Destination('notes', 'Notes', Icons.grid_on, [_p, _sg], () => const EcranNotes(), section: 'Évaluations'),
  Destination('bulletins', 'Bulletins', Icons.description_outlined, [_p, _sg], () => const EcranBulletins(), section: 'Évaluations'),
  Destination('statistiques', 'Statistiques', Icons.bar_chart, [_p, _sg], () => const EcranStatistiques(), section: 'Évaluations'),
  Destination('classement', 'Classement général', Icons.emoji_events_outlined, [_p, _sg], () => const EcranClassement(), section: 'Évaluations'),
  Destination('tableau-honneur', "Tableau d'honneur", Icons.military_tech_outlined, [_p, _sg], () => const EcranTableauHonneur(), section: 'Évaluations'),
  Destination('decisions', 'Décisions prises', Icons.gavel, [_p], () => const EcranDecisions(), section: 'Administration'),
  Destination('attestations', 'Attestations de présence', Icons.approval_outlined, [_p], () => const EcranAttestations(), section: 'Administration'),
  Destination('annees', 'Années et séquences', Icons.date_range_outlined, [_p, _sg], () => const EcranAnnees(), section: 'Administration'),
  Destination('parametres', 'Paramètres', Icons.settings_outlined, [_p, _sg], () => const EcranParametres(), section: 'Administration'),
];

/// Permet aux écrans d'en ouvrir un autre (par exemple le tableau de bord vers la saisie).
final ValueNotifier<String> destinationCourante = ValueNotifier('accueil');

/// Incrémenté par le bouton « Actualiser » : l'écran affiché est reconstruit et recharge ses données.
final ValueNotifier<int> versionEcran = ValueNotifier(0);

class Coquille extends StatelessWidget {
  const Coquille({super.key});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([destinationCourante, versionEcran]),
      builder: (context, _) {
        final cle = destinationCourante.value;
        final e = Etat.i;
        final visibles = destinations.where((d) => d.roles.contains(e.role)).toList();
        final d = visibles.firstWhere((x) => x.cle == cle, orElse: () => visibles.first);
        return MotifFond(
          child: Scaffold(
            appBar: AppBar(
              title: Text(d.libelle),
              actions: [
                IconButton(
                  tooltip: 'Actualiser',
                  icon: const Icon(Icons.refresh),
                  onPressed: () => versionEcran.value++,
                ),
                ClocheNotifications(
                  ouvrir: (cle) {
                    if (visibles.any((x) => x.cle == cle)) destinationCourante.value = cle;
                  },
                ),
                ListenableBuilder(
                  listenable: FileAttente.i,
                  builder: (_, __) => FileAttente.i.envois.isEmpty
                      ? const SizedBox()
                      : TextButton.icon(
                          onPressed: () => _ouvrirFile(context),
                          icon: const Icon(Icons.cloud_upload_outlined, size: 20),
                          label: Text('${FileAttente.i.nombreNotes}'),
                        ),
                ),
              ],
              bottom: Api.i.horsLigne.value
                  ? PreferredSize(
                      preferredSize: const Size.fromHeight(28),
                      child: Container(
                        height: 28,
                        width: double.infinity,
                        alignment: Alignment.center,
                        color: context.c.alerte.withValues(alpha: 0.15),
                        child: Text('Hors connexion : données de la dernière synchronisation',
                            style: TextStyle(fontSize: 12, color: context.c.alerte, fontWeight: FontWeight.w600)),
                      ),
                    )
                  : null,
            ),
            drawer: _Tiroir(visibles: visibles, courante: d.cle),
            body: KeyedSubtree(key: ValueKey('${d.cle}-${Api.i.anneeId}-${versionEcran.value}'), child: d.ecran()),
          ),
        );
      },
    );
  }

  void _ouvrirFile(BuildContext context) {
    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      builder: (ctx) => ListenableBuilder(
        listenable: FileAttente.i,
        builder: (ctx, _) {
          final f = FileAttente.i;
          return SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                const Text('Notes en attente d\'envoi', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
                const SizedBox(height: 4),
                Text('Elles ont été enregistrées sur le téléphone sans réseau et partiront dès que le serveur répondra.',
                    style: TextStyle(color: ctx.c.encre2)),
                const SizedBox(height: 12),
                for (final e in f.envois)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(e.libelle),
                    subtitle: e.erreur == null
                        ? Text('${e.notes.length} note(s)')
                        : Text(e.erreur!, style: TextStyle(color: ctx.c.danger)),
                    trailing: e.erreur == null
                        ? null
                        : IconButton(
                            icon: const Icon(Icons.delete_outline),
                            tooltip: 'Abandonner ces notes',
                            onPressed: () async {
                              if (await confirmer(ctx, 'Abandonner ces notes ?', 'Elles ne seront jamais envoyées.', danger: true)) {
                                f.retirer(e);
                              }
                            },
                          ),
                  ),
                const SizedBox(height: 8),
                FilledButton.icon(
                  icon: const Icon(Icons.sync),
                  label: const Text('Envoyer maintenant'),
                  onPressed: () async {
                    final n = await f.synchroniser();
                    if (ctx.mounted) message(ctx, n > 0 ? '$n feuille(s) envoyée(s).' : 'Rien n\'a pu être envoyé pour le moment.');
                  },
                ),
              ]),
            ),
          );
        },
      ),
    );
  }
}

class _Tiroir extends StatelessWidget {
  const _Tiroir({required this.visibles, required this.courante});
  final List<Destination> visibles;
  final String courante;

  @override
  Widget build(BuildContext context) {
    final e = Etat.i;
    final c = context.c;
    final p = Theme.of(context).colorScheme.primary;
    String? section;
    final elements = <Widget>[];
    for (final d in visibles) {
      if (d.section != section && d.section != null) {
        section = d.section;
        elements.add(Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 16, 4),
          child: Text(section!.toUpperCase(), style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 0.9, color: c.encre3)),
        ));
      }
      final active = d.cle == courante;
      elements.add(Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: ListTile(
          dense: true,
          selected: active,
          selectedTileColor: c.primairePale,
          selectedColor: p,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
          leading: Icon(d.icone, size: 20),
          title: Text(d.libelle, style: TextStyle(fontSize: 14.5, fontWeight: active ? FontWeight.w600 : FontWeight.w400)),
          onTap: () {
            Navigator.pop(context);
            destinationCourante.value = d.cle;
          },
        ),
      ));
    }
    return Drawer(
      child: SafeArea(
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          const Padding(padding: EdgeInsets.fromLTRB(16, 16, 16, 12), child: Marque()),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Choix<String>(
              libelle: 'Année scolaire',
              valeur: e.annee?['id'] as String?,
              options: [for (final a in e.annees) (a['id'] as String, '${a['libelle']}${a['active'] == true ? ' (en cours)' : ''}')],
              changer: (v) {
                if (v == null) return;
                Navigator.pop(context);
                e.choisirAnnee(v);
              },
            ),
          ),
          const SizedBox(height: 8),
          Expanded(child: ListView(padding: EdgeInsets.zero, children: elements)),
          const Divider(),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 8, 4),
            child: Row(children: [
              Expanded(
                child: InkWell(
                  borderRadius: BorderRadius.circular(6),
                  onTap: () {
                    Navigator.pop(context);
                    Navigator.push(context, MaterialPageRoute(builder: (_) => const EcranProfil()));
                  },
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text('${e.utilisateur?['prenom']} ${e.utilisateur?['nom']}', style: const TextStyle(fontWeight: FontWeight.w600)),
                      Text('${libelleRole(e.utilisateur)} · Mon profil', style: TextStyle(fontSize: 12, color: c.encre2)),
                    ]),
                  ),
                ),
              ),
              IconButton(
                tooltip: 'Changer de thème',
                icon: Icon(Theme.of(context).brightness == Brightness.dark ? Icons.light_mode_outlined : Icons.dark_mode_outlined),
                onPressed: () => e.basculerTheme(Theme.of(context).brightness),
              ),
              IconButton(
                tooltip: 'Changer mon mot de passe',
                icon: const Icon(Icons.key_outlined),
                onPressed: () {
                  Navigator.pop(context);
                  Navigator.push(context, MaterialPageRoute(builder: (_) => const EcranMotDePasse()));
                },
              ),
            ]),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
            child: TextButton.icon(
              style: TextButton.styleFrom(alignment: Alignment.centerLeft, foregroundColor: c.encre2),
              icon: const Icon(Icons.logout, size: 20),
              label: const Text('Déconnexion'),
              onPressed: () async {
                if (FileAttente.i.envois.isNotEmpty &&
                    !await confirmer(context, 'Des notes ne sont pas encore envoyées',
                        'Elles resteront sur le téléphone et partiront à la prochaine connexion. Se déconnecter quand même ?')) {
                  return;
                }
                destinationCourante.value = 'accueil';
                await e.deconnecter();
              },
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 16, 10),
            child: Text('Version $versionApp', style: TextStyle(fontSize: 11, color: c.encre3)),
          ),
        ]),
      ),
    );
  }
}
