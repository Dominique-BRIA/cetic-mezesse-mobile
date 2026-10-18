// Composants d'interface partagés.
import 'package:flutter/material.dart';

import 'api.dart';
import 'etat.dart';
import 'format.dart';
import 'theme.dart';

/// Page défilante posée sur le motif : chaque bloc est une carte, le motif reste visible entre elles.
class Defilement extends StatelessWidget {
  const Defilement({super.key, required this.enfants, this.rafraichir, this.bas});
  final List<Widget> enfants;
  final Future<void> Function()? rafraichir;
  final Widget? bas;

  @override
  Widget build(BuildContext context) {
    final liste = ListView.separated(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: EdgeInsets.fromLTRB(12, 12, 12, bas == null ? 24 : 96),
      itemCount: enfants.length,
      separatorBuilder: (_, __) => const SizedBox(height: 12),
      itemBuilder: (_, i) => enfants[i],
    );
    return Stack(
      children: [
        rafraichir == null ? liste : RefreshIndicator(onRefresh: rafraichir!, child: liste),
        if (bas != null) Positioned(left: 12, right: 12, bottom: 12, child: bas!),
      ],
    );
  }
}

class Carte extends StatelessWidget {
  const Carte({super.key, this.titre, this.action, required this.enfant, this.sansMarge = false});
  final String? titre;
  final Widget? action;
  final Widget enfant;
  final bool sansMarge;

  @override
  Widget build(BuildContext context) {
    return Card(
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (titre != null || action != null) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 10, 8, 10),
              child: Row(children: [
                Expanded(child: Text(titre ?? '', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14))),
                if (action != null) action!,
              ]),
            ),
            const Divider(),
          ],
          Padding(padding: sansMarge ? EdgeInsets.zero : const EdgeInsets.all(14), child: enfant),
        ],
      ),
    );
  }
}

/// En-tête de page : titre et description, sur une carte.
class EnTete extends StatelessWidget {
  const EnTete({super.key, required this.titre, this.description, this.actions = const []});
  final String titre;
  final String? description;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(titre, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700, letterSpacing: -0.2)),
          if (description != null) ...[
            const SizedBox(height: 4),
            Text(description!, style: TextStyle(color: context.c.encre2, fontSize: 13.5)),
          ],
          if (actions.isNotEmpty) ...[
            const SizedBox(height: 12),
            Wrap(spacing: 8, runSpacing: 8, children: actions),
          ],
        ]),
      ),
    );
  }
}

class Indicateur extends StatelessWidget {
  const Indicateur({super.key, required this.libelle, required this.valeur, this.detail, this.accent = false});
  final String libelle;
  final String valeur;
  final String? detail;
  final bool accent;

  @override
  Widget build(BuildContext context) {
    final p = Theme.of(context).colorScheme.primary;
    return Card(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(color: accent ? p.withValues(alpha: 0.45) : context.c.bord),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(libelle.toUpperCase(), style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w600, letterSpacing: 0.6, color: context.c.encre2)),
          const SizedBox(height: 4),
          Text(valeur,
              style: TextStyle(fontSize: 21, fontWeight: FontWeight.w700, color: accent ? p : null, fontFeatures: const [FontFeature.tabularFigures()])),
          if (detail != null) Text(detail!, style: TextStyle(fontSize: 11.5, color: context.c.encre2)),
        ]),
      ),
    );
  }
}

/// Grille d'indicateurs : deux par ligne.
class GrilleIndicateurs extends StatelessWidget {
  const GrilleIndicateurs({super.key, required this.enfants});
  final List<Widget> enfants;

  @override
  Widget build(BuildContext context) {
    final lignes = <Widget>[];
    for (var i = 0; i < enfants.length; i += 2) {
      lignes.add(IntrinsicHeight(
        child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Expanded(child: enfants[i]),
          const SizedBox(width: 10),
          Expanded(child: i + 1 < enfants.length ? enfants[i + 1] : const SizedBox()),
        ]),
      ));
    }
    return Column(children: [for (var i = 0; i < lignes.length; i++) ...[if (i > 0) const SizedBox(height: 10), lignes[i]]]);
  }
}

/// État en texte, avec un trait de couleur : pas de pastille.
class EtatTexte extends StatelessWidget {
  const EtatTexte(this.texte, {super.key, this.ton = 'neutre'});
  final String texte;
  final String ton;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final couleur = switch (ton) { 'succes' => c.succes, 'danger' => c.danger, 'alerte' => c.alerte, _ => c.encre3 };
    return Container(
      padding: const EdgeInsets.only(left: 6),
      decoration: BoxDecoration(border: Border(left: BorderSide(color: couleur, width: 2))),
      child: Text(texte, style: TextStyle(color: couleur, fontSize: 12, fontWeight: FontWeight.w600)),
    );
  }
}

/// Données en cours de chargement : des blocs gris à la forme d'une liste, qui pulsent doucement.
class Chargement extends StatefulWidget {
  const Chargement({super.key, this.lignes = 6});
  final int lignes;
  @override
  State<Chargement> createState() => _ChargementState();
}

class _ChargementState extends State<Chargement> with SingleTickerProviderStateMixin {
  late final AnimationController _pulsation = AnimationController(vsync: this, duration: const Duration(milliseconds: 700))
    ..repeat(reverse: true);

  @override
  void dispose() {
    _pulsation.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final couleur = context.c.bord.withValues(alpha: 0.8);
    Widget bloc(double hauteur, {double? largeur}) => Container(
          height: hauteur,
          width: largeur,
          decoration: BoxDecoration(color: couleur, borderRadius: BorderRadius.circular(4)),
        );
    // Sans animation si le téléphone demande de réduire les animations.
    final animer = !MediaQuery.of(context).disableAnimations;
    final contenu = Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          bloc(16, largeur: 150),
          const SizedBox(height: 16),
          for (var i = 0; i < widget.lignes; i++) ...[
            if (i > 0) const SizedBox(height: 14),
            Row(children: [
              Expanded(
                flex: 6,
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  FractionallySizedBox(widthFactor: 0.9 - (i % 3) * 0.15, child: bloc(13)),
                  const SizedBox(height: 7),
                  FractionallySizedBox(widthFactor: 0.5, child: bloc(10)),
                ]),
              ),
              const Spacer(flex: 2),
              bloc(13, largeur: 44),
            ]),
          ],
        ]),
      ),
    );
    return Semantics(
      label: 'Chargement',
      liveRegion: true,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: animer ? FadeTransition(opacity: Tween(begin: 1.0, end: 0.5).animate(_pulsation), child: contenu) : contenu,
      ),
    );
  }
}

class MessageErreur extends StatelessWidget {
  const MessageErreur(this.erreur, {super.key, this.reessayer});
  final Object erreur;
  final VoidCallback? reessayer;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8), side: BorderSide(color: c.danger.withValues(alpha: 0.4))),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(children: [
          Icon(Icons.error_outline, color: c.danger, size: 20),
          const SizedBox(width: 10),
          Expanded(child: Text(erreur is ErreurApi ? (erreur as ErreurApi).message : '$erreur', style: TextStyle(color: c.danger))),
          if (reessayer != null) TextButton(onPressed: reessayer, child: const Text('Réessayer')),
        ]),
      ),
    );
  }
}

class Vide extends StatelessWidget {
  const Vide(this.titre, {super.key, this.texte});
  final String titre;
  final String? texte;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 16),
        child: Column(children: [
          Text(titre, textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.w600)),
          if (texte != null) ...[
            const SizedBox(height: 4),
            Text(texte!, textAlign: TextAlign.center, style: TextStyle(color: context.c.encre2, fontSize: 13)),
          ],
        ]),
      );
}

/// Charge une donnée et gère attente, erreur et rafraîchissement.
///
/// Si le téléphone garde une copie des données de l'écran, elle s'affiche aussitôt, avec une fine barre en
/// haut, pendant que la version à jour arrive du serveur. Sinon, un squelette tient la place du contenu.
/// [copieImmediate] est à désactiver pour un écran dont [charger] prépare un formulaire.
class Charge<T> extends StatefulWidget {
  const Charge({super.key, required this.charger, required this.construire, this.copieImmediate = true});
  final Future<T> Function() charger;
  final Widget Function(BuildContext context, T donnees, Future<void> Function() recharger) construire;
  final bool copieImmediate;

  @override
  State<Charge<T>> createState() => _ChargeState<T>();
}

class _ChargeState<T> extends State<Charge<T>> {
  late Future<T> _f;

  /// Dernières données affichées (copie locale ou réponse précédente), montrées pendant une mise à jour.
  T? _affichees;
  bool _aDesDonnees = false;
  int _demande = 0;

  @override
  void initState() {
    super.initState();
    _lancer();
  }

  @override
  void didUpdateWidget(covariant Charge<T> old) {
    super.didUpdateWidget(old);
    if (old.key != widget.key) {
      _aDesDonnees = false;
      _lancer();
    }
  }

  void _lancer() {
    final n = ++_demande;
    _f = widget.charger();
    _f.then((d) {
      if (n == _demande) {
        _affichees = d;
        _aDesDonnees = true;
      }
    }, onError: (_) {});
    if (widget.copieImmediate && !_aDesDonnees) {
      Api.i.copieSeulement(widget.charger).then((d) {
        if (mounted && n == _demande && !_aDesDonnees) {
          setState(() {
            _affichees = d;
            _aDesDonnees = true;
          });
        }
      }, onError: (_) {});
    }
  }

  Future<void> _recharger() async {
    setState(_lancer);
    await _f.then((_) {}, onError: (_) {});
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<T>(
      future: _f,
      builder: (context, s) {
        final enCours = s.connectionState != ConnectionState.done;
        if (enCours && !_aDesDonnees) return const Chargement();
        if (!enCours && s.hasError) {
          return Padding(padding: const EdgeInsets.all(12), child: MessageErreur(s.error!, reessayer: _recharger));
        }
        // Données déjà connues : elles restent à l'écran, la barre signale la mise à jour en cours. La même
        // structure est gardée à l'arrivée des données à jour, pour ne perdre ni le défilement ni la saisie.
        return Stack(fit: StackFit.passthrough, children: [
          widget.construire(context, enCours ? _affichees as T : s.data as T, _recharger),
          if (enCours) const Positioned(top: 0, left: 0, right: 0, child: LinearProgressIndicator(minHeight: 2)),
        ]);
      },
    );
  }
}

/// Liste déroulante simple.
class Choix<T> extends StatelessWidget {
  const Choix({super.key, required this.libelle, required this.valeur, required this.options, required this.changer});
  final String libelle;
  final T? valeur;
  final List<(T, String)> options;
  final ValueChanged<T?> changer;

  @override
  Widget build(BuildContext context) {
    final existe = options.any((o) => o.$1 == valeur);
    return DropdownButtonFormField<T>(
      initialValue: existe ? valeur : null,
      isExpanded: true,
      decoration: InputDecoration(labelText: libelle),
      items: [for (final o in options) DropdownMenuItem(value: o.$1, child: Text(o.$2, overflow: TextOverflow.ellipsis))],
      onChanged: changer,
    );
  }
}

class ChoixPeriode extends StatelessWidget {
  const ChoixPeriode({super.key, required this.valeur, required this.changer});
  final String valeur;
  final ValueChanged<String> changer;

  @override
  Widget build(BuildContext context) => Choix<String>(
        libelle: 'Période',
        valeur: valeur,
        options: [for (final p in periodes) (p.$1, p.$2)],
        changer: (v) => changer(v!),
      );
}

void message(BuildContext context, String texte, {bool erreur = false}) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(
      content: Text(texte),
      backgroundColor: erreur ? context.c.danger : null,
    ));
}

/// Exécute une action et affiche son résultat ou son erreur.
Future<bool> agir(BuildContext context, Future<void> Function() action, {String? succes}) async {
  try {
    await action();
    if (context.mounted && succes != null) message(context, succes);
    return true;
  } catch (e) {
    if (context.mounted) message(context, e is ErreurApi ? e.message : '$e', erreur: true);
    return false;
  }
}

Future<bool> confirmer(BuildContext context, String titre, String texte, {String action = 'Confirmer', bool danger = false}) async {
  final r = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(titre),
      content: Text(texte),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Annuler')),
        FilledButton(
          style: danger ? FilledButton.styleFrom(backgroundColor: ctx.c.danger) : null,
          onPressed: () => Navigator.pop(ctx, true),
          child: Text(action),
        ),
      ],
    ),
  );
  return r == true;
}

/// Ligne « libellé : valeur ».
class LigneInfo extends StatelessWidget {
  const LigneInfo(this.libelle, this.valeur, {super.key, this.gras = false});
  final String libelle;
  final String valeur;
  final bool gras;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 5),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(child: Text(libelle, style: TextStyle(color: context.c.encre2, fontSize: 13.5))),
          const SizedBox(width: 12),
          Flexible(
            child: Text(valeur,
                textAlign: TextAlign.right,
                style: TextStyle(fontWeight: gras ? FontWeight.w700 : FontWeight.w500, fontFeatures: const [FontFeature.tabularFigures()])),
          ),
        ]),
      );
}

Color? couleurNote(BuildContext context, num? v) =>
    v != null && (v * 100).round() / 100 < 10 ? context.c.danger : null;

/// Liste des classes de l'année (partagée par plusieurs écrans).
Future<List<Map<String, dynamic>>> chargerClasses() async =>
    (await Api.i.get('/classes') as List).cast<Map<String, dynamic>>();

bool get peutEcrire => Etat.i.estSG;

/// Mot de passe avec un œil pour l'afficher ou le masquer.
class ChampMotDePasse extends StatefulWidget {
  const ChampMotDePasse({super.key, required this.controleur, required this.libelle, this.aide, this.onChanged});
  final TextEditingController controleur;
  final String libelle;
  final String? aide;
  final ValueChanged<String>? onChanged;

  @override
  State<ChampMotDePasse> createState() => _ChampMotDePasseState();
}

class _ChampMotDePasseState extends State<ChampMotDePasse> {
  bool _voir = false;

  @override
  Widget build(BuildContext context) => TextField(
        controller: widget.controleur,
        obscureText: !_voir,
        onChanged: widget.onChanged,
        decoration: InputDecoration(
          labelText: widget.libelle,
          helperText: widget.aide,
          helperMaxLines: 2,
          suffixIcon: IconButton(
            tooltip: _voir ? 'Masquer le mot de passe' : 'Afficher le mot de passe',
            icon: Icon(_voir ? Icons.visibility_off_outlined : Icons.visibility_outlined),
            onPressed: () => setState(() => _voir = !_voir),
          ),
        ),
      );
}
