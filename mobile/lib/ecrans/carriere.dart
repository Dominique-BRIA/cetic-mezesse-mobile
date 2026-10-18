import 'package:flutter/material.dart';

import '../format.dart';
import '../theme.dart';
import '../widgets.dart';

/// Carrière d'un personnel, telle qu'imprimée sur l'attestation de présence effective au poste.
class Carriere {
  Carriere.de(Map? u)
    : sexe = u?['sexe'] as String? ?? '',
      matricule = TextEditingController(text: u?['matricule'] as String? ?? ''),
      grade = TextEditingController(text: u?['grade'] as String? ?? ''),
      fonction = TextEditingController(
        text:
            u?['fonction'] as String? ??
            ((u?['discipline'] as String?)?.isNotEmpty == true ? 'Professeur de ${(u!['discipline'] as String).toLowerCase()}' : ''),
      ),
      datePriseService = jour(u?['datePriseService'] as String?),
      dateEntreeFonctionPublique = jour(u?['dateEntreeFonctionPublique'] as String?),
      acteNomination = TextEditingController(text: u?['acteNomination'] as String? ?? '');

  String sexe;
  final TextEditingController matricule;
  final TextEditingController grade;
  final TextEditingController fonction;
  DateTime? datePriseService;
  DateTime? dateEntreeFonctionPublique;
  final TextEditingController acteNomination;

  /// Corps envoyé à l'API : champs vides ramenés à null.
  Map<String, dynamic> corps() {
    String? v(TextEditingController t) => t.text.trim().isEmpty ? null : t.text.trim();
    return {
      'sexe': sexe.isEmpty ? null : sexe,
      'matricule': v(matricule),
      'grade': v(grade),
      'fonction': v(fonction),
      'datePriseService': isoJour(datePriseService),
      'dateEntreeFonctionPublique': isoJour(dateEntreeFonctionPublique),
      'acteNomination': v(acteNomination),
    };
  }

  /// Ce qui manque pour délivrer une attestation.
  List<String> get manquants => [
    if (matricule.text.trim().isEmpty) 'matricule',
    if (grade.text.trim().isEmpty) 'grade',
    if (fonction.text.trim().isEmpty) 'fonction',
    if (datePriseService == null) 'date de prise de service',
  ];
}

const _grades = ['PLEG', 'PCEG', 'PLET', 'PCET', 'PEPS', 'IEG', 'IET', 'CE', 'Vacataire'];

/// Champs de la carrière, à placer dans un formulaire (`maj` redessine le formulaire).
class ChampsCarriere extends StatelessWidget {
  const ChampsCarriere(this.c, {super.key, required this.maj});
  final Carriere c;
  final void Function(VoidCallback) maj;

  @override
  Widget build(BuildContext context) {
    Widget espace(Widget w) => Padding(padding: const EdgeInsets.only(bottom: 12), child: w);
    Widget date(String libelle, DateTime? valeur, ValueChanged<DateTime?> changer) => espace(
      InputDecorator(
        decoration: InputDecoration(
          labelText: libelle,
          suffixIcon: valeur == null
              ? const Icon(Icons.event, size: 20)
              : IconButton(icon: const Icon(Icons.close, size: 18), tooltip: 'Effacer', onPressed: () => maj(() => changer(null))),
        ),
        child: InkWell(
          onTap: () async {
            final d = await showDatePicker(context: context, firstDate: DateTime(1970), lastDate: DateTime.now(), initialDate: valeur ?? DateTime.now());
            if (d != null) maj(() => changer(d));
          },
          child: Text(
            valeur == null ? 'Choisir' : '${valeur.day.toString().padLeft(2, '0')}/${valeur.month.toString().padLeft(2, '0')}/${valeur.year}',
            style: TextStyle(color: valeur == null ? context.c.encre3 : null),
          ),
        ),
      ),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        espace(
          Choix<String>(
            libelle: 'Civilité',
            valeur: c.sexe,
            options: const [('', '—'), ('M', 'M.'), ('F', 'Mme')],
            changer: (v) => maj(() => c.sexe = v ?? ''),
          ),
        ),
        espace(
          TextField(
            controller: c.matricule,
            textCapitalization: TextCapitalization.characters,
            maxLength: 30,
            onChanged: (_) => maj(() {}),
            decoration: const InputDecoration(labelText: 'Matricule (fonction publique)', hintText: '1034573P', counterText: ''),
          ),
        ),
        espace(
          Autocomplete<String>(
            initialValue: c.grade.value,
            optionsBuilder: (v) => _grades.where((g) => g.toLowerCase().startsWith(v.text.toLowerCase())),
            onSelected: (g) => maj(() => c.grade.text = g),
            fieldViewBuilder: (context, controleur, focus, _) => TextField(
              controller: controleur,
              focusNode: focus,
              textCapitalization: TextCapitalization.characters,
              maxLength: 40,
              onChanged: (v) => maj(() => c.grade.text = v),
              decoration: const InputDecoration(labelText: 'Grade / corps', hintText: 'PCEG, PLET…', counterText: ''),
            ),
          ),
        ),
        espace(
          TextField(
            controller: c.fonction,
            maxLength: 120,
            onChanged: (_) => maj(() {}),
            decoration: const InputDecoration(labelText: 'Fonction / spécialité', hintText: 'Professeur de mathématiques', counterText: ''),
          ),
        ),
        date('Prise de service au CETIC', c.datePriseService, (d) => c.datePriseService = d),
        date('Entrée dans la fonction publique', c.dateEntreeFonctionPublique, (d) => c.dateEntreeFonctionPublique = d),
        TextField(
          controller: c.acteNomination,
          maxLength: 200,
          decoration: const InputDecoration(
            labelText: 'Acte de nomination / affectation',
            hintText: 'Décision n° 0123/MINESEC/SG/DRH du 12/08/2020',
            helperText: "Facultatif. Imprimé sur l'attestation s'il est renseigné.",
            counterText: '',
          ),
        ),
      ],
    );
  }
}
