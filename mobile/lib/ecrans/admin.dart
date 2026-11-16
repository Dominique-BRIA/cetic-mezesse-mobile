import 'package:flutter/material.dart';

import '../api.dart';
import '../etat.dart';
import '../theme.dart';
import '../widgets.dart';
import 'organisation.dart';

// ---------------- Années et séquences ----------------

class EcranAnnees extends StatefulWidget {
  const EcranAnnees({super.key});
  @override
  State<EcranAnnees> createState() => _EcranAnneesState();
}

class _EcranAnneesState extends State<EcranAnnees> {
  Future<void> _rafraichir() => Etat.i.chargerAnnees();

  Future<void> _nouvelle() async {
    final e = Etat.i;
    final debut = e.annees.isEmpty ? DateTime.now().year : int.parse((e.annees.first['libelle'] as String).substring(0, 4)) + 1;
    final libelle = TextEditingController(text: '$debut-${debut + 1}');
    String? copier = e.annees.isEmpty ? null : e.annees.first['id'] as String;
    var activer = false;
    String? cree;
    final ok = await feuilleFormulaire(
      context,
      'Nouvelle année scolaire',
      (ctx, maj) => Column(children: [
        TextField(controller: libelle, decoration: const InputDecoration(labelText: 'Libellé', helperText: 'Les 6 séquences sont créées automatiquement')),
        const SizedBox(height: 12),
        Choix<String>(
          libelle: "Reprendre l'organisation de",
          valeur: copier ?? '',
          options: [('', 'Ne rien reprendre'), for (final a in e.annees) (a['id'] as String, a['libelle'] as String)],
          changer: (v) => maj(() => copier = v == '' ? null : v),
        ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text("En faire l'année en cours"),
          value: activer,
          onChanged: (v) => maj(() => activer = v),
        ),
      ]),
      () async {
        final r = await Api.i.envoyer('POST', '/annees',
            corps: {'libelle': libelle.text.trim(), 'copierDepuisId': copier, 'activer': activer}, annee: false) as Map;
        cree = r['id'] as String;
      },
    );
    if (ok) {
      await e.chargerAnnees();
      if (cree != null) await e.choisirAnnee(cree!);
    }
  }

  @override
  Widget build(BuildContext context) {
    final e = Etat.i;
    final sg = e.estSG;
    final c = context.c;
    return ListenableBuilder(
      listenable: e,
      builder: (context, _) => Scaffold(
        backgroundColor: Colors.transparent,
        floatingActionButton:
            sg ? FloatingActionButton.extended(onPressed: _nouvelle, icon: const Icon(Icons.add), label: const Text('Nouvelle année')) : null,
        body: Defilement(rafraichir: _rafraichir, enfants: [
          if (e.annee != null)
            Carte(
              titre: 'Séquences de ${e.annee!['libelle']}',
              sansMarge: true,
              enfant: Column(children: [
                for (final s in e.sequences)
                  ListTile(
                    title: Text('Séquence ${s['numero']} · trimestre ${s['trimestre']}'),
                    subtitle: Align(
                      alignment: Alignment.centerLeft,
                      child: s['saisieOuverte'] == true ? const EtatTexte('Saisie ouverte', ton: 'succes') : const EtatTexte('Saisie fermée'),
                    ),
                    trailing: sg
                        ? Switch(
                            value: s['saisieOuverte'] == true,
                            onChanged: (v) async {
                              final ok = await agir(
                                context,
                                () => Api.i.envoyer('PATCH', '/annees/sequences/${s['id']}', corps: {'saisieOuverte': v}, annee: false),
                                succes: 'Saisie de la séquence ${s['numero']} ${v ? 'ouverte' : 'fermée'}.',
                              );
                              if (ok) await e.chargerAnnees();
                            },
                          )
                        : null,
                  ),
                Padding(
                  padding: const EdgeInsets.all(14),
                  child: Text('Une séquence fermée ne peut plus être modifiée par les professeurs.', style: TextStyle(color: c.encre2, fontSize: 13)),
                ),
              ]),
            ),
          Carte(
            titre: 'Années scolaires',
            sansMarge: true,
            enfant: Column(children: [
              for (final a in e.annees)
                ListTile(
                  title: Text(a['libelle'] as String, style: const TextStyle(fontWeight: FontWeight.w600)),
                  subtitle: Text('${a['_count']['classes']} classes · ${a['_count']['inscriptions']} inscriptions'),
                  trailing: a['active'] == true
                      ? const EtatTexte('En cours', ton: 'succes')
                      : sg
                          ? TextButton(
                              onPressed: () async {
                                if (!await confirmer(context, 'Rendre active ?', "${a['libelle']} deviendra l'année en cours.")) return;
                                if (context.mounted &&
                                    await agir(context, () => Api.i.envoyer('POST', '/annees/${a['id']}/activer', annee: false), succes: 'Année activée.')) {
                                  await e.chargerAnnees();
                                }
                              },
                              child: const Text('Rendre active'),
                            )
                          : const EtatTexte('Archivée'),
                  onTap: () => e.choisirAnnee(a['id'] as String),
                ),
            ]),
          ),
        ]),
      ),
    );
  }
}

// ---------------- Paramètres ----------------

class EcranParametres extends StatefulWidget {
  const EcranParametres({super.key});
  @override
  State<EcranParametres> createState() => _EcranParametresState();
}

const _champsEtablissement = [
  ('nomFr', 'Nom (français)'),
  ('nomEn', 'Nom (anglais)'),
  ('sigle', 'Sigle'),
  ('sigleEn', 'Sigle anglais'),
  ('code', 'Code / immatriculation'),
  ('regionFr', 'Région (français)'),
  ('regionEn', 'Région (anglais)'),
  ('departementFr', 'Département (français)'),
  ('departementEn', 'Département (anglais)'),
  ('arrondissement', 'Arrondissement'),
  ('localite', 'Localité'),
  ('boitePostale', 'Boîte postale'),
  ('telephone', 'Téléphone'),
  ('prefixeMatricule', 'Préfixe des matricules'),
];

class _EcranParametresState extends State<EcranParametres> {
  final Map<String, TextEditingController> _etab = {};
  final Map<String, List<(TextEditingController, TextEditingController, TextEditingController)>> _baremes = {'GRADE': [], 'COTE': []};
  final _seuil = TextEditingController();
  // Sanctions pour absences non justifiées : trois paliers fixes, le SG règle à partir de combien d'heures.
  static const _paliers = [('AVERTISSEMENT', 'Avertissement conduite'), ('BLAME', 'Blâme conduite'), ('EXCLUSION', 'Exclusion')];
  final Map<String, TextEditingController> _sanctions = {for (final (l, _) in _paliers) l: TextEditingController()};
  // Règles des résultats : délibération, refus du tableau d'honneur, matières composées, départage de la première place.
  final _deliberation = TextEditingController();
  final _heuresRefus = TextEditingController();
  final _nonClasse = TextEditingController();
  final _ignorees = TextEditingController();
  List<Map<String, Object?>> _criteres = []; // {type, groupe, actif}, dans l'ordre choisi

  static String _nombre(Object? v) => v == null ? '' : '$v'.replaceAll('.', ',');
  static double? _lire(String t) => t.trim().isEmpty ? null : double.tryParse(t.trim().replaceAll(',', '.'));
  static String _cle(Map c) => c['type'] == 'GROUPE' ? 'GROUPE:${'${c['groupe']}'.toLowerCase()}' : '${c['type']}';

  static String _heures(Object? minutes) {
    if (minutes == null) return '';
    final h = (minutes as num) / 60;
    return (h == h.roundToDouble() ? h.toInt().toString() : h.toStringAsFixed(2)).replaceAll('.', ',');
  }

  // Le Directeur consulte les informations et les barèmes ; il règle avec le SG le tableau d'honneur.
  bool get _modifiable => Etat.i.estSG;

  Future<bool> _charger() async {
    final e = await Api.i.get('/etablissement', annee: false) as Map? ?? {};
    for (final (k, _) in _champsEtablissement) {
      _etab[k] = TextEditingController(text: e[k] == null ? '' : '${e[k]}');
    }
    _seuil.text = ((e['seuilTableauHonneur'] as num?) ?? 12).toStringAsFixed(2).replaceAll('.', ',');
    final r = (e['reglesResultats'] as Map?) ?? {};
    _deliberation.text = r['moyenneDeliberation'] == null ? '' : (r['moyenneDeliberation'] as num).toStringAsFixed(2).replaceAll('.', ',');
    _heuresRefus.text = _nombre(r['heuresRefusTableauHonneur']);
    _nonClasse.text = _nombre(r['seuilNonClasse'] ?? 33.33);
    _ignorees.text = _nombre(r['seuilMatieresIgnorees'] ?? 66.67);
    final groupes = (await Api.i.get('/groupes') as List).cast<Map>();
    final noms = {for (final g in groupes) g['nom'] as String}.toList();
    final possibles = <Map<String, Object?>>[
      for (final n in noms) {'type': 'GROUPE', 'groupe': n},
      {'type': 'DISCIPLINE'},
      {'type': 'ALPHABETIQUE'},
    ];
    // Sans réglage : les groupes « professionnels », puis la discipline, puis l'ordre alphabétique.
    final enregistres = ((r['criteres'] as List?) ?? []).cast<Map>();
    final choisis = enregistres.isNotEmpty
        ? [for (final c in enregistres) {'type': c['type'], 'groupe': c['groupe']}]
        : [
            ...possibles.where((c) => c['type'] == 'GROUPE' && '${c['groupe']}'.toLowerCase().contains('professionnel')),
            {'type': 'DISCIPLINE'},
            {'type': 'ALPHABETIQUE'},
          ];
    _criteres = [
      for (final c in choisis) {...c, 'actif': true},
      for (final p in possibles)
        if (!choisis.any((c) => _cle(c) == _cle(p))) {...p, 'actif': false},
    ];
    final s = (await Api.i.get('/sanctions-absences', annee: false) as List).cast<Map>();
    for (final (l, _) in _paliers) {
      _sanctions[l]!.text = _heures(s.where((x) => x['ligne'] == l).firstOrNull?['minutes']);
    }
    final b = (await Api.i.get('/baremes', annee: false) as List).cast<Map>()
      ..sort((x, y) => (y['min'] as num).compareTo(x['min'] as num));
    for (final t in ['GRADE', 'COTE']) {
      _baremes[t] = [
        for (final l in b.where((l) => l['type'] == t))
          (
            TextEditingController(text: l['libelle'] as String),
            TextEditingController(text: l['libelleLong'] as String? ?? ''),
            TextEditingController(text: '${l['min']}'.replaceAll('.', ',')),
          ),
      ];
    }
    return true;
  }

  @override
  Widget build(BuildContext context) {
    return Charge<bool>(
      charger: _charger,
      // Le chargement remplit le formulaire : on attend la version du serveur.
      copieImmediate: false,
      construire: (context, _, __) => Defilement(enfants: [
        Carte(
          titre: "Tableau d'honneur",
          action: TextButton(
            onPressed: () {
              final v = double.tryParse(_seuil.text.trim().replaceAll(',', '.'));
              if (v == null) return message(context, 'Moyenne minimale invalide.', erreur: true);
              agir(
                context,
                () => Api.i.envoyer('PUT', '/etablissement/tableau-honneur', corps: {'seuil': v}, annee: false),
                succes: "Moyenne minimale du tableau d'honneur enregistrée.",
              );
            },
            child: const Text('Enregistrer'),
          ),
          enfant: TextField(
            controller: _seuil,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(
              labelText: 'Moyenne minimale',
              helperText: "Un élève figure au tableau d'honneur dès que sa moyenne de la période atteint cette valeur.",
              helperMaxLines: 2,
            ),
          ),
        ),
        _reglesResultats(),
        _sanctionsAbsences(),
        Carte(
          titre: 'Établissement',
          action: _modifiable
              ? TextButton(
                  onPressed: () => agir(
                    context,
                    () => Api.i.envoyer('PUT', '/etablissement', corps: {for (final MapEntry(:key, :value) in _etab.entries) key: value.text.trim()}, annee: false),
                    succes: 'Informations enregistrées.',
                  ),
                  child: const Text('Enregistrer'),
                )
              : null,
          enfant: Column(children: [
            if (!_modifiable)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Text('Ces informations sont tenues par le Surveillant Général.', style: TextStyle(color: context.c.encre2, fontSize: 13)),
              ),
            for (final (k, l) in _champsEtablissement)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: TextField(controller: _etab[k], readOnly: !_modifiable, decoration: InputDecoration(labelText: l)),
              ),
          ]),
        ),
        _bareme('GRADE', 'Grades par matière'),
        _bareme('COTE', 'Cotes de la moyenne générale'),
      ]),
    );
  }

  /// Règles des résultats ; le départage de la première place se range par importance (flèches) et se coche.
  Widget _reglesResultats() {
    String libelle(Map c) => c['type'] == 'GROUPE'
        ? 'Moyenne du groupe « ${c['groupe']} »'
        : c['type'] == 'DISCIPLINE'
            ? "Discipline : le moins d'heures d'absence non justifiées"
            : 'Ordre alphabétique des noms';
    return StatefulBuilder(
      builder: (context, maj) => Carte(
        titre: 'Résultats, classement et délibération',
        action: TextButton(
          onPressed: () {
            final nonClasse = _lire(_nonClasse.text);
            final ignorees = _lire(_ignorees.text);
            if (nonClasse == null || ignorees == null) return message(context, 'Indiquez les deux parts des matières composées.', erreur: true);
            agir(
              context,
              () => Api.i.envoyer('PUT', '/etablissement/resultats', annee: false, corps: {
                'moyenneDeliberation': _lire(_deliberation.text),
                'heuresRefusTableauHonneur': _lire(_heuresRefus.text)?.round(),
                'seuilNonClasse': nonClasse,
                'seuilMatieresIgnorees': ignorees,
                'criteres': [
                  for (final c in _criteres.where((c) => c['actif'] == true)) {'type': c['type'], 'groupe': c['type'] == 'GROUPE' ? c['groupe'] : null},
                ],
              }),
              succes: 'Règles des résultats enregistrées.',
            );
          },
          child: const Text('Enregistrer'),
        ),
        enfant: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          TextField(
            controller: _deliberation,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(
              labelText: 'Moyenne de délibération',
              helperText: "Sur la moyenne annuelle : à partir de cette moyenne (par exemple 9,00), l'élève passe après délibération. Vide : pas de délibération.",
              helperMaxLines: 3,
            ),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _heuresRefus,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
              labelText: "Refus du tableau d'honneur (heures)",
              helperText: "À partir de ce nombre d'heures d'absence non justifiées sur la période. Vide : pas de limite.",
              helperMaxLines: 2,
            ),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _nonClasse,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(labelText: 'Non classé en dessous de (% des matières)', helperText: '1/3 : 33,33'),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _ignorees,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(
              labelText: 'Matières ignorées à partir de (% des matières)',
              helperText: 'En dessous, les matières non composées valent 0 ; 2/3 : 66,67',
              helperMaxLines: 2,
            ),
          ),
          const SizedBox(height: 14),
          const Text('Élève désigné parmi les ex æquo', style: TextStyle(fontWeight: FontWeight.w700)),
          Text(
            "Les rangs gardent leurs ex æquo. Parmi des ex æquo, à n'importe quel rang, ces critères, dans l'ordre (cochez et rangez-les), désignent celui qui porte son rang sans « ex » (par exemple « 1er » ou « 5e ») sur son bulletin et devant les autres ex æquo au tableau d'honneur. En dernier recours, un tirage au sort.",
            style: TextStyle(color: context.c.encre2, fontSize: 12.5),
          ),
          for (var i = 0; i < _criteres.length; i++)
            Row(children: [
              Checkbox(value: _criteres[i]['actif'] == true, onChanged: (v) => maj(() => _criteres[i]['actif'] = v == true)),
              Expanded(
                child: Text(libelle(_criteres[i]), style: TextStyle(fontSize: 13.5, color: _criteres[i]['actif'] == true ? null : context.c.encre3)),
              ),
              IconButton(
                tooltip: 'Monter',
                icon: const Icon(Icons.arrow_upward, size: 18),
                onPressed: i == 0 ? null : () => maj(() => _criteres.insert(i - 1, _criteres.removeAt(i))),
              ),
              IconButton(
                tooltip: 'Descendre',
                icon: const Icon(Icons.arrow_downward, size: 18),
                onPressed: i == _criteres.length - 1 ? null : () => maj(() => _criteres.insert(i + 1, _criteres.removeAt(i))),
              ),
            ]),
        ]),
      ),
    );
  }

  /// Sanctions pour absences non justifiées : le SG indique à partir de combien d'heures ; vide : non utilisée.
  Widget _sanctionsAbsences() {
    return Carte(
      titre: 'Sanctions pour absences non justifiées',
      action: _modifiable
          ? TextButton(
              onPressed: () => agir(
                context,
                () => Api.i.envoyer('PUT', '/sanctions-absences',
                    corps: [
                      for (final (l, _) in _paliers)
                        {'ligne': l, 'heures': _sanctions[l]!.text.trim().isEmpty ? null : double.tryParse(_sanctions[l]!.text.trim().replaceAll(',', '.'))}
                    ],
                    annee: false),
                succes: 'Sanctions enregistrées.',
              ),
              child: const Text('Enregistrer'),
            )
          : null,
      enfant: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text(
          "Heures non justifiées cumulées depuis la rentrée. Le bulletin porte la sanction la plus élevée atteinte. À l'exclusion, le Directeur est prévenu et décide : exclusion définitive, exclusion temporaire ou sursis. Case vide : sanction non utilisée.",
          style: TextStyle(color: context.c.encre2, fontSize: 12.5),
        ),
        for (final (l, libelle) in _paliers)
          Padding(
            padding: const EdgeInsets.only(top: 10),
            child: Row(children: [
              Expanded(child: Text(libelle, style: const TextStyle(fontWeight: FontWeight.w600))),
              SizedBox(
                width: 110,
                child: TextField(
                  controller: _sanctions[l],
                  readOnly: !_modifiable,
                  textAlign: TextAlign.right,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(labelText: 'À partir de', suffixText: 'h', isDense: true),
                ),
              ),
            ]),
          ),
      ]),
    );
  }

  Widget _bareme(String type, String titre) {
    final lignes = _baremes[type]!;
    return StatefulBuilder(
      builder: (context, maj) => Carte(
        titre: titre,
        action: _modifiable
            ? TextButton(
                onPressed: () => agir(
                  context,
                  () => Api.i.envoyer('PUT', '/baremes/$type',
                      corps: [
                        for (final (l, ll, m) in lignes)
                          {'libelle': l.text.trim(), 'libelleLong': ll.text.trim(), 'min': double.tryParse(m.text.replaceAll(',', '.')) ?? -1}
                      ],
                      annee: false),
                  succes: 'Barème enregistré.',
                ),
                child: const Text('Enregistrer'),
              )
            : null,
        enfant: Column(children: [
          Text("Chaque mention s'applique à partir de sa note minimale (incluse).", style: TextStyle(color: context.c.encre2, fontSize: 13)),
          const SizedBox(height: 10),
          for (final ligne in lignes)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(children: [
                SizedBox(width: 72, child: TextField(controller: ligne.$1, readOnly: !_modifiable, decoration: const InputDecoration(labelText: 'Mention'))),
                const SizedBox(width: 8),
                if (type == 'COTE') ...[
                  Expanded(child: TextField(controller: ligne.$2, readOnly: !_modifiable, decoration: const InputDecoration(labelText: 'Signification'))),
                  const SizedBox(width: 8),
                ],
                SizedBox(
                  width: 80,
                  child: TextField(
                    controller: ligne.$3,
                    readOnly: !_modifiable,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(labelText: 'Dès'),
                  ),
                ),
                if (_modifiable) IconButton(icon: const Icon(Icons.close, size: 18), onPressed: () => maj(() => lignes.remove(ligne))),
              ]),
            ),
          if (_modifiable)
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                icon: const Icon(Icons.add, size: 18),
                label: const Text('Ajouter une mention'),
                onPressed: () => maj(() => lignes.add((TextEditingController(), TextEditingController(), TextEditingController()))),
              ),
            ),
        ]),
      ),
    );
  }
}
