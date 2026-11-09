# Application mobile du CETIC de Mezesse

Application Android (Flutter) de gestion scolaire : mêmes écrans que le site, saisie des notes hors connexion.

## Installer

Première installation, et seule installation à faire à la main : télécharger l'APK de la dernière version.

<https://github.com/Dominique-BRIA/cetic-mezesse-mobile/releases/latest/download/cetic-mezesse.apk>

Android demande d'autoriser l'installation depuis le navigateur. Ensuite, l'application se met à jour d'elle-même.

## Mises à jour

Deux mécanismes, tous deux pilotés par le workflow **APK Android** (`.github/workflows/apk.yml`) à chaque push dans `mobile/` sur `main` :

| Changement | Ce qu'il faut faire | Ce que voit l'utilisateur |
| --- | --- | --- |
| Code Dart seulement (écrans, règles, textes) | Rien : pousser suffit, **une fois Shorebird activé** | Rien. Le correctif est téléchargé au lancement et appliqué au lancement suivant ; s'il arrive pendant l'utilisation, un bandeau propose de rouvrir l'application. |
| Plugin, autorisation Android, logo, version de Flutter, ou Shorebird pas encore activé | Augmenter `version` dans `pubspec.yaml` (`1.1.0+2` → `1.1.1+3`) : le numéro après `+` doit toujours augmenter | Rien : l'APK se télécharge d'elle-même, même application fermée (tâche de fond toutes les 6 heures environ), et s'installe aussitôt, ou quand l'utilisateur quitte l'application s'il s'en sert, sans confirmation sur Android 12 et plus quand Android l'accepte, sinon par l'écran « Mettre à jour » d'Android (un appui). |

Le workflow décide seul :

- la version de `pubspec.yaml` n'a pas encore de Release GitHub : il construit l'APK et publie la Release `v<version>` avec `cetic-mezesse.apk` et `version.json` ;
- elle a une Release construite avec Shorebird (fichier `shorebird.txt` joint) : il publie un correctif Shorebird de cette version ;
- sinon : il construit une APK de contrôle, en artefact, sans rien distribuer.

`mise-a-jour.json` règle la prochaine Release :

- `notes` : le texte affiché dans le bandeau (à défaut, le titre du commit) ;
- `minimum` : numéro de version (le nombre après `+`) en dessous duquel l'application refuse de servir et impose la mise à jour. À utiliser quand l'API change d'une façon que les anciennes versions ne savent pas gérer.

L'application vérifie `version.json` au démarrage puis toutes les 6 heures ; le menu propose aussi « Rechercher une mise à jour ». Une version construite en local (`flutter run`) a le numéro 0 et ne propose jamais de mise à jour.

**La clé de signature ne doit jamais changer** (secrets `ANDROID_KEYSTORE_*`, copie dans `D:\Cles`) : Android refuse d'installer par-dessus une APK signée avec une autre clé, et il faudrait désinstaller, ce qui efface les notes en attente.

## Console technique

L'application signale sa version à chaque ouverture et remonte ses plantages, y compris ceux du tout début du lancement (`CapturePlantages.kt`). Avant de télécharger ou d'installer une APK, elle lit la politique réglée depuis la console ([cetic-mezesse-console](../../cetic-mezesse-console)) : suspension, version bloquée, version minimale. Si le serveur ne répond pas, rien n'est téléchargé. **L'API doit donc être déployée avant cette version de l'application.**

## Activer Shorebird

Rien à installer sur le poste : l'outil Shorebird (près de 3 Go) s'installe sur la machine de GitHub, à chaque run du workflow. Une seule fois, après la création du compte sur <https://console.shorebird.dev> :

1. Dans la console Shorebird : Settings de l'organisation → Service accounts → créer un compte (rôle Developer) → Create key. Copier la clé dans GitHub : dépôt `cetic-mezesse-mobile` → Settings → Secrets and variables → Actions → New repository secret **`SHOREBIRD_TOKEN`**. (Les jetons de `shorebird login:ci` ne fonctionnent plus depuis le 1er octobre 2026.)
2. Pousser sur `main` une version de `pubspec.yaml` pas encore publiée. Le workflow lance `shorebird init` (application « CETIC Mezesse »), commite `mobile/shorebird.yaml` sur `main`, puis publie la première APK Shorebird. Les téléphones l'installent par le bandeau ; à partir de là, les pushs sans changement de version deviennent des correctifs.

Si l'initialisation échoue (rôle insuffisant : passer le compte de service en Admin ; plusieurs organisations : variable `SHOREBIRD_ORG_ID`), le workflow le signale et publie une APK classique. Ne pas relancer d'initialisation une fois `shorebird.yaml` créé chez Shorebird : elle créerait une seconde application. Garder `auto_update: true` et ne pas ajouter `patch_verification: install_only`.

Pour travailler avec Shorebird en local (facultatif, environ 2,2 Go, 3 Go libres exigés) : `git clone -b stable https://github.com/shorebirdtech/shorebird.git D:\Dev\shorebird`, ajouter `D:\Dev\shorebird\bin` au Path, puis `shorebird doctor`. Le script officiel installe sur C:, trop plein sur ce poste.

L'offre gratuite de Shorebird (Hobby) couvre 5 000 installations de correctifs par mois ; au-delà, les correctifs sont refusés jusqu'au mois suivant, et l'application continue de fonctionner avec la version installée. Les releases Shorebird sont construites avec Flutter 3.44.9 (`FLUTTER_SHOREBIRD` dans le workflow).

## Développer

```bash
flutter pub get
flutter run --dart-define=API_URL=http://10.0.2.2:4000/api   # émulateur Android, API locale
flutter test
```
