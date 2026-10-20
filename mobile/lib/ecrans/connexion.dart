import 'package:flutter/material.dart';

import '../api.dart';
import '../etat.dart';
import '../motif.dart';
import '../theme.dart';
import '../widgets.dart';

class Marque extends StatelessWidget {
  const Marque({super.key, this.compacte = false});
  final bool compacte;

  @override
  Widget build(BuildContext context) {
    final t = compacte ? 30.0 : 38.0;
    return Row(mainAxisSize: MainAxisSize.min, children: [
      Image.asset('assets/logo.png', width: t + 6, height: t + 6),
      const SizedBox(width: 10),
      Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
        Text('CETIC de Mezesse', style: TextStyle(fontWeight: FontWeight.w700, fontSize: compacte ? 15 : 16.5)),
        if (!compacte) Text('Gestion scolaire', style: TextStyle(fontSize: 12, color: context.c.encre2)),
      ]),
    ]);
  }
}

class EcranConnexion extends StatefulWidget {
  const EcranConnexion({super.key});
  @override
  State<EcranConnexion> createState() => _EcranConnexionState();
}

// Couleurs du drapeau, pour le filet en haut de l'écran (comme sur le web).
const _drapeau = [Color(0xFF007A5E), Color(0xFFCE1126), Color(0xFFFCD116)];

class _EcranConnexionState extends State<EcranConnexion> {
  final _id = TextEditingController();
  final _mdp = TextEditingController();
  bool _voir = false;
  bool _memoriser = true;
  bool _envoi = false;
  String? _erreur;

  Future<void> _connecter() async {
    setState(() {
      _envoi = true;
      _erreur = null;
    });
    try {
      final r = await Api.i.envoyer('POST', '/auth/connexion',
          corps: {'identifiant': _id.text.trim(), 'motDePasse': _mdp.text, 'resterConnecte': _memoriser}, annee: false) as Map;
      await Etat.i.connecter(r['jeton'] as String, (r['utilisateur'] as Map).cast<String, dynamic>(), memoriser: _memoriser);
    } on ErreurApi catch (e) {
      setState(() => _erreur = e.message);
    } finally {
      if (mounted) setState(() => _envoi = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final sombre = Theme.of(context).brightness == Brightness.dark;
    final surface = Theme.of(context).colorScheme.surface;
    final petit = TextStyle(fontSize: 9, height: 1.3, color: c.encre2);
    final gras = petit.copyWith(fontWeight: FontWeight.w700, letterSpacing: 0.4, color: Theme.of(context).colorScheme.onSurface);

    // Pleine page, sans carte : bandes sur toute la largeur, puis le formulaire sur le motif.
    return Scaffold(
      backgroundColor: surface,
      body: SafeArea(
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          SizedBox(
            height: 12,
            child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Expanded(child: ColoredBox(color: _drapeau[0])),
              Expanded(
                child: ColoredBox(color: _drapeau[1], child: Center(child: Icon(Icons.star, size: 10, color: _drapeau[2]))),
              ),
              Expanded(child: ColoredBox(color: _drapeau[2])),
            ]),
          ),
          // En-tête officiel bilingue : français à gauche, anglais à droite.
          Container(
            decoration: BoxDecoration(color: c.surface2, border: Border(bottom: BorderSide(color: c.bord))),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            child: Row(children: [
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('RÉPUBLIQUE DU CAMEROUN', style: gras),
                  Text('Paix – Travail – Patrie', style: petit.copyWith(fontStyle: FontStyle.italic)),
                  Text('MINESEC · DRES-Sud', style: petit),
                  Text('DDES Dja-et-Lobo', style: petit),
                ]),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: Image.asset('assets/logo.png', width: 44, height: 44),
              ),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                  Text('REPUBLIC OF CAMEROON', style: gras, textAlign: TextAlign.right),
                  Text('Peace – Work – Fatherland', style: petit.copyWith(fontStyle: FontStyle.italic), textAlign: TextAlign.right),
                  Text('MINSEC · South RDSE', style: petit, textAlign: TextAlign.right),
                  Text('Dja and Lobo DDSE', style: petit, textAlign: TextAlign.right),
                ]),
              ),
            ]),
          ),
          // Établissement, avec le choix du thème.
          Container(
            decoration: BoxDecoration(color: surface, border: Border(bottom: BorderSide(color: c.bord))),
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              const Text('CETIC DE MEZESSE',
                  textAlign: TextAlign.center, style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700, letterSpacing: 0.5)),
              Text("Collège d'Enseignement Technique Industriel et Commercial",
                  textAlign: TextAlign.center, style: TextStyle(fontSize: 11.5, color: c.encre2)),
              Text('Gestion scolaire et pédagogique',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Theme.of(context).colorScheme.primary)),
            ]),
          ),
          // Formulaire, directement sur le motif.
          Expanded(
            child: Stack(children: [
              Positioned.fill(
                child: MotifFond(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(20, 24, 20, 32),
                    child: Center(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 420),
                        child: AutofillGroup(
                          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                            const Text('Connexion', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700)),
                            const SizedBox(height: 4),
                            Text('Espace réservé aux enseignants et au personnel administratif.', style: TextStyle(color: c.encre2)),
                            const SizedBox(height: 20),
                            if (_erreur != null) ...[MessageErreur(_erreur!), const SizedBox(height: 14)],
                            TextField(
                              controller: _id,
                              keyboardType: TextInputType.emailAddress,
                              autofillHints: const [AutofillHints.username],
                              textInputAction: TextInputAction.next,
                              decoration: const InputDecoration(
                                labelText: 'Téléphone ou e-mail',
                                hintText: 'Ex. : 677 00 00 00',
                                helperText: "Le numéro ou l'adresse enregistré par le Surveillant Général.",
                                helperMaxLines: 2,
                              ),
                            ),
                            const SizedBox(height: 16),
                            TextField(
                              controller: _mdp,
                              obscureText: !_voir,
                              autofillHints: const [AutofillHints.password],
                              onSubmitted: (_) => _connecter(),
                              decoration: InputDecoration(
                                labelText: 'Mot de passe',
                                hintText: 'Votre mot de passe',
                                suffixIcon: IconButton(
                                  tooltip: _voir ? 'Masquer le mot de passe' : 'Afficher le mot de passe',
                                  icon: Icon(_voir ? Icons.visibility_off_outlined : Icons.visibility_outlined),
                                  onPressed: () => setState(() => _voir = !_voir),
                                ),
                              ),
                            ),
                            const SizedBox(height: 6),
                            CheckboxListTile(
                              contentPadding: EdgeInsets.zero,
                              controlAffinity: ListTileControlAffinity.leading,
                              dense: true,
                              value: _memoriser,
                              title: const Text('Rester connecté sur cet appareil'),
                              onChanged: (v) => setState(() => _memoriser = v ?? true),
                            ),
                            const SizedBox(height: 8),
                            FilledButton(
                              style: FilledButton.styleFrom(
                                minimumSize: const Size.fromHeight(46),
                                backgroundColor: sombre ? null : const Color(0xFF16324F),
                              ),
                              onPressed: _envoi ? null : _connecter,
                              child: _envoi
                                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                                  : const Text('Se connecter'),
                            ),
                            const SizedBox(height: 20),
                            Divider(color: c.bord),
                            const SizedBox(height: 8),
                            Text('Mot de passe oublié ? Adressez-vous au Surveillant Général.',
                                textAlign: TextAlign.center, style: TextStyle(fontSize: 12, color: c.encre2)),
                            const SizedBox(height: 10),
                            Text('Version $versionApp', textAlign: TextAlign.center, style: TextStyle(fontSize: 11, color: c.encre3)),
                          ]),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              Positioned(
                right: 12,
                bottom: 12,
                child: IconButton.filledTonal(
                  tooltip: sombre ? 'Passer en mode clair' : 'Passer en mode sombre',
                  icon: Icon(sombre ? Icons.light_mode_outlined : Icons.dark_mode_outlined),
                  onPressed: () => Etat.i.basculerTheme(Theme.of(context).brightness),
                ),
              ),
            ]),
          ),
        ]),
      ),
    );
  }
}

class EcranMotDePasse extends StatefulWidget {
  const EcranMotDePasse({super.key, this.obligatoire = false});
  final bool obligatoire;
  @override
  State<EcranMotDePasse> createState() => _EcranMotDePasseState();
}

class _EcranMotDePasseState extends State<EcranMotDePasse> {
  final _ancien = TextEditingController();
  final _nouveau = TextEditingController();
  final _confirmation = TextEditingController();
  String? _erreur;
  bool _envoi = false;

  Future<void> _enregistrer() async {
    if (_nouveau.text != _confirmation.text) {
      setState(() => _erreur = 'Les deux nouveaux mots de passe ne sont pas identiques.');
      return;
    }
    setState(() {
      _envoi = true;
      _erreur = null;
    });
    try {
      await Api.i.envoyer('POST', '/auth/mot-de-passe', corps: {'ancien': _ancien.text, 'nouveau': _nouveau.text}, annee: false);
      await Etat.i.rafraichirProfil();
      if (mounted) {
        message(context, 'Mot de passe modifié.');
        if (!widget.obligatoire) Navigator.pop(context);
      }
    } on ErreurApi catch (e) {
      setState(() => _erreur = e.message);
    } finally {
      if (mounted) setState(() => _envoi = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final formulaire = Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      if (_erreur != null) ...[MessageErreur(_erreur!), const SizedBox(height: 12)],
      ChampMotDePasse(controleur: _ancien, libelle: 'Mot de passe actuel'),
      const SizedBox(height: 12),
      ChampMotDePasse(controleur: _nouveau, libelle: 'Nouveau mot de passe', aide: '8 caractères au moins', onChanged: (_) => setState(() {})),
      const SizedBox(height: 12),
      ChampMotDePasse(
        controleur: _confirmation,
        libelle: 'Confirmez le nouveau mot de passe',
        aide: _confirmation.text.isNotEmpty && _confirmation.text != _nouveau.text ? 'Les deux mots de passe ne correspondent pas.' : null,
        onChanged: (_) => setState(() {}),
      ),
      const SizedBox(height: 18),
      FilledButton(onPressed: _envoi ? null : _enregistrer, child: const Text('Enregistrer')),
      if (widget.obligatoire) TextButton(onPressed: Etat.i.deconnecter, child: const Text('Se déconnecter')),
    ]);
    return MotifFond(
      child: Scaffold(
        appBar: widget.obligatoire ? null : AppBar(title: const Text('Changer mon mot de passe')),
        body: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  if (widget.obligatoire) ...[
                    const Marque(),
                    const SizedBox(height: 18),
                    const Text('Choisissez votre mot de passe', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
                    const SizedBox(height: 4),
                    Text('Votre compte utilise le mot de passe provisoire. Remplacez-le avant de continuer.',
                        style: TextStyle(color: context.c.encre2)),
                    const SizedBox(height: 16),
                  ],
                  formulaire,
                ]),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
