import 'package:flutter/material.dart';

import '../api.dart';
import '../doublons.dart';
import '../etat.dart';
import '../theme.dart';
import '../widgets.dart';
import 'organisation.dart';

// Emploi du temps d'une classe : la semaine type, jour par jour. Le SG le tient, le Proviseur le consulte.
// Une nouvelle version, à partir d'une date, remplace la précédente pour les jours suivants.

const _jours = ['', 'Lundi', 'Mardi', 'Mercredi', 'Jeudi', 'Vendredi', 'Samedi'];

/// Durée en minutes : « 55 min », « 1 h », « 3 h 25 ».
String duree(int minutes) {
  final h = minutes ~/ 60;
  final m = minutes % 60;
  if (h == 0) return '$m min';
  return m == 0 ? '$h h' : '$h h ${m.toString().padLeft(2, '0')}';
}

String _date(String iso) {
  final d = DateTime.parse(iso);
  return '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';
}

String _libelleVersion(Map v) =>
    '${v['valableDu'] == null ? 'Depuis la rentrée' : 'À partir du ${_date(v['valableDu'] as String)}'}'
    '${v['valableAu'] == null ? '' : " jusqu'au ${_date(v['valableAu'] as String)}"}'
    '${v['enVigueur'] == true ? ' · en vigueur' : ''}';

int _minutes(String h) {
  final p = h.split(':');
  return int.parse(p[0]) * 60 + int.parse(p[1]);
}

String _heure(TimeOfDay t) => '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

class EcranEmploiDuTemps extends StatefulWidget {
  const EcranEmploiDuTemps({super.key});
  @override
  State<EcranEmploiDuTemps> createState() => _EcranEmploiDuTempsState();
}

class _EcranEmploiDuTempsState extends State<EcranEmploiDuTemps> {
  String? _classe;
  String? _versionId;
  int _rechargement = 0;

  void _afficher(Map vue) => setState(() {
        _versionId = (vue['version'] as Map?)?['id'] as String?;
        _rechargement++;
      });

  Future<void> _formulaireCreneau(String classeId, Map vue, {Map? creneau, int jour = 1}) async {
    final cle = nouvelleCleEnvoi();
    final matieres = (await Api.i.get('/matieres?classeId=$classeId') as List).cast<Map>();
    if (!mounted) return;
    final duJour = (vue['creneaux'] as List).cast<Map>().where((c) => c['jour'] == jour).toList()
      ..sort((x, y) => _minutes(y['fin'] as String) - _minutes(x['fin'] as String));
    var j = creneau?['jour'] as int? ?? jour;
    var matiereId = creneau?['matiere']['id'] as String? ?? '';
    var debut = creneau?['debut'] as String? ?? (duJour.isEmpty ? '07:30' : duJour.first['fin'] as String);
    String? fin = creneau?['fin'] as String?;
    Map? resultat;
    final ok = await feuilleFormulaire(
      context,
      creneau == null ? 'Nouveau créneau, ${_jours[jour].toLowerCase()}' : 'Modifier le créneau',
      (ctx, maj) {
        Future<void> choisirHeure(bool estDebut) async {
          final actuelle = estDebut ? debut : (fin ?? debut);
          final t = await showTimePicker(
            context: ctx,
            initialTime: TimeOfDay(hour: _minutes(actuelle) ~/ 60, minute: _minutes(actuelle) % 60),
            builder: (c, enfant) => MediaQuery(data: MediaQuery.of(c).copyWith(alwaysUse24HourFormat: true), child: enfant!),
          );
          if (t != null) maj(() => estDebut ? debut = _heure(t) : fin = _heure(t));
        }

        final ecart = fin == null ? 0 : _minutes(fin!) - _minutes(debut);
        return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Choix<String>(
              libelle: 'Matière',
              valeur: matiereId,
              options: [
                for (final m in matieres)
                  (m['id'] as String, '${m['nom']}${m['professeur'] == null ? '' : ' · ${m['professeur']['prenom']} ${m['professeur']['nom']}'}'),
              ],
              changer: (v) => maj(() => matiereId = v ?? ''),
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Choix<int>(
              libelle: 'Jour',
              valeur: j,
              options: [for (var k = 1; k <= 6; k++) (k, _jours[k])],
              changer: (v) => maj(() => j = v ?? j),
            ),
          ),
          Row(children: [
            Expanded(
              child: OutlinedButton.icon(
                icon: const Icon(Icons.schedule, size: 18),
                label: Text('Début : $debut'),
                onPressed: () => choisirHeure(true),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: OutlinedButton.icon(
                icon: const Icon(Icons.schedule, size: 18),
                label: Text('Fin : ${fin ?? '—'}'),
                onPressed: () => choisirHeure(false),
              ),
            ),
          ]),
          if (fin != null)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(ecart > 0 ? 'Durée : ${duree(ecart)}' : 'La fin doit être après le début.',
                  style: TextStyle(color: ecart > 0 ? context.c.encre2 : context.c.danger, fontSize: 13)),
            ),
          if (creneau != null)
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                style: TextButton.styleFrom(foregroundColor: context.c.danger),
                icon: const Icon(Icons.delete_outline, size: 18),
                label: const Text('Retirer ce créneau'),
                onPressed: () async {
                  if (!await confirmer(ctx, 'Retirer ce créneau ?', '${creneau['matiere']['nom']}, ${_jours[creneau['jour'] as int].toLowerCase()} de ${creneau['debut']} à ${creneau['fin']}.',
                      action: 'Retirer', danger: true)) {
                    return;
                  }
                  if (!ctx.mounted) return;
                  if (await agir(ctx, () async => resultat = await Api.i.delete('/emplois-du-temps/creneaux/${creneau['id']}') as Map, succes: 'Créneau retiré.') &&
                      ctx.mounted) {
                    Navigator.pop(ctx, true);
                  }
                },
              ),
            ),
        ]);
      },
      () async {
        if (matiereId.isEmpty) throw ErreurApi(400, 'Choisissez la matière.');
        if (fin == null) throw ErreurApi(400, "Choisissez l'heure de fin.");
        final corps = {'classeId': classeId, 'versionId': (vue['version'] as Map?)?['id'], 'jour': j, 'debut': debut, 'fin': fin, 'matiereId': matiereId};
        resultat = await envoyerVerifie(
          context,
          (e) => Api.i.envoyer(creneau == null ? 'POST' : 'PUT', creneau == null ? '/emplois-du-temps/creneaux' : '/emplois-du-temps/creneaux/${creneau['id']}',
              corps: corps, entetes: e),
          cle: cle,
        ) as Map;
      },
    );
    if (ok && resultat != null) _afficher(resultat!);
  }

  Future<void> _nouvelleVersion(String classeId, Map vue) async {
    final aDeja = (vue['versions'] as List).isNotEmpty;
    DateTime? du;
    var copier = true;
    Map? resultat;
    final ok = await feuilleFormulaire(
      context,
      "Nouvelle version de l'emploi du temps",
      (ctx, maj) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text(
          "À partir de cette date, la nouvelle version remplace l'actuelle. Les jours d'avant gardent l'ancienne, pour que les absences déjà relevées restent justes.",
          style: TextStyle(color: context.c.encre2, fontSize: 13),
        ),
        const SizedBox(height: 12),
        OutlinedButton.icon(
          icon: const Icon(Icons.event, size: 18),
          label: Text(du == null ? (aDeja ? 'Choisir la date' : 'Depuis la rentrée (ou choisir une date)') : 'À partir du ${_date(du!.toIso8601String())}'),
          onPressed: () async {
            final d = await showDatePicker(context: ctx, firstDate: DateTime(2020), lastDate: DateTime(2100), initialDate: DateTime.now());
            if (d != null) maj(() => du = d);
          },
        ),
        if (aDeja)
          CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            value: copier,
            title: const Text('Reprendre les créneaux actuels, puis les modifier'),
            onChanged: (v) => maj(() => copier = v ?? true),
          ),
      ]),
      () async {
        if (aDeja && du == null) throw ErreurApi(400, 'Choisissez la date à partir de laquelle la nouvelle version vaut.');
        final jour = du == null ? null : '${du!.year}-${du!.month.toString().padLeft(2, '0')}-${du!.day.toString().padLeft(2, '0')}';
        resultat = await Api.i.post('/emplois-du-temps/versions', {'classeId': classeId, 'valableDu': jour, 'copier': copier}) as Map;
      },
      action: 'Créer',
    );
    if (ok && resultat != null) _afficher(resultat!);
  }

  Future<void> _supprimerVersion(Map vue) async {
    final v = vue['version'] as Map;
    if (!await confirmer(context, 'Supprimer cette version ?', '« ${_libelleVersion(v)} » et ses ${(vue['creneaux'] as List).length} créneau(x) seront supprimés.',
        action: 'Supprimer', danger: true)) {
      return;
    }
    if (mounted && await agir(context, () => Api.i.delete('/emplois-du-temps/versions/${v['id']}'), succes: 'Version supprimée.')) {
      setState(() {
        _versionId = null;
        _rechargement++;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final sg = Etat.i.estSG;
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
          key: ValueKey('$classeId|$_versionId|$_rechargement'),
          charger: () async => await Api.i.get('/emplois-du-temps?classeId=$classeId${_versionId == null ? '' : '&versionId=$_versionId'}') as Map,
          construire: (context, vue, recharger) {
            final c = context.c;
            final creneaux = (vue['creneaux'] as List).cast<Map>();
            final versions = (vue['versions'] as List).cast<Map>();
            final version = vue['version'] as Map?;
            final jours = [for (var j = 1; j <= 6; j++) j].where((j) => j < 6 || sg || creneaux.any((x) => x['jour'] == j));
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
                      changer: (v) => setState(() {
                        _classe = v;
                        _versionId = null;
                      }),
                    ),
                    if (versions.length > 1) ...[
                      const SizedBox(height: 12),
                      Choix<String>(
                        libelle: 'Version',
                        valeur: version?['id'] as String?,
                        options: [for (final v in versions) (v['id'] as String, _libelleVersion(v))],
                        changer: (v) => setState(() => _versionId = v),
                      ),
                    ],
                    if (sg)
                      Wrap(spacing: 8, children: [
                        TextButton.icon(
                          icon: const Icon(Icons.edit_calendar_outlined, size: 18),
                          label: const Text('Nouvelle version'),
                          onPressed: () => _nouvelleVersion(classeId, vue),
                        ),
                        if (version != null && versions.length > 1)
                          TextButton.icon(
                            style: TextButton.styleFrom(foregroundColor: c.danger),
                            icon: const Icon(Icons.delete_outline, size: 18),
                            label: const Text('Supprimer cette version'),
                            onPressed: () => _supprimerVersion(vue),
                          ),
                      ]),
                  ]),
                ),
              ),
              if (version != null)
                Text('  ${_libelleVersion(version)} · ${duree(vue['minutesParSemaine'] as int)} de cours par semaine', style: TextStyle(color: c.encre2)),
              if (version == null && !sg)
                const Carte(enfant: Vide("Pas encore d'emploi du temps", texte: "Le Surveillant Général ne l'a pas encore saisi pour cette classe.")),
              if (version != null || sg)
                for (final j in jours) _jour(context, classeId, vue, j, creneaux.where((x) => x['jour'] == j).toList(), sg),
            ]);
          },
        );
      },
    );
  }

  Widget _jour(BuildContext context, String classeId, Map vue, int j, List<Map> liste, bool sg) {
    final c = context.c;
    final primaire = Theme.of(context).colorScheme.primary;
    final sur = Theme.of(context).brightness == Brightness.dark ? const Color(0xFF0C1826) : Colors.white;
    final total = liste.fold<int>(0, (n, x) => n + (x['duree'] as int));
    return Card(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Container(
          color: primaire,
          padding: const EdgeInsets.fromLTRB(14, 9, 14, 9),
          child: Row(children: [
            Expanded(child: Text(_jours[j], style: TextStyle(color: sur, fontWeight: FontWeight.w700, fontSize: 16))),
            if (total > 0) Text(duree(total), style: TextStyle(color: sur.withValues(alpha: 0.9), fontSize: 13)),
          ]),
        ),
        if (liste.isEmpty) Padding(padding: const EdgeInsets.all(14), child: Center(child: Text('Pas de cours', style: TextStyle(color: c.encre3)))),
        for (final (i, x) in liste.indexed) ...[
          if (i > 0) Divider(height: 1, color: c.bord),
          InkWell(
            onTap: sg ? () => _formulaireCreneau(classeId, vue, creneau: x, jour: j) : null,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Expanded(child: Text('${x['debut']} – ${x['fin']}', style: const TextStyle(fontWeight: FontWeight.w700))),
                  Text(duree(x['duree'] as int), style: TextStyle(color: c.encre2, fontSize: 12.5)),
                ]),
                Text('${x['matiere']['nom']}', style: const TextStyle(fontWeight: FontWeight.w500, fontSize: 15)),
                Text(
                  x['matiere']['professeur'] == null ? 'Aucun enseignant' : '${x['matiere']['professeur']['prenom']} ${x['matiere']['professeur']['nom']}',
                  style: TextStyle(color: c.encre2, fontSize: 12.5),
                ),
                for (final k in (x['conflits'] as List).cast<Map>())
                  Padding(
                    padding: const EdgeInsets.only(top: 3),
                    child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Icon(Icons.warning_amber_rounded, size: 15, color: c.danger),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          k['memeClasse'] == true
                              ? 'Même heure que ${k['matiere']} (${k['debut']} – ${k['fin']})'
                              : 'Enseignant attendu en ${k['classe']} (${k['matiere']}, ${k['debut']} – ${k['fin']})',
                          style: TextStyle(color: c.danger, fontSize: 12.5, fontWeight: FontWeight.w600),
                        ),
                      ),
                    ]),
                  ),
              ]),
            ),
          ),
        ],
        if (sg)
          Material(
            color: primaire.withValues(alpha: 0.10),
            child: InkWell(
              onTap: () => _formulaireCreneau(classeId, vue, jour: j),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 11),
                child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                  Icon(Icons.add, size: 18, color: primaire),
                  const SizedBox(width: 6),
                  Text('Ajouter', style: TextStyle(color: primaire, fontWeight: FontWeight.w700)),
                ]),
              ),
            ),
          ),
      ]),
    );
  }
}
