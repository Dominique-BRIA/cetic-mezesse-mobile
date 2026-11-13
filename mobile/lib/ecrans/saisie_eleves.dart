import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../api.dart';
import '../doublons.dart';
import '../format.dart';
import '../theme.dart';
import '../widgets.dart';

// Saisie groupée sur le téléphone : plusieurs élèves, ou les photos de plusieurs élèves,
// enregistrés d'un seul coup (tout ou rien, comme sur le web).

/// Photo prise à l'appareil ou choisie dans la galerie, déjà réduite (600 px).
Future<File?> choisirPhoto(BuildContext context) async {
  final source = await showModalBottomSheet<ImageSource>(
    context: context,
    builder: (ctx) => SafeArea(
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        ListTile(leading: const Icon(Icons.photo_camera_outlined), title: const Text('Prendre une photo'), onTap: () => Navigator.pop(ctx, ImageSource.camera)),
        ListTile(leading: const Icon(Icons.photo_library_outlined), title: const Text('Choisir dans la galerie'), onTap: () => Navigator.pop(ctx, ImageSource.gallery)),
      ]),
    ),
  );
  if (source == null) return null;
  final image = await ImagePicker().pickImage(source: source, maxWidth: 600, maxHeight: 600, imageQuality: 85);
  return image == null ? null : File(image.path);
}

class _Fiche {
  final nom = TextEditingController();
  final prenoms = TextEditingController();
  final lieu = TextEditingController();
  final telephoneParent = TextEditingController();
  String sexe = '';
  DateTime? naissance;
  bool redoublant = false;
  File? photo;

  bool get remplie =>
      nom.text.trim().isNotEmpty || prenoms.text.trim().isNotEmpty || lieu.text.trim().isNotEmpty || sexe.isNotEmpty || naissance != null || photo != null;
  bool get complete => nom.text.trim().isNotEmpty && prenoms.text.trim().isNotEmpty && lieu.text.trim().isNotEmpty && sexe.isNotEmpty && naissance != null;

  Map<String, Object?> versJson() => {
        'nom': nom.text.trim(),
        'prenoms': prenoms.text.trim(),
        'sexe': sexe,
        'dateNaissance':
            '${naissance!.year}-${naissance!.month.toString().padLeft(2, '0')}-${naissance!.day.toString().padLeft(2, '0')}',
        'lieuNaissance': lieu.text.trim(),
        'redoublant': redoublant,
        'parentTelephone': telephoneParent.text.trim().isEmpty ? null : telephoneParent.text.trim(),
      };
}

class EcranAjoutEleves extends StatefulWidget {
  const EcranAjoutEleves({super.key, required this.classes, this.classeParDefaut});
  final List<Map<String, dynamic>> classes;
  final String? classeParDefaut;
  @override
  State<EcranAjoutEleves> createState() => _EcranAjoutElevesState();
}

class _EcranAjoutElevesState extends State<EcranAjoutEleves> {
  final _cle = nouvelleCleEnvoi();
  late String? _classe = widget.classeParDefaut ?? (widget.classes.isEmpty ? null : widget.classes.first['id'] as String);
  final List<_Fiche> _fiches = [_Fiche()];
  bool _verifier = false;
  bool _envoi = false;
  String? _erreur;

  List<_Fiche> get _remplies => _fiches.where((f) => f.remplie).toList();

  Future<void> _enregistrer() async {
    setState(() {
      _verifier = true;
      _erreur = null;
    });
    final remplies = _remplies;
    if (remplies.isEmpty || _classe == null) return;
    if (remplies.any((f) => !f.complete)) {
      setState(() => _erreur = 'Complétez les champs en rouge : rien n’a été enregistré.');
      return;
    }
    setState(() => _envoi = true);
    try {
      final r = await envoyerVerifie(context, (e) => Api.i.envoyerFormulaire('/eleves/lot', entetes: e, champs: {
        'donnees': jsonEncode({'classeId': _classe, 'eleves': [for (final f in remplies) f.versJson()]}),
      }, fichiers: {
        for (final (i, f) in remplies.indexed)
          if (f.photo != null) 'photo_$i': f.photo!,
      }), cle: _cle) as Map;
      if (mounted) {
        message(context, r['message'] as String);
        Navigator.pop(context, true);
      }
    } on Abandon {
      // renoncé après l'avertissement de doublon
    } on ErreurApi catch (e) {
      setState(() => _erreur = e.message);
    } finally {
      if (mounted) setState(() => _envoi = false);
    }
  }

  InputDecoration _champ(String libelle, TextEditingController c) => InputDecoration(
        labelText: libelle,
        isDense: true,
        errorText: _verifier && c.text.trim().isEmpty ? 'obligatoire' : null,
      );

  Widget _carte(int i, _Fiche f) {
    final c = context.c;
    final incomplete = _verifier && f.remplie && !f.complete;
    return Carte(
      titre: 'Élève ${i + 1}',
      action: IconButton(
        tooltip: 'Retirer',
        icon: const Icon(Icons.delete_outline, size: 20),
        onPressed: () => setState(() => _fiches.length > 1 ? _fiches.removeAt(i) : _fiches[0] = _Fiche()),
      ),
      enfant: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          InkWell(
            onTap: () async {
              final photo = await choisirPhoto(context);
              if (photo != null) setState(() => f.photo = photo);
            },
            child: Container(
              width: 72,
              height: 92,
              decoration: BoxDecoration(border: Border.all(color: c.bord), borderRadius: BorderRadius.circular(6), color: c.surface2),
              clipBehavior: Clip.antiAlias,
              child: f.photo != null ? Image.file(f.photo!, fit: BoxFit.cover) : Icon(Icons.add_a_photo_outlined, color: c.encre3),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(children: [
              TextField(controller: f.nom, textCapitalization: TextCapitalization.characters, decoration: _verifier && f.remplie ? _champ('Nom', f.nom) : const InputDecoration(labelText: 'Nom', isDense: true), onChanged: (_) => setState(() {})),
              const SizedBox(height: 8),
              TextField(controller: f.prenoms, textCapitalization: TextCapitalization.words, decoration: _verifier && f.remplie ? _champ('Prénoms', f.prenoms) : const InputDecoration(labelText: 'Prénoms', isDense: true), onChanged: (_) => setState(() {})),
            ]),
          ),
        ]),
        const SizedBox(height: 10),
        Row(children: [
          SegmentedButton<String>(
            segments: const [ButtonSegment(value: 'M', label: Text('M')), ButtonSegment(value: 'F', label: Text('F'))],
            selected: f.sexe.isEmpty ? {} : {f.sexe},
            emptySelectionAllowed: true,
            onSelectionChanged: (s) => setState(() => f.sexe = s.isEmpty ? '' : s.first),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: OutlinedButton.icon(
              icon: const Icon(Icons.event, size: 18),
              label: Text(f.naissance == null ? 'Né(e) le' : date(f.naissance!.toIso8601String())),
              style: OutlinedButton.styleFrom(
                foregroundColor: _verifier && f.remplie && f.naissance == null ? c.danger : null,
                side: _verifier && f.remplie && f.naissance == null ? BorderSide(color: c.danger) : null,
              ),
              onPressed: () async {
                final d = await showDatePicker(context: context, firstDate: DateTime(1995), lastDate: DateTime.now(), initialDate: f.naissance ?? DateTime(2012));
                if (d != null) setState(() => f.naissance = DateTime.utc(d.year, d.month, d.day));
              },
            ),
          ),
        ]),
        if (_verifier && f.remplie && f.sexe.isEmpty)
          Padding(padding: const EdgeInsets.only(top: 4), child: Text('Sexe obligatoire', style: TextStyle(fontSize: 12, color: c.danger))),
        const SizedBox(height: 8),
        TextField(controller: f.lieu, decoration: _verifier && f.remplie ? _champ('Lieu de naissance', f.lieu) : const InputDecoration(labelText: 'Lieu de naissance', isDense: true), onChanged: (_) => setState(() {})),
        const SizedBox(height: 8),
        TextField(controller: f.telephoneParent, keyboardType: TextInputType.phone, decoration: const InputDecoration(labelText: 'Téléphone du parent (facultatif)', isDense: true)),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          dense: true,
          title: const Text('Redoublant'),
          value: f.redoublant,
          onChanged: (v) => setState(() => f.redoublant = v),
        ),
        if (incomplete) Text('Fiche incomplète', style: TextStyle(fontSize: 12, color: c.danger, fontWeight: FontWeight.w600)),
      ]),
    );
  }

  @override
  Widget build(BuildContext context) {
    final nombre = _remplies.length;
    return Scaffold(
      appBar: AppBar(title: const Text('Ajouter des élèves')),
      body: Defilement(
        bas: FilledButton.icon(
          icon: _envoi ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.save_outlined),
          label: Text(nombre == 0 ? 'Remplissez au moins une fiche' : 'Enregistrer $nombre élève(s)'),
          onPressed: nombre == 0 || _envoi ? null : _enregistrer,
        ),
        enfants: [
          Choix<String>(
            libelle: 'Classe',
            valeur: _classe,
            options: [for (final c in widget.classes) (c['id'] as String, c['nom'] as String)],
            changer: (v) => setState(() => _classe = v),
          ),
          const SizedBox(height: 6),
          Text('Une fiche par élève. Tout ou rien : si une fiche est incomplète, rien n’est enregistré. Le matricule est attribué à l’enregistrement.',
              style: TextStyle(fontSize: 12, color: context.c.encre2)),
          const SizedBox(height: 8),
          if (_erreur != null) ...[MessageErreur(_erreur!), const SizedBox(height: 8)],
          for (final (i, f) in _fiches.indexed) _carte(i, f),
          OutlinedButton.icon(
            icon: const Icon(Icons.person_add_alt),
            label: const Text('Ajouter un élève'),
            onPressed: () => setState(() => _fiches.add(_Fiche())),
          ),
        ],
      ),
    );
  }
}

class EcranPhotosClasse extends StatefulWidget {
  const EcranPhotosClasse({super.key, required this.classes, this.classeParDefaut, this.sansPhotoParDefaut = false});
  final List<Map<String, dynamic>> classes;
  final String? classeParDefaut;
  final bool sansPhotoParDefaut;
  @override
  State<EcranPhotosClasse> createState() => _EcranPhotosClasseState();
}

class _EcranPhotosClasseState extends State<EcranPhotosClasse> {
  late String? _classe = widget.classeParDefaut ?? (widget.classes.isEmpty ? null : widget.classes.first['id'] as String);
  late bool _sansPhoto = widget.sansPhotoParDefaut;
  final Map<String, File> _choix = {};
  bool _envoi = false;

  Future<void> _enregistrer() async {
    setState(() => _envoi = true);
    final ok = await agir(context, () async {
      final r = await Api.i.envoyerFormulaire('/eleves/photos', annee: false, fichiers: {
        for (final e in _choix.entries) 'photo_${e.key}': e.value,
      }) as Map;
      if (mounted) message(context, r['message'] as String);
    });
    if (mounted) setState(() => _envoi = false);
    if (ok && mounted) Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Scaffold(
      appBar: AppBar(title: const Text('Photos des élèves')),
      body: _classe == null
          ? const Vide('Aucune classe')
          : Charge<List>(
              key: ValueKey(_classe),
              charger: () async => await Api.i.get('/eleves?classeId=$_classe') as List,
              construire: (context, inscriptions, _) {
                final liste = inscriptions.cast<Map>().map((i) => i['eleve'] as Map).where((e) => !_sansPhoto || e['photoCle'] == null || _choix.containsKey(e['id'])).toList();
                return Defilement(
                  bas: FilledButton.icon(
                    icon: _envoi ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.save_outlined),
                    label: Text(_choix.isEmpty ? 'Touchez un élève pour sa photo' : 'Enregistrer ${_choix.length} photo(s)'),
                    onPressed: _choix.isEmpty || _envoi ? null : _enregistrer,
                  ),
                  enfants: [
                    Choix<String>(
                      libelle: 'Classe',
                      valeur: _classe,
                      options: [for (final cl in widget.classes) (cl['id'] as String, cl['nom'] as String)],
                      changer: (v) => setState(() => _classe = v),
                    ),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Seulement les élèves sans photo'),
                      value: _sansPhoto,
                      onChanged: (v) => setState(() => _sansPhoto = v),
                    ),
                    if (liste.isEmpty)
                      Vide(_sansPhoto ? 'Tous les élèves de cette classe ont une photo' : 'Aucun élève dans cette classe')
                    else
                      GridView.count(
                        crossAxisCount: 3,
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        mainAxisSpacing: 10,
                        crossAxisSpacing: 10,
                        childAspectRatio: 0.62,
                        children: [
                          for (final e in liste)
                            InkWell(
                              onTap: () async {
                                final photo = await choisirPhoto(context);
                                if (photo != null) setState(() => _choix[e['id'] as String] = photo);
                              },
                              onLongPress: () => setState(() => _choix.remove(e['id'])),
                              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                                Expanded(
                                  child: Container(
                                    decoration: BoxDecoration(
                                      color: c.surface2,
                                      borderRadius: BorderRadius.circular(6),
                                      border: Border.all(color: _choix.containsKey(e['id']) ? Theme.of(context).colorScheme.primary : c.bord, width: _choix.containsKey(e['id']) ? 2 : 1),
                                    ),
                                    clipBehavior: Clip.antiAlias,
                                    child: _choix.containsKey(e['id'])
                                        ? Image.file(_choix[e['id']]!, fit: BoxFit.cover)
                                        : e['photoCle'] != null
                                            ? Image.network(Api.i.urlPhoto(e['id'] as String, e['photoCle'] as String?), fit: BoxFit.cover,
                                                errorBuilder: (_, _, _) => Icon(Icons.person_outline, color: c.encre3))
                                            : Icon(Icons.add_a_photo_outlined, color: c.encre3),
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text('${e['nom']} ${e['prenoms']}', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                                Text(_choix.containsKey(e['id']) ? 'nouvelle · appui long pour retirer' : e['matricule'] as String,
                                    maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 10.5, color: c.encre3)),
                              ]),
                            ),
                        ],
                      ),
                  ],
                );
              },
            ),
    );
  }
}
