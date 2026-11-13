import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../api.dart';
import '../doublons.dart';
import '../etat.dart';
import '../format.dart';
import '../theme.dart';
import '../widgets.dart';
import 'saisie_eleves.dart';
import 'verification.dart';

class EcranEleves extends StatefulWidget {
  const EcranEleves({super.key});
  @override
  State<EcranEleves> createState() => _EcranElevesState();
}

class _EcranElevesState extends State<EcranEleves> {
  String _classe = '';
  String _recherche = '';
  int _version = 0;

  @override
  Widget build(BuildContext context) {
    return Charge<List<Map<String, dynamic>>>(
      charger: chargerClasses,
      construire: (context, classes, _) {
        return Scaffold(
          backgroundColor: Colors.transparent,
          floatingActionButton: classes.isEmpty
              ? null
              : FloatingActionButton.extended(
                  onPressed: () async {
                    final ok = await Navigator.push<bool>(
                        context, MaterialPageRoute(builder: (_) => EcranAjoutEleves(classes: classes, classeParDefaut: _classe.isEmpty ? null : _classe)));
                    if (ok == true) setState(() => _version++);
                  },
                  icon: const Icon(Icons.group_add_outlined),
                  label: const Text('Ajouter des élèves'),
                ),
          body: Column(children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(children: [
                    Choix<String>(
                      libelle: 'Classe',
                      valeur: _classe,
                      options: [('', 'Toutes les classes'), for (final c in classes) (c['id'] as String, '${c['nom']} (${c['_count']['inscriptions']})')],
                      changer: (v) => setState(() => _classe = v ?? ''),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      decoration: const InputDecoration(labelText: 'Rechercher', hintText: 'Nom, prénom ou matricule', prefixIcon: Icon(Icons.search)),
                      onSubmitted: (v) => setState(() => _recherche = v.trim()),
                    ),
                    ...[
                      const SizedBox(height: 8),
                      Wrap(spacing: 8, children: [
                        OutlinedButton.icon(
                          icon: const Icon(Icons.photo_camera_outlined, size: 18),
                          label: const Text('Photos'),
                          onPressed: () async {
                            final ok = await Navigator.push<bool>(
                                context, MaterialPageRoute(builder: (_) => EcranPhotosClasse(classes: classes, classeParDefaut: _classe.isEmpty ? null : _classe)));
                            if (ok == true) setState(() => _version++);
                          },
                        ),
                        if (_classe.isNotEmpty) ...[
                          OutlinedButton.icon(
                            icon: const Icon(Icons.picture_as_pdf_outlined, size: 18),
                            label: const Text('Liste PDF'),
                            onPressed: () => agir(context, () => Api.i.ouvrirDocument('/documents/liste?classeId=$_classe&format=pdf')),
                          ),
                          OutlinedButton.icon(
                            icon: const Icon(Icons.table_chart_outlined, size: 18),
                            label: const Text('Excel'),
                            onPressed: () => agir(context, () => Api.i.ouvrirDocument('/documents/liste?classeId=$_classe&format=xlsx')),
                          ),
                        ],
                        if (Etat.i.estSG)
                          OutlinedButton.icon(
                            icon: const Icon(Icons.upload_file, size: 18),
                            label: const Text('Importer'),
                            onPressed: () async {
                              final ok = await importerEleves(context, classes, _classe);
                              if (ok) setState(() => _version++);
                            },
                          ),
                      ]),
                    ],
                  ]),
                ),
              ),
            ),
            Expanded(
              child: Charge<List>(
                key: ValueKey('$_classe|$_recherche|$_version'),
                charger: () async => await Api.i.get('/eleves?classeId=$_classe&q=${Uri.encodeQueryComponent(_recherche)}') as List,
                construire: (context, eleves, recharger) => Defilement(
                  rafraichir: recharger,
                  enfants: [
                    Carte(
                      titre: '${eleves.length} élève(s)',
                      sansMarge: true,
                      enfant: eleves.isEmpty
                          ? const Vide('Aucun élève')
                          : Column(children: [
                              for (final i in eleves.cast<Map>())
                                ListTile(
                                  title: Text('${i['eleve']['nom']} ${i['eleve']['prenoms']}', style: const TextStyle(fontWeight: FontWeight.w500)),
                                  subtitle: Text('${i['eleve']['matricule']} · ${i['classe']['nom']} · ${i['eleve']['sexe']}'),
                                  trailing: const Icon(Icons.chevron_right),
                                  onTap: () async {
                                    await Navigator.push(context, MaterialPageRoute(builder: (_) => FicheEleve(id: i['eleve']['id'] as String)));
                                    setState(() => _version++);
                                  },
                                ),
                            ]),
                    ),
                  ],
                ),
              ),
            ),
          ]),
        );
      },
    );
  }
}

Future<bool> importerEleves(BuildContext context, List<Map<String, dynamic>> classes, String classeParDefaut) async {
  String classe = classeParDefaut.isEmpty ? classes.first['id'] as String : classeParDefaut;
  final ok = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, maj) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            const Text('Importer des élèves', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
            const SizedBox(height: 4),
            Text('Fichier Excel ou CSV, une ligne par élève, dans l\'ordre des colonnes du modèle. Une seule ligne invalide et rien n\'est importé.',
                style: TextStyle(color: ctx.c.encre2)),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              icon: const Icon(Icons.download_outlined),
              label: const Text('Ouvrir le modèle'),
              onPressed: () => agir(ctx, () => Api.i.ouvrirDocument('/eleves/modele-import')),
            ),
            const SizedBox(height: 12),
            Choix<String>(
              libelle: "Classe d'inscription",
              valeur: classe,
              options: [for (final c in classes) (c['id'] as String, c['nom'] as String)],
              changer: (v) => maj(() => classe = v!),
            ),
            const SizedBox(height: 14),
            FilledButton.icon(
              icon: const Icon(Icons.upload_file),
              label: const Text('Choisir le fichier et importer'),
              onPressed: () async {
                final r = await FilePicker.pickFiles(type: FileType.custom, allowedExtensions: ['xlsx', 'csv']);
                final chemin = r.isEmpty ? null : r.single.path;
                if (chemin == null || !ctx.mounted) return;
                final fait = await agir(ctx, () async {
                  final rep = await envoyerVerifie(
                      ctx, (e) => Api.i.televerser('/eleves/import', 'fichier', File(chemin), champs: {'classeId': classe}, entetes: e));
                  if (ctx.mounted) message(ctx, rep['message'] as String);
                });
                if (fait && ctx.mounted) Navigator.pop(ctx, true);
              },
            ),
          ]),
        ),
      ),
    ),
  );
  return ok == true;
}

class FicheEleve extends StatefulWidget {
  const FicheEleve({super.key, required this.id});
  final String id;
  @override
  State<FicheEleve> createState() => _FicheEleveState();
}

class _FicheEleveState extends State<FicheEleve> {
  int _version = 0;
  String _periode = 'S1';

  Future<void> _photo(Map e) async {
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(leading: const Icon(Icons.photo_camera_outlined), title: const Text('Prendre une photo'), onTap: () => Navigator.pop(ctx, ImageSource.camera)),
          ListTile(leading: const Icon(Icons.photo_library_outlined), title: const Text('Choisir dans la galerie'), onTap: () => Navigator.pop(ctx, ImageSource.gallery)),
        ]),
      ),
    );
    if (source == null) return;
    final image = await ImagePicker().pickImage(source: source, maxWidth: 900, imageQuality: 85);
    if (image == null || !mounted) return;
    final ok = await agir(context, () => Api.i.televerser('/eleves/${widget.id}/photo', 'photo', File(image.path)), succes: 'Photo enregistrée.');
    if (ok) setState(() => _version++);
  }

  @override
  Widget build(BuildContext context) {
    final etat = Etat.i;
    return Scaffold(
      appBar: AppBar(title: const Text('Fiche élève')),
      backgroundColor: Theme.of(context).extension<Couleurs>()!.fond,
      body: Charge<List>(
        key: ValueKey(_version),
        charger: () async => [await Api.i.get('/eleves/${widget.id}'), await chargerClasses()],
        construire: (context, d, recharger) {
          final e = d[0] as Map;
          final classes = (d[1] as List).cast<Map<String, dynamic>>();
          final inscriptions = (e['inscriptions'] as List).cast<Map>();
          Map? actuelle;
          for (final i in inscriptions) {
            if (i['anneeId'] == Api.i.anneeId) actuelle = i;
          }
          final c = context.c;
          return Defilement(rafraichir: recharger, enfants: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  GestureDetector(
                    onTap: () => _photo(e),
                    child: Container(
                      width: 84,
                      height: 104,
                      decoration: BoxDecoration(color: c.surface2, borderRadius: BorderRadius.circular(6), border: Border.all(color: c.bord)),
                      clipBehavior: Clip.antiAlias,
                      child: e['photoCle'] == null
                          ? Icon(Icons.add_a_photo_outlined, color: c.encre3)
                          : Image.network(Api.i.urlPhoto(widget.id, e['photoCle'] as String?),
                              fit: BoxFit.cover, errorBuilder: (_, __, ___) => Icon(Icons.person_outline, color: c.encre3)),
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text('${e['nom']} ${e['prenoms']}', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
                      const SizedBox(height: 4),
                      Text('${e['matricule']}', style: TextStyle(color: c.encre2)),
                      if (actuelle != null) ...[
                        Text('${actuelle['classe']['nom']} · ${actuelle['annee']['libelle']}', style: TextStyle(color: c.encre2)),
                        const SizedBox(height: 6),
                        actuelle['statut'] == 'ACTIF' ? const EtatTexte('Inscrit', ton: 'succes') : const EtatTexte('Renvoyé', ton: 'danger'),
                      ],
                    ]),
                  ),
                ]),
              ),
            ),
            if (actuelle != null)
              Wrap(spacing: 8, runSpacing: 8, children: [
                if (etat.estSG)
                  OutlinedButton.icon(
                    icon: const Icon(Icons.edit_outlined, size: 18),
                    label: const Text('Modifier'),
                    onPressed: () async {
                      final ok = await Navigator.push<bool>(
                          context, MaterialPageRoute(builder: (_) => FormEleve(classes: classes, eleve: e, inscription: actuelle)));
                      if (ok == true) setState(() => _version++);
                    },
                  ),
                if (etat.estSG || etat.estProviseur)
                  OutlinedButton.icon(
                    icon: const Icon(Icons.merge_type, size: 18),
                    label: const Text('Fusionner…'),
                    onPressed: () async {
                      if (await fusionnerEleve(context, widget.id, '${e['nom']} ${e['prenoms']}')) setState(() => _version++);
                    },
                  ),
                if (etat.estProviseur && actuelle['statut'] == 'ACTIF')
                  OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(foregroundColor: c.danger),
                    icon: const Icon(Icons.person_remove_outlined, size: 18),
                    label: const Text('Renvoyer'),
                    onPressed: () async {
                      if (await renvoyer(context, actuelle!['id'] as String, '${e['nom']} ${e['prenoms']}')) setState(() => _version++);
                    },
                  ),
                if (etat.estProviseur && actuelle['statut'] == 'RENVOYE')
                  FilledButton.icon(
                    icon: const Icon(Icons.person_add_alt, size: 18),
                    label: const Text('Réintégrer'),
                    onPressed: () async {
                      if (await reintegrer(context, actuelle!['id'] as String, '${e['nom']} ${e['prenoms']}')) setState(() => _version++);
                    },
                  ),
              ]),
            Carte(
              titre: 'Identité',
              enfant: Column(children: [
                LigneInfo('Matricule national', e['matriculeNational'] as String? ?? 'Non renseigné'),
                LigneInfo('Sexe', e['sexe'] == 'F' ? 'Féminin' : 'Masculin'),
                LigneInfo('Né(e) le', '${date(e['dateNaissance'] as String?)} à ${e['lieuNaissance']}'),
                LigneInfo('Parent ou tuteur', e['parentNom'] as String? ?? '—'),
                LigneInfo('Téléphone du parent', e['parentTelephone'] as String? ?? '—'),
                LigneInfo('Adresse du parent', e['parentAdresse'] as String? ?? '—'),
              ]),
            ),
            if (actuelle != null && actuelle['statut'] == 'ACTIF')
              Carte(
                titre: 'Documents',
                enfant: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  ChoixPeriode(valeur: _periode, changer: (v) => setState(() => _periode = v)),
                  const SizedBox(height: 10),
                  FilledButton.icon(
                    icon: const Icon(Icons.picture_as_pdf_outlined),
                    label: const Text('Générer le bulletin'),
                    onPressed: () => agir(
                      context,
                      () => Api.i.ouvrirDocument('/documents/bulletins', methode: 'POST', corps: {
                        'periode': _periode,
                        'inscriptionIds': [actuelle!['id']]
                      }),
                    ),
                  ),
                  const SizedBox(height: 8),
                  // La photo est obligatoire sur la carte scolaire (RG-31).
                  OutlinedButton.icon(
                    icon: const Icon(Icons.credit_card),
                    label: Text(e['photoCle'] == null ? 'Carte scolaire : ajoutez d’abord la photo' : 'Carte scolaire'),
                    onPressed: e['photoCle'] == null
                        ? null
                        : () => agir(
                              context,
                              () => Api.i.ouvrirDocument('/documents/cartes', methode: 'POST', corps: {
                                'inscriptionIds': [actuelle!['id']]
                              }),
                            ),
                  ),
                ]),
              ),
            Carte(
              titre: 'Parcours',
              sansMarge: true,
              enfant: Column(children: [
                for (final i in inscriptions)
                  ListTile(
                    title: Text('${i['annee']['libelle']} · ${i['classe']['nom']}'),
                    subtitle: Text(i['redoublant'] == true ? 'Redoublant' : 'Non redoublant'),
                    trailing: i['statut'] == 'ACTIF' ? const EtatTexte('Inscrit', ton: 'succes') : const EtatTexte('Renvoyé', ton: 'danger'),
                  ),
              ]),
            ),
            for (final i in inscriptions)
              for (final r in (i['renvois'] as List).cast<Map>())
                Carte(
                  titre: 'Renvoyé le ${date(r['date'] as String?)}',
                  enfant: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('Motif : ${r['motif']}'),
                    Text('Par ${r['par']['prenom']} ${r['par']['nom']} (${i['annee']['libelle']})', style: TextStyle(color: c.encre2, fontSize: 12.5)),
                    if (r['reintegreLe'] != null) ...[
                      const SizedBox(height: 6),
                      Text('Réintégré le ${date(r['reintegreLe'] as String?)}${r['motifReintegration'] != null ? ' : ${r['motifReintegration']}' : ''}',
                          style: TextStyle(color: c.succes)),
                    ],
                  ]),
                ),
          ]);
        },
      ),
    );
  }
}

Future<bool> renvoyer(BuildContext context, String inscriptionId, String nomEleve) async {
  final motif = TextEditingController();
  var jour = DateTime.now();
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, maj) => AlertDialog(
        title: Text('Renvoyer $nomEleve'),
        content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          const Text("L'élève sort de la liste principale, des classements et des bulletins. Ses notes sont conservées."),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            icon: const Icon(Icons.event, size: 18),
            label: Text('Date : ${date(jour.toIso8601String())}'),
            onPressed: () async {
              final d = await showDatePicker(context: ctx, firstDate: DateTime(2020), lastDate: DateTime.now().add(const Duration(days: 30)), initialDate: jour);
              if (d != null) maj(() => jour = d);
            },
          ),
          const SizedBox(height: 10),
          TextField(controller: motif, maxLines: 3, maxLength: 500, decoration: const InputDecoration(labelText: 'Motif')),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Annuler')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: ctx.c.danger),
            onPressed: () async {
              if (motif.text.trim().isEmpty) return;
              final fait = await agir(
                ctx,
                () => Api.i.post('/eleves/inscriptions/$inscriptionId/renvoyer',
                    {'motif': motif.text.trim(), 'date': '${jour.year}-${jour.month.toString().padLeft(2, '0')}-${jour.day.toString().padLeft(2, '0')}'}),
                succes: '$nomEleve a été renvoyé(e).',
              );
              if (fait && ctx.mounted) Navigator.pop(ctx, true);
            },
            child: const Text('Confirmer le renvoi'),
          ),
        ],
      ),
    ),
  );
  return ok == true;
}

Future<bool> reintegrer(BuildContext context, String inscriptionId, String nomEleve) async {
  final motif = TextEditingController();
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text('Réintégrer $nomEleve'),
      content: Column(mainAxisSize: MainAxisSize.min, children: [
        const Text("L'élève retrouve sa classe, ses notes et sa place dans les classements."),
        const SizedBox(height: 12),
        TextField(controller: motif, maxLines: 2, decoration: const InputDecoration(labelText: 'Observation (facultative)')),
      ]),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Annuler')),
        FilledButton(
          onPressed: () async {
            final fait = await agir(ctx, () => Api.i.post('/eleves/inscriptions/$inscriptionId/reintegrer', {'motif': motif.text.trim()}),
                succes: '$nomEleve a été réintégré(e).');
            if (fait && ctx.mounted) Navigator.pop(ctx, true);
          },
          child: const Text('Réintégrer'),
        ),
      ],
    ),
  );
  return ok == true;
}

class FormEleve extends StatefulWidget {
  const FormEleve({super.key, required this.classes, this.eleve, this.inscription, this.classeParDefaut});
  final List<Map<String, dynamic>> classes;
  final Map? eleve;
  final Map? inscription;
  final String? classeParDefaut;
  @override
  State<FormEleve> createState() => _FormEleveState();
}

class _FormEleveState extends State<FormEleve> {
  final _cle = nouvelleCleEnvoi();
  late final Map<String, TextEditingController> _t;
  late String _sexe;
  late String _classe;
  late bool _redoublant;
  DateTime? _naissance;
  bool _envoi = false;
  String? _erreur;

  @override
  void initState() {
    super.initState();
    final e = widget.eleve ?? {};
    _t = {
      for (final k in ['nom', 'prenoms', 'lieuNaissance', 'matriculeNational', 'parentNom', 'parentTelephone', 'parentAdresse'])
        k: TextEditingController(text: e[k] as String? ?? ''),
    };
    _sexe = e['sexe'] as String? ?? 'F';
    _classe = widget.inscription?['classeId'] as String? ?? widget.classeParDefaut ?? widget.classes.first['id'] as String;
    _redoublant = widget.inscription?['redoublant'] as bool? ?? false;
    _naissance = e['dateNaissance'] == null ? null : DateTime.parse(e['dateNaissance'] as String);
  }

  Future<void> _enregistrer() async {
    if (_naissance == null) {
      setState(() => _erreur = 'Indiquez la date de naissance.');
      return;
    }
    setState(() {
      _envoi = true;
      _erreur = null;
    });
    final corps = {
      for (final MapEntry(:key, :value) in _t.entries) key: value.text.trim(),
      'sexe': _sexe,
      'classeId': _classe,
      'redoublant': _redoublant,
      'dateNaissance': '${_naissance!.year}-${_naissance!.month.toString().padLeft(2, '0')}-${_naissance!.day.toString().padLeft(2, '0')}',
    };
    try {
      if (widget.eleve == null) {
        final r = await envoyerVerifie(context, (e) => Api.i.envoyer('POST', '/eleves', corps: corps, entetes: e), cle: _cle);
        if (mounted) message(context, 'Élève créé, matricule ${r['matricule']}.');
      } else {
        await envoyerVerifie(context, (e) => Api.i.envoyer('PUT', '/eleves/${widget.eleve!['id']}', corps: corps, entetes: e), cle: _cle);
        if (mounted) message(context, 'Élève modifié.');
      }
      if (mounted) Navigator.pop(context, true);
    } on Abandon {
      // renoncé après l'avertissement de doublon
    } on ErreurApi catch (e) {
      setState(() => _erreur = e.message);
    } finally {
      if (mounted) setState(() => _envoi = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    Widget champ(String cle, String libelle, {TextInputType? clavier, TextCapitalization cap = TextCapitalization.words}) => Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: TextField(controller: _t[cle], keyboardType: clavier, textCapitalization: cap, decoration: InputDecoration(labelText: libelle)),
        );
    return Scaffold(
      appBar: AppBar(title: Text(widget.eleve == null ? 'Nouvel élève' : 'Modifier l\'élève')),
      backgroundColor: context.c.fond,
      body: Defilement(enfants: [
        if (_erreur != null) MessageErreur(_erreur!),
        Carte(
          titre: 'Identité',
          enfant: Column(children: [
            champ('nom', 'Nom', cap: TextCapitalization.characters),
            champ('prenoms', 'Prénoms'),
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: SegmentedButton<String>(
                segments: const [ButtonSegment(value: 'F', label: Text('Féminin')), ButtonSegment(value: 'M', label: Text('Masculin'))],
                selected: {_sexe},
                onSelectionChanged: (s) => setState(() => _sexe = s.first),
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: OutlinedButton.icon(
                icon: const Icon(Icons.cake_outlined, size: 18),
                label: Text(_naissance == null ? 'Date de naissance' : 'Né(e) le ${date(_naissance!.toIso8601String())}'),
                onPressed: () async {
                  final d = await showDatePicker(
                      context: context, firstDate: DateTime(1995), lastDate: DateTime.now(), initialDate: _naissance ?? DateTime(2012));
                  if (d != null) setState(() => _naissance = DateTime.utc(d.year, d.month, d.day));
                },
              ),
            ),
            champ('lieuNaissance', 'Lieu de naissance'),
            champ('matriculeNational', 'Matricule national (cartescolaire.cm)', cap: TextCapitalization.characters),
          ]),
        ),
        Carte(
          titre: 'Scolarité',
          enfant: Column(children: [
            Choix<String>(
              libelle: 'Classe',
              valeur: _classe,
              options: [for (final c in widget.classes) (c['id'] as String, c['nom'] as String)],
              changer: (v) => setState(() => _classe = v!),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Redoublant'),
              value: _redoublant,
              onChanged: (v) => setState(() => _redoublant = v),
            ),
          ]),
        ),
        Carte(
          titre: 'Parent ou tuteur',
          enfant: Column(children: [
            champ('parentNom', 'Nom'),
            champ('parentTelephone', 'Téléphone', clavier: TextInputType.phone),
            champ('parentAdresse', 'Adresse'),
          ]),
        ),
        FilledButton(onPressed: _envoi ? null : _enregistrer, child: const Text('Enregistrer')),
      ]),
    );
  }
}

class EcranRenvoyes extends StatefulWidget {
  const EcranRenvoyes({super.key});
  @override
  State<EcranRenvoyes> createState() => _EcranRenvoyesState();
}

class _EcranRenvoyesState extends State<EcranRenvoyes> {
  int _version = 0;
  @override
  Widget build(BuildContext context) {
    return Charge<List>(
      key: ValueKey(_version),
      charger: () async => await Api.i.get('/eleves?statut=RENVOYE') as List,
      construire: (context, liste, recharger) => Defilement(rafraichir: recharger, enfants: [
        if (liste.isEmpty) const Carte(enfant: Vide('Aucun élève renvoyé cette année')),
        for (final i in liste.cast<Map>())
          Builder(builder: (context) {
            final r = (i['renvois'] as List).isEmpty ? null : (i['renvois'] as List).first as Map;
            final nomEleve = '${i['eleve']['nom']} ${i['eleve']['prenoms']}';
            return Carte(
              titre: nomEleve,
              action: Etat.i.estProviseur
                  ? TextButton(
                      onPressed: () async {
                        if (await reintegrer(context, i['id'] as String, nomEleve)) setState(() => _version++);
                      },
                      child: const Text('Réintégrer'),
                    )
                  : null,
              enfant: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('${i['classe']['nom']} · ${i['eleve']['matricule']}', style: TextStyle(color: context.c.encre2)),
                if (r != null) ...[
                  const SizedBox(height: 6),
                  Text('Renvoyé le ${date(r['date'] as String?)} par ${r['par']['prenom']} ${r['par']['nom']}'),
                  Text('Motif : ${r['motif']}', style: TextStyle(color: context.c.encre2)),
                ],
              ]),
            );
          }),
      ]),
    );
  }
}

class EcranReinscription extends StatefulWidget {
  const EcranReinscription({super.key});
  @override
  State<EcranReinscription> createState() => _EcranReinscriptionState();
}

class _EcranReinscriptionState extends State<EcranReinscription> {
  late final List<Map<String, dynamic>> _precedentes = Etat.i.annees.where((a) => a['id'] != Api.i.anneeId).toList();
  String? _source;
  String? _classeSource;
  String? _cible;
  bool _redoublant = false;
  final Set<String> _choisis = {};
  int _version = 0;

  @override
  Widget build(BuildContext context) {
    if (_precedentes.isEmpty) {
      return const Defilement(enfants: [
        Carte(enfant: Vide("Il n'y a qu'une année scolaire", texte: 'Créez la nouvelle année dans « Années et séquences ».')),
      ]);
    }
    _source ??= _precedentes.first['id'] as String;
    return Charge<List>(
      key: ValueKey('$_source|$_classeSource|$_version'),
      charger: () async => [
        await Api.i.get('/classes?anneeId=$_source'),
        await Api.i.get('/classes'),
        if (_classeSource != null) await Api.i.get('/eleves?anneeId=$_source&classeId=$_classeSource&statut=TOUS') else [],
        await Api.i.get('/eleves?statut=TOUS'),
      ],
      construire: (context, d, _) {
        final classesSource = (d[0] as List).cast<Map>();
        final classesCible = (d[1] as List).cast<Map>();
        final dejaInscrits = (d[3] as List).map((i) => i['eleveId']).toSet();
        final disponibles = (d[2] as List).cast<Map>().where((i) => !dejaInscrits.contains(i['eleveId'])).toList();
        return Defilement(
          bas: FilledButton(
            onPressed: _choisis.isEmpty || _cible == null
                ? null
                : () async {
                    final ok = await agir(context, () async {
                      final r = await Api.i.post('/eleves/reinscrire', {'eleveIds': _choisis.toList(), 'classeId': _cible, 'redoublant': _redoublant});
                      if (context.mounted) message(context, r['message'] as String);
                    });
                    if (ok) {
                      setState(() {
                        _choisis.clear();
                        _version++;
                      });
                    }
                  },
            child: Text('Réinscrire ${_choisis.length} élève(s)'),
          ),
          enfants: [
            Carte(
              titre: '1. Élèves à réinscrire',
              enfant: Column(children: [
                Choix<String>(
                  libelle: "Année d'origine",
                  valeur: _source,
                  options: [for (final a in _precedentes) (a['id'] as String, a['libelle'] as String)],
                  changer: (v) => setState(() {
                    _source = v;
                    _classeSource = null;
                    _choisis.clear();
                  }),
                ),
                const SizedBox(height: 10),
                Choix<String>(
                  libelle: "Classe d'origine",
                  valeur: _classeSource,
                  options: [for (final c in classesSource) (c['id'] as String, c['nom'] as String)],
                  changer: (v) => setState(() {
                    _classeSource = v;
                    _choisis.clear();
                  }),
                ),
              ]),
            ),
            Carte(
              titre: '2. Classe en ${Etat.i.annee?['libelle']}',
              enfant: Column(children: [
                Choix<String>(
                  libelle: "Classe d'accueil",
                  valeur: _cible,
                  options: [for (final c in classesCible) (c['id'] as String, c['nom'] as String)],
                  changer: (v) => setState(() => _cible = v),
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Inscrire comme redoublants'),
                  value: _redoublant,
                  onChanged: (v) => setState(() => _redoublant = v),
                ),
              ]),
            ),
            if (_classeSource != null)
              Carte(
                titre: '${disponibles.length} élève(s) à réinscrire',
                action: disponibles.isEmpty
                    ? null
                    : TextButton(
                        onPressed: () => setState(() => _choisis.length == disponibles.length
                            ? _choisis.clear()
                            : _choisis.addAll(disponibles.map((i) => i['eleveId'] as String))),
                        child: Text(_choisis.length == disponibles.length ? 'Aucun' : 'Tous'),
                      ),
                sansMarge: true,
                enfant: disponibles.isEmpty
                    ? const Vide('Tous sont déjà inscrits cette année')
                    : Column(children: [
                        for (final i in disponibles)
                          CheckboxListTile(
                            value: _choisis.contains(i['eleveId']),
                            onChanged: (v) => setState(() => v == true ? _choisis.add(i['eleveId'] as String) : _choisis.remove(i['eleveId'])),
                            title: Text('${i['eleve']['nom']} ${i['eleve']['prenoms']}'),
                            subtitle: Text('${i['eleve']['matricule']}${i['statut'] == 'RENVOYE' ? ' · renvoyé l\'an passé' : ''}'),
                          ),
                      ]),
              ),
          ],
        );
      },
    );
  }
}
