import 'package:flutter/material.dart';

import '../api.dart';
import '../etat.dart';
import '../format.dart';
import '../theme.dart';
import '../widgets.dart';
import 'carriere.dart';

Future<List<Map<String, dynamic>>> _profs() async =>
    (await Api.i.get('/utilisateurs?role=PROFESSEUR') as List).cast<Map<String, dynamic>>().where((p) => p['actif'] == true).toList();

/// Formulaire générique en feuille du bas.
Future<bool> feuilleFormulaire(BuildContext context, String titre, Widget Function(BuildContext, StateSetter) champs, Future<void> Function() enregistrer,
    {String action = 'Enregistrer'}) async {
  final ok = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, maj) => Padding(
        padding: EdgeInsets.fromLTRB(16, 0, 16, MediaQuery.of(ctx).viewInsets.bottom + 16),
        child: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text(titre, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
            const SizedBox(height: 14),
            champs(ctx, maj),
            const SizedBox(height: 14),
            FilledButton(
              onPressed: () async {
                if (await agir(ctx, enregistrer) && ctx.mounted) Navigator.pop(ctx, true);
              },
              child: Text(action),
            ),
          ]),
        ),
      ),
    ),
  );
  return ok == true;
}

Widget _espace(Widget w) => Padding(padding: const EdgeInsets.only(bottom: 12), child: w);

// ---------------- Classes ----------------

class EcranClasses extends StatefulWidget {
  const EcranClasses({super.key});
  @override
  State<EcranClasses> createState() => _EcranClassesState();
}

class _EcranClassesState extends State<EcranClasses> {
  int _version = 0;

  // Le nom découle du niveau, de la spécialité et de la lettre (RG-29) : on n'en montre que l'aperçu.
  Future<void> _formulaire(Map? classe, List<Map<String, dynamic>> classes) async {
    final profs = await _profs();
    final specialites = await _specialites();
    if (!mounted) return;
    var niveau = classe?['niveau'] as int? ?? 1;
    var specialiteId = classe?['specialiteId'] as String? ?? '';
    String? pp = classe?['profPrincipalId'] as String?;
    String apercu() {
      bool meme(Map c) => c['niveau'] == niveau && (c['specialiteId'] ?? '') == specialiteId;
      final voisines = classes.where((c) => meme(c) && c['id'] != classe?['id']).toList();
      final reste = classe != null && meme(classe);
      final rang = reste ? voisines.where((c) => (c['numero'] as int) < (classe['numero'] as int)).length : voisines.length;
      final sp = specialites.where((s) => s['id'] == specialiteId).firstOrNull;
      return nomClasse(niveau, sp?['nom'] as String?, rang, voisines.length + 1);
    }

    final ok = await feuilleFormulaire(
      context,
      classe == null ? 'Nouvelle classe' : 'Modifier ${classe['nom']}',
      (ctx, maj) => Column(children: [
        _espace(Choix<int>(
          libelle: 'Niveau',
          valeur: niveau,
          options: [for (var n = 1; n <= 7; n++) (n, '${n == 1 ? '1re' : '${n}e'} année')],
          changer: (v) => maj(() => niveau = v!),
        )),
        _espace(Choix<String>(
          libelle: 'Spécialité',
          valeur: specialiteId,
          options: [('', 'Sans spécialité'), for (final s in specialites) (s['id'] as String, s['nom'] as String)],
          changer: (v) => maj(() => specialiteId = v ?? ''),
        )),
        _espace(InputDecorator(
          decoration: const InputDecoration(labelText: 'Nom de la classe', helperText: "Une lettre A, B… s'ajoute quand le niveau et la spécialité comptent plusieurs classes.",
              helperMaxLines: 2),
          child: Text(apercu(), style: const TextStyle(fontWeight: FontWeight.w700)),
        )),
        Choix<String>(
          libelle: 'Professeur principal',
          valeur: pp ?? '',
          options: [('', 'Aucun'), for (final p in profs) (p['id'] as String, '${p['nom']} ${p['prenom']}')],
          changer: (v) => maj(() => pp = v == '' ? null : v),
        ),
      ]),
      () async {
        final corps = {'niveau': niveau, 'specialiteId': specialiteId.isEmpty ? null : specialiteId, 'profPrincipalId': pp};
        classe == null ? await Api.i.post('/classes', corps) : await Api.i.put('/classes/${classe['id']}', corps);
      },
    );
    if (ok) setState(() => _version++);
  }

  @override
  Widget build(BuildContext context) {
    return Charge<List<Map<String, dynamic>>>(
      key: ValueKey(_version),
      charger: chargerClasses,
      construire: (context, classes, recharger) => Scaffold(
        backgroundColor: Colors.transparent,
        floatingActionButton: Etat.i.estSG
            ? FloatingActionButton.extended(
                onPressed: () => _formulaire(null, classes), icon: const Icon(Icons.add), label: const Text('Nouvelle classe'))
            : null,
        body: Defilement(rafraichir: recharger, enfants: [
          if (Etat.i.estSG)
            Align(
              alignment: Alignment.centerLeft,
              child: OutlinedButton.icon(
                icon: const Icon(Icons.sell_outlined, size: 18),
                label: const Text('Spécialités'),
                onPressed: () async {
                  await Navigator.push(context, MaterialPageRoute(builder: (_) => const EcranSpecialites()));
                  setState(() => _version++);
                },
              ),
            ),
          if (classes.isEmpty) const Carte(enfant: Vide('Aucune classe', texte: 'Créez les spécialités, puis les classes et leurs groupes de matières.')),
          for (final c in classes)
            Carte(
              titre: c['nom'] as String,
              action: Etat.i.estSG
                  ? Row(mainAxisSize: MainAxisSize.min, children: [
                      IconButton(icon: const Icon(Icons.edit_outlined, size: 20), onPressed: () => _formulaire(c, classes)),
                      // Une classe sans élève peut être supprimée ; les lettres des autres se resserrent.
                      if (c['_count']['inscriptions'] == 0)
                        IconButton(
                          icon: const Icon(Icons.delete_outline, size: 20),
                          onPressed: () async {
                            if (!await confirmer(context, 'Supprimer cette classe ?', '${c['nom']} et ses matières seront supprimées.',
                                action: 'Supprimer', danger: true)) {
                              return;
                            }
                            if (context.mounted &&
                                await agir(context, () => Api.i.delete('/classes/${c['id']}'), succes: 'Classe supprimée.')) {
                              setState(() => _version++);
                            }
                          },
                        ),
                    ])
                  : null,
              enfant: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                LigneInfo('Spécialité', c['specialite']?['nom'] as String? ?? '—'),
                LigneInfo('Élèves', '${c['_count']['inscriptions']}', gras: true),
                LigneInfo('Matières', '${c['_count']['matieres']}'),
                LigneInfo('Prof. principal', c['profPrincipal'] == null ? '—' : '${c['profPrincipal']['prenom']} ${c['profPrincipal']['nom']}'),
                const SizedBox(height: 8),
                Wrap(spacing: 8, children: [
                  OutlinedButton.icon(
                    icon: const Icon(Icons.picture_as_pdf_outlined, size: 18),
                    label: const Text('Liste PDF'),
                    onPressed: () => agir(context, () => Api.i.ouvrirDocument('/documents/liste?classeId=${c['id']}&format=pdf')),
                  ),
                  OutlinedButton.icon(
                    icon: const Icon(Icons.table_chart_outlined, size: 18),
                    label: const Text('Excel'),
                    onPressed: () => agir(context, () => Api.i.ouvrirDocument('/documents/liste?classeId=${c['id']}&format=xlsx')),
                  ),
                ]),
              ]),
            ),
        ]),
      ),
    );
  }
}

// ---------------- Spécialités ----------------

Future<List<Map<String, dynamic>>> _specialites() async =>
    (await Api.i.get('/specialites', annee: false) as List).cast<Map<String, dynamic>>();

class EcranSpecialites extends StatefulWidget {
  const EcranSpecialites({super.key});
  @override
  State<EcranSpecialites> createState() => _EcranSpecialitesState();
}

class _EcranSpecialitesState extends State<EcranSpecialites> {
  int _version = 0;

  Future<void> _formulaire(Map? s) async {
    final nom = TextEditingController(text: s?['nom'] as String? ?? '');
    final nomEn = TextEditingController(text: s?['nomEn'] as String? ?? '');
    final ok = await feuilleFormulaire(
      context,
      s == null ? 'Nouvelle spécialité' : 'Modifier ${s['nom']}',
      (ctx, maj) => Column(children: [
        _espace(TextField(controller: nom, decoration: const InputDecoration(labelText: 'Nom', helperText: '« Mécanique », « Électricité »…'))),
        TextField(controller: nomEn, decoration: const InputDecoration(labelText: 'Nom en anglais (facultatif)')),
      ]),
      () async {
        final corps = {'nom': nom.text.trim(), 'nomEn': nomEn.text.trim()};
        s == null
            ? await Api.i.envoyer('POST', '/specialites', corps: corps, annee: false)
            : await Api.i.envoyer('PUT', '/specialites/${s['id']}', corps: corps, annee: false);
      },
    );
    if (ok) setState(() => _version++);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Spécialités')),
      floatingActionButton:
          FloatingActionButton.extended(onPressed: () => _formulaire(null), icon: const Icon(Icons.add), label: const Text('Nouvelle spécialité')),
      body: Charge<List<Map<String, dynamic>>>(
        key: ValueKey(_version),
        charger: _specialites,
        construire: (context, liste, recharger) => Defilement(rafraichir: recharger, enfants: [
          Text("Elles servent d'une année sur l'autre. Renommer une spécialité renomme les classes qui la portent.",
              style: TextStyle(color: context.c.encre2)),
          const SizedBox(height: 8),
          if (liste.isEmpty) const Carte(enfant: Vide('Aucune spécialité')),
          for (final s in liste)
            Carte(
              titre: s['nom'] as String,
              action: Row(mainAxisSize: MainAxisSize.min, children: [
                IconButton(icon: const Icon(Icons.edit_outlined, size: 20), onPressed: () => _formulaire(s)),
                if (s['_count']['classes'] == 0)
                  IconButton(
                    icon: const Icon(Icons.delete_outline, size: 20),
                    onPressed: () async {
                      if (!await confirmer(context, 'Supprimer cette spécialité ?', s['nom'] as String, danger: true)) return;
                      if (context.mounted &&
                          await agir(context, () => Api.i.envoyer('DELETE', '/specialites/${s['id']}', annee: false), succes: 'Spécialité supprimée.')) {
                        setState(() => _version++);
                      }
                    },
                  ),
              ]),
              enfant: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                LigneInfo('En anglais', s['nomEn'] as String? ?? '—'),
                LigneInfo('Classes', '${s['_count']['classes']}'),
              ]),
            ),
        ]),
      ),
    );
  }
}

// ---------------- Groupes ----------------

class EcranGroupes extends StatefulWidget {
  const EcranGroupes({super.key});
  @override
  State<EcranGroupes> createState() => _EcranGroupesState();
}

class _EcranGroupesState extends State<EcranGroupes> {
  int _version = 0;

  Future<void> _formulaire(Map? g, int suivant) async {
    final classes = await chargerClasses();
    if (!mounted) return;
    final nom = TextEditingController(text: g?['nom'] as String? ?? '');
    final nomEn = TextEditingController(text: g?['nomEn'] as String? ?? '');
    final ordre = TextEditingController(text: '${g?['ordre'] ?? suivant}');
    final choisies = <String>{...((g?['classes'] as List?) ?? []).map((c) => c['id'] as String)};
    final ok = await feuilleFormulaire(
      context,
      g == null ? 'Nouveau groupe de matières' : 'Modifier ${g['nom']}',
      (ctx, maj) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        _espace(TextField(controller: nom, decoration: const InputDecoration(labelText: 'Nom'))),
        _espace(TextField(controller: nomEn, decoration: const InputDecoration(labelText: 'Nom en anglais'))),
        _espace(TextField(controller: ordre, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Ordre sur le bulletin'))),
        Text('CLASSES CONCERNÉES', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: ctx.c.encre2)),
        for (final c in classes)
          CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            value: choisies.contains(c['id']),
            title: Text(c['nom'] as String),
            onChanged: (v) => maj(() => v == true ? choisies.add(c['id'] as String) : choisies.remove(c['id'])),
          ),
      ]),
      () async {
        final corps = {'nom': nom.text.trim(), 'nomEn': nomEn.text.trim(), 'ordre': int.tryParse(ordre.text) ?? 1, 'classeIds': choisies.toList()};
        g == null ? await Api.i.post('/groupes', corps) : await Api.i.put('/groupes/${g['id']}', corps);
      },
    );
    if (ok) setState(() => _version++);
  }

  @override
  Widget build(BuildContext context) {
    return Charge<List>(
      key: ValueKey(_version),
      charger: () async => await Api.i.get('/groupes') as List,
      construire: (context, groupes, recharger) => Scaffold(
        backgroundColor: Colors.transparent,
        floatingActionButton: Etat.i.estSG
            ? FloatingActionButton.extended(
                onPressed: () => _formulaire(null, groupes.length + 1), icon: const Icon(Icons.add), label: const Text('Nouveau groupe'))
            : null,
        body: Defilement(rafraichir: recharger, enfants: [
          const EnTete(titre: 'Groupes de matières', description: 'Ils structurent le bulletin : sous-totaux et moyennes par groupe.'),
          if (groupes.isEmpty) const Carte(enfant: Vide('Aucun groupe')),
          for (final g in groupes.cast<Map>())
            Carte(
              titre: '${g['ordre']}. ${g['nom']}',
              action: Etat.i.estSG
                  ? Row(mainAxisSize: MainAxisSize.min, children: [
                      IconButton(icon: const Icon(Icons.edit_outlined, size: 20), onPressed: () => _formulaire(g, 0)),
                      IconButton(
                        icon: const Icon(Icons.delete_outline, size: 20),
                        onPressed: () async {
                          if (!await confirmer(context, 'Supprimer ce groupe ?', g['nom'] as String, danger: true)) return;
                          if (context.mounted && await agir(context, () => Api.i.delete('/groupes/${g['id']}'), succes: 'Groupe supprimé.')) {
                            setState(() => _version++);
                          }
                        },
                      ),
                    ])
                  : null,
              enfant: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text((g['classes'] as List).map((c) => c['nom']).join(', '), style: TextStyle(color: context.c.encre2)),
                Text('${g['_count']['matieres']} matière(s)', style: TextStyle(color: context.c.encre3, fontSize: 12.5)),
              ]),
            ),
        ]),
      ),
    );
  }
}

// ---------------- Matières ----------------

class EcranMatieres extends StatefulWidget {
  const EcranMatieres({super.key});
  @override
  State<EcranMatieres> createState() => _EcranMatieresState();
}

class _EcranMatieresState extends State<EcranMatieres> {
  String? _classe;
  int _version = 0;

  Future<void> _formulaire(Map? m, String classeId, int suivant) async {
    final groupes = (await Api.i.get('/groupes') as List).cast<Map>().where((g) => (g['classes'] as List).any((c) => c['id'] == classeId)).toList();
    final profs = await _profs();
    if (!mounted) return;
    if (groupes.isEmpty) {
      message(context, "Aucun groupe de matières n'est rattaché à cette classe.", erreur: true);
      return;
    }
    final nom = TextEditingController(text: m?['nom'] as String? ?? '');
    final nomEn = TextEditingController(text: m?['nomEn'] as String? ?? '');
    final coef = TextEditingController(text: '${m?['coefficient'] ?? 1}');
    final ordre = TextEditingController(text: '${m?['ordre'] ?? suivant}');
    var groupe = m?['groupeId'] as String? ?? groupes.first['id'] as String;
    String? prof = m?['professeurId'] as String?;
    final ok = await feuilleFormulaire(
      context,
      m == null ? 'Nouvelle matière' : 'Modifier ${m['nom']}',
      (ctx, maj) => Column(children: [
        _espace(TextField(controller: nom, decoration: const InputDecoration(labelText: 'Nom'))),
        _espace(TextField(controller: nomEn, decoration: const InputDecoration(labelText: 'Nom en anglais'))),
        _espace(Choix<String>(
          libelle: 'Groupe',
          valeur: groupe,
          options: [for (final g in groupes) (g['id'] as String, g['nom'] as String)],
          changer: (v) => maj(() => groupe = v!),
        )),
        _espace(Row(children: [
          Expanded(child: TextField(controller: coef, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Coefficient'))),
          const SizedBox(width: 10),
          Expanded(child: TextField(controller: ordre, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Ordre'))),
        ])),
        Choix<String>(
          libelle: 'Enseignant',
          valeur: prof ?? '',
          options: [('', 'Non attribuée'), for (final p in profs) (p['id'] as String, '${p['nom']} ${p['prenom']}${p['discipline'] != null ? ' (${p['discipline']})' : ''}')],
          changer: (v) => maj(() => prof = v == '' ? null : v),
        ),
      ]),
      () async {
        final corps = {
          'classeId': classeId,
          'groupeId': groupe,
          'nom': nom.text.trim(),
          'nomEn': nomEn.text.trim(),
          'coefficient': int.tryParse(coef.text) ?? 1,
          'ordre': int.tryParse(ordre.text) ?? 1,
          'professeurId': prof,
        };
        m == null ? await Api.i.post('/matieres', corps) : await Api.i.put('/matieres/${m['id']}', corps);
      },
    );
    if (ok) setState(() => _version++);
  }

  Future<void> _supprimer(Map m) async {
    if (!await confirmer(context, 'Supprimer ${m['nom']} ?', 'La matière sera retirée de ${m['classe']['nom']}.', danger: true)) return;
    try {
      await Api.i.delete('/matieres/${m['id']}');
    } on ErreurApi catch (e) {
      if (e.statut != 409 || !mounted) {
        if (mounted) message(context, e.message, erreur: true);
        return;
      }
      if (!await confirmer(context, 'Des notes existent', '${e.message}\nLes notes seront définitivement perdues.', action: 'Tout supprimer', danger: true)) return;
      if (!mounted || !await agir(context, () => Api.i.delete('/matieres/${m['id']}?confirmer=oui'))) return;
    }
    if (mounted) {
      message(context, 'Matière supprimée.');
      setState(() => _version++);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Charge<List<Map<String, dynamic>>>(
      charger: chargerClasses,
      construire: (context, classes, _) {
        if (classes.isEmpty) return const Defilement(enfants: [Carte(enfant: Vide('Aucune classe'))]);
        final classeId = _classe ?? classes.first['id'] as String;
        return Scaffold(
          backgroundColor: Colors.transparent,
          body: Column(children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Choix<String>(
                    libelle: 'Classe',
                    valeur: classeId,
                    options: [for (final c in classes) (c['id'] as String, c['nom'] as String)],
                    changer: (v) => setState(() => _classe = v),
                  ),
                ),
              ),
            ),
            Expanded(
              child: Charge<List>(
                key: ValueKey('$classeId|$_version'),
                charger: () async => await Api.i.get('/matieres?classeId=$classeId') as List,
                construire: (context, matieres, recharger) {
                  final parGroupe = <String, List<Map>>{};
                  for (final m in matieres.cast<Map>()) {
                    parGroupe.putIfAbsent(m['groupe']['nom'] as String, () => []).add(m);
                  }
                  final total = matieres.fold<int>(0, (s, m) => s + (m['coefficient'] as int));
                  return Scaffold(
                    backgroundColor: Colors.transparent,
                    floatingActionButton: Etat.i.estSG
                        ? FloatingActionButton.extended(
                            onPressed: () => _formulaire(null, classeId, matieres.length + 1), icon: const Icon(Icons.add), label: const Text('Nouvelle matière'))
                        : null,
                    body: Defilement(rafraichir: recharger, enfants: [
                      if (matieres.isEmpty) const Carte(enfant: Vide('Aucune matière dans cette classe')),
                      if (matieres.isNotEmpty) Text('  ${matieres.length} matières · total des coefficients : $total', style: TextStyle(color: context.c.encre2)),
                      for (final MapEntry(key: groupe, value: liste) in parGroupe.entries)
                        Carte(
                          titre: '$groupe · coef ${liste.fold<int>(0, (s, m) => s + (m['coefficient'] as int))}',
                          sansMarge: true,
                          enfant: Column(children: [
                            for (final m in liste)
                              ListTile(
                                title: Text('${m['nom']}  (coef ${m['coefficient']})', style: const TextStyle(fontWeight: FontWeight.w500)),
                                subtitle: Text(
                                  m['professeur'] == null ? 'Non attribuée' : '${m['professeur']['prenom']} ${m['professeur']['nom']}',
                                  style: TextStyle(color: m['professeur'] == null ? context.c.alerte : null),
                                ),
                                trailing: Etat.i.estSG
                                    ? PopupMenuButton<String>(
                                        onSelected: (a) => a == 'modifier' ? _formulaire(m, classeId, 0) : _supprimer(m),
                                        itemBuilder: (_) => const [
                                          PopupMenuItem(value: 'modifier', child: Text('Modifier')),
                                          PopupMenuItem(value: 'supprimer', child: Text('Supprimer')),
                                        ],
                                      )
                                    : null,
                              ),
                          ]),
                        ),
                    ]),
                  );
                },
              ),
            ),
          ]),
        );
      },
    );
  }
}

// ---------------- Enseignants ----------------

class EcranEnseignants extends StatefulWidget {
  const EcranEnseignants({super.key});
  @override
  State<EcranEnseignants> createState() => _EcranEnseignantsState();
}

class _EcranEnseignantsState extends State<EcranEnseignants> {
  int _version = 0;

  Future<void> _formulaire(Map? p) async {
    final t = {
      for (final k in ['nom', 'prenom', 'telephone', 'email', 'discipline']) k: TextEditingController(text: p?[k] as String? ?? ''),
    };
    var actif = p?['actif'] as bool? ?? true;
    final carriere = Carriere.de(p);
    final ok = await feuilleFormulaire(
      context,
      p == null ? 'Nouvel enseignant' : 'Modifier ${p['prenom']} ${p['nom']}',
      (ctx, maj) => Column(children: [
        _espace(TextField(controller: t['nom'], textCapitalization: TextCapitalization.characters, decoration: const InputDecoration(labelText: 'Nom'))),
        _espace(TextField(controller: t['prenom'], textCapitalization: TextCapitalization.words, decoration: const InputDecoration(labelText: 'Prénom'))),
        _espace(TextField(controller: t['telephone'], keyboardType: TextInputType.phone, decoration: const InputDecoration(labelText: 'Téléphone (identifiant)'))),
        _espace(TextField(controller: t['email'], keyboardType: TextInputType.emailAddress, decoration: const InputDecoration(labelText: 'E-mail (facultatif)'))),
        _espace(TextField(controller: t['discipline'], decoration: const InputDecoration(labelText: 'Discipline'))),
        if (p != null)
          SwitchListTile(contentPadding: EdgeInsets.zero, title: const Text('Compte actif'), value: actif, onChanged: (v) => maj(() => actif = v)),
        if (p == null)
          Text('Mot de passe provisoire : « password », à changer à la première connexion.', style: TextStyle(fontSize: 12.5, color: ctx.c.encre2)),
        Padding(
          padding: const EdgeInsets.only(top: 16, bottom: 4),
          child: Text('Carrière', style: const TextStyle(fontWeight: FontWeight.w700)),
        ),
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Text("Imprimée sur l'attestation de présence effective au poste.", style: TextStyle(fontSize: 12.5, color: ctx.c.encre2)),
        ),
        ChampsCarriere(carriere, maj: maj),
      ]),
      () async {
        final corps = {
          for (final MapEntry(:key, :value) in t.entries) key: value.text.trim(),
          'actif': actif,
          'carriere': carriere.corps(),
        };
        p == null ? await Api.i.post('/utilisateurs', corps) : await Api.i.put('/utilisateurs/${p['id']}', corps);
      },
    );
    if (ok) setState(() => _version++);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      floatingActionButton: Etat.i.estSG
          ? FloatingActionButton.extended(onPressed: () => _formulaire(null), icon: const Icon(Icons.person_add_alt), label: const Text('Nouvel enseignant'))
          : null,
      body: Charge<List>(
        key: ValueKey(_version),
        charger: () async => await Api.i.get('/utilisateurs?role=PROFESSEUR') as List,
        construire: (context, profs, recharger) => Defilement(rafraichir: recharger, enfants: [
          for (final p in profs.cast<Map>())
            Carte(
              titre: '${p['nom']} ${p['prenom']}',
              action: Etat.i.estSG
                  ? PopupMenuButton<String>(
                      onSelected: (a) async {
                        if (a == 'modifier') return _formulaire(p);
                        if (await confirmer(context, 'Réinitialiser le mot de passe ?', 'Il deviendra « password ».')) {
                          if (context.mounted) {
                            await agir(context, () async {
                              final r = await Api.i.post('/utilisateurs/${p['id']}/reinitialiser');
                              if (context.mounted) message(context, r['message'] as String);
                            });
                          }
                        }
                      },
                      itemBuilder: (_) => const [
                        PopupMenuItem(value: 'modifier', child: Text('Modifier')),
                        PopupMenuItem(value: 'reinitialiser', child: Text('Réinitialiser le mot de passe')),
                      ],
                    )
                  : null,
              enfant: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                if (p['discipline'] != null || p['grade'] != null)
                  Text([p['grade'], p['discipline']].whereType<String>().join(' · '), style: TextStyle(color: context.c.encre2)),
                Text([p['telephone'], p['email']].whereType<String>().join(' · '), style: TextStyle(color: context.c.encre3, fontSize: 12.5)),
                const SizedBox(height: 6),
                for (final m in (p['matieres'] as List).cast<Map>()) Text('${m['nom']} · ${m['classe']['nom']}', style: const TextStyle(fontSize: 13.5)),
                if ((p['matieres'] as List).isEmpty) Text('Aucune matière', style: TextStyle(color: context.c.encre3)),
                const SizedBox(height: 6),
                p['actif'] != true
                    ? const EtatTexte('Désactivé')
                    : p['doitChangerMotDePasse'] == true
                        ? const EtatTexte('Mot de passe provisoire', ton: 'alerte')
                        : const EtatTexte('Actif', ton: 'succes'),
              ]),
            ),
        ]),
      ),
    );
  }
}
