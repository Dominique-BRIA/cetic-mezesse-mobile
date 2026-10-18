import 'package:flutter/material.dart';

import '../api.dart';
import '../etat.dart';
import '../format.dart';
import '../motif.dart';
import '../theme.dart';
import '../widgets.dart';
import 'connexion.dart';

// Espace profil : chacun modifie ses propres informations.

class EcranProfil extends StatefulWidget {
  const EcranProfil({super.key});
  @override
  State<EcranProfil> createState() => _EcranProfilState();
}

class _EcranProfilState extends State<EcranProfil> {
  late final Map<String, dynamic> _u = Etat.i.utilisateur!;
  late final _prenom = TextEditingController(text: _u['prenom'] as String? ?? '');
  late final _nom = TextEditingController(text: _u['nom'] as String? ?? '');
  late final _telephone = TextEditingController(text: _u['telephone'] as String? ?? '');
  late final _email = TextEditingController(text: _u['email'] as String? ?? '');
  late final _discipline = TextEditingController(text: _u['discipline'] as String? ?? '');
  final _motDePasse = TextEditingController();
  late String _sexe = _u['sexe'] as String? ?? '';
  bool _envoi = false;
  String? _erreur;

  String _normaliser(String t) => t.replaceAll(RegExp(r'[\s.-]'), '');

  // Le téléphone et l'e-mail servent à se connecter : les changer demande le mot de passe.
  bool get _identifiantChange =>
      _normaliser(_telephone.text) != _normaliser(_u['telephone'] as String? ?? '') ||
      _email.text.trim().toLowerCase() != (_u['email'] as String? ?? '');

  Future<void> _enregistrer() async {
    setState(() {
      _envoi = true;
      _erreur = null;
    });
    try {
      final maj = await Api.i.envoyer('PUT', '/auth/moi', annee: false, corps: {
        'prenom': _prenom.text.trim(),
        'nom': _nom.text.trim(),
        'telephone': _telephone.text.trim(),
        'email': _email.text.trim(),
        'discipline': _discipline.text.trim(),
        if (_sexe.isNotEmpty) 'sexe': _sexe,
        if (_identifiantChange) 'motDePasse': _motDePasse.text,
      }) as Map;
      await Etat.i.majProfil(maj.cast<String, dynamic>());
      if (mounted) {
        message(context, 'Profil enregistré.');
        Navigator.pop(context);
      }
    } on ErreurApi catch (e) {
      setState(() => _erreur = e.message);
    } finally {
      if (mounted) setState(() => _envoi = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final prof = _u['role'] == 'PROFESSEUR';
    return MotifFond(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(title: const Text('Mon profil')),
        body: Defilement(enfants: [
          Text('${libelleRole(_u)} · vos informations, visibles par l\'administration.', style: TextStyle(color: context.c.encre2)),
          const SizedBox(height: 8),
          Carte(
            titre: 'Informations',
            enfant: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              if (_erreur != null) ...[MessageErreur(_erreur!), const SizedBox(height: 12)],
              Choix<String>(
                libelle: 'Civilité',
                valeur: _sexe,
                options: const [('', '—'), ('M', 'M.'), ('F', 'Mme')],
                changer: (v) => setState(() => _sexe = v ?? ''),
              ),
              if (_u['role'] == 'PROVISEUR')
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text('Imprimée sur les documents : « Le Directeur » ou « La Directrice ».',
                      style: TextStyle(fontSize: 12, color: context.c.encre2)),
                ),
              const SizedBox(height: 12),
              TextField(controller: _prenom, textCapitalization: TextCapitalization.words, decoration: const InputDecoration(labelText: 'Prénom')),
              const SizedBox(height: 12),
              TextField(controller: _nom, textCapitalization: TextCapitalization.characters, decoration: const InputDecoration(labelText: 'Nom')),
              const SizedBox(height: 12),
              TextField(
                controller: _telephone,
                keyboardType: TextInputType.phone,
                onChanged: (_) => setState(() {}),
                decoration: const InputDecoration(labelText: 'Téléphone', helperText: "Sert d'identifiant de connexion."),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _email,
                keyboardType: TextInputType.emailAddress,
                onChanged: (_) => setState(() {}),
                decoration: const InputDecoration(labelText: 'E-mail', helperText: 'Facultatif si le téléphone est renseigné.'),
              ),
              if (prof) ...[
                const SizedBox(height: 12),
                TextField(
                  controller: _discipline,
                  decoration: const InputDecoration(labelText: 'Discipline', helperText: 'Ce que vous enseignez, à titre indicatif.'),
                ),
              ],
              if (_identifiantChange) ...[
                const SizedBox(height: 12),
                ChampMotDePasse(
                  controleur: _motDePasse,
                  libelle: 'Mot de passe actuel',
                  aide: "Obligatoire pour changer de téléphone ou d'e-mail.",
                ),
              ],
              const SizedBox(height: 16),
              FilledButton(
                onPressed: _envoi ? null : _enregistrer,
                child: _envoi
                    ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Text('Enregistrer'),
              ),
            ]),
          ),
          Carte(
            titre: 'Sécurité',
            enfant: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Text("Le mot de passe sert sur le web et sur l'application mobile.", style: TextStyle(color: context.c.encre2)),
              const SizedBox(height: 10),
              OutlinedButton.icon(
                icon: const Icon(Icons.key_outlined),
                label: const Text('Changer mon mot de passe'),
                onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const EcranMotDePasse())),
              ),
            ]),
          ),
        ]),
      ),
    );
  }
}
