import 'package:flutter/material.dart';

import '../api.dart';
import '../format.dart';
import '../theme.dart';
import '../widgets.dart';
import 'carriere.dart';
import 'organisation.dart';

// Attestations de présence effective au poste : le Directeur les délivre et en garde le registre.

class EcranAttestations extends StatefulWidget {
  const EcranAttestations({super.key});
  @override
  State<EcranAttestations> createState() => _EcranAttestationsState();
}

class _EcranAttestationsState extends State<EcranAttestations> {
  int _version = 0;

  Future<void> _imprimer(Map a) => agir(context, () => Api.i.ouvrirDocument('/attestations/${a['id']}/pdf'));

  Future<void> _nouvelle() async {
    List<Map> personnels = [];
    if (!await agir(context, () async {
      personnels = (await Api.i.get('/utilisateurs') as List).cast<Map>().where((u) => u['role'] != 'PROVISEUR' && u['actif'] == true).toList()
        ..sort((x, y) => '${x['nom']} ${x['prenom']}'.compareTo('${y['nom']} ${y['prenom']}'));
    })) {
      return;
    }
    if (!mounted) return;
    String? id;
    var carriere = Carriere.de(null);
    Map? delivree;
    final ok = await feuilleFormulaire(
      context,
      'Nouvelle attestation de présence effective au poste',
      (ctx, maj) {
        final reste = carriere.manquants;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Choix<String>(
              libelle: 'Personnel',
              valeur: id,
              options: [
                for (final u in personnels)
                  (
                    u['id'] as String,
                    '${u['nom']} ${u['prenom']}${u['role'] == 'SURVEILLANT_GENERAL'
                        ? ' (Surveillant Général)'
                        : u['discipline'] != null
                        ? ' (${u['discipline']})'
                        : ''}',
                  ),
              ],
              changer: (v) => maj(() {
                id = v;
                carriere = Carriere.de(personnels.firstWhere((u) => u['id'] == v));
              }),
            ),
            if (id != null) ...[
              const SizedBox(height: 14),
              // La clé recrée les champs quand on change de personnel.
              ChampsCarriere(carriere, key: ValueKey(id), maj: maj),
              const SizedBox(height: 10),
              Text(
                reste.isNotEmpty
                    ? 'À compléter avant de délivrer : ${reste.join(', ')}.'
                    : "Ces informations sont enregistrées sur le compte, puis imprimées sur l'attestation, qui reçoit le numéro suivant du registre.",
                style: TextStyle(fontSize: 13, color: reste.isNotEmpty ? ctx.c.alerte : ctx.c.encre2),
              ),
            ],
          ],
        );
      },
      () async {
        if (id == null) throw ErreurApi(0, 'Choisissez un personnel.');
        final reste = carriere.manquants;
        if (reste.isNotEmpty) throw ErreurApi(0, 'À compléter : ${reste.join(', ')}.');
        // La carrière complétée est enregistrée sur le compte, puis l'attestation est délivrée.
        await Api.i.envoyer('PUT', '/utilisateurs/$id/carriere', corps: carriere.corps(), annee: false);
        delivree = await Api.i.envoyer('POST', '/attestations', corps: {'utilisateurId': id}, annee: false) as Map;
      },
      action: "Délivrer l'attestation",
    );
    if (!ok || !mounted) return;
    setState(() => _version++);
    final a = delivree!;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text('Attestation ${a['reference']} délivrée à ${a['beneficiaire']}.'),
          duration: const Duration(seconds: 15),
          action: SnackBarAction(label: 'Imprimer', onPressed: () => _imprimer(a)),
        ),
      );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      floatingActionButton: FloatingActionButton.extended(onPressed: _nouvelle, icon: const Icon(Icons.add), label: const Text('Nouvelle attestation')),
      body: Charge<List>(
        key: ValueKey(_version),
        charger: () async => await Api.i.get('/attestations', annee: false) as List,
        construire: (context, liste, recharger) {
          final c = context.c;
          return Defilement(
            rafraichir: recharger,
            bas: const SizedBox(height: 56),
            enfants: [
              Text(
                "Attestations de présence effective au poste délivrées aux personnels. Chacune reçoit un numéro dans l'année scolaire et reste au registre.",
                style: TextStyle(color: c.encre2, fontSize: 13),
              ),
              Carte(
                titre: 'Registre · ${liste.length} attestation(s)',
                sansMarge: true,
                enfant: liste.isEmpty
                    ? const Vide('Aucune attestation délivrée', texte: 'Touchez « Nouvelle attestation » pour en délivrer une.')
                    : Column(
                        children: [
                          for (final a in liste.cast<Map>())
                            ListTile(
                              title: Text(a['beneficiaire'] as String, style: const TextStyle(fontWeight: FontWeight.w600)),
                              subtitle: Text('${a['reference']}\n${a['grade']} · ${a['fonction']} · le ${date(a['delivreeLe'] as String?)}'),
                              isThreeLine: true,
                              trailing: IconButton(icon: const Icon(Icons.print_outlined), tooltip: "Imprimer l'attestation", onPressed: () => _imprimer(a)),
                            ),
                        ],
                      ),
              ),
            ],
          );
        },
      ),
    );
  }
}
