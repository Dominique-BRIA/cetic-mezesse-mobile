# Règles de gestion

Validées avec le commanditaire le 16/10/2026 ; RG-33 à RG-35 ajoutées le 18/10/2026 ; RG-04 modifiée le 20/10/2026 (sessions prolongées). Le code y renvoie par leur numéro ; le rapport (`rapport-projet.html`, chapitre 3) les reprend.

| N° | Règle |
|---|---|
| RG-01 | Trois rôles : Directeur (chef d'établissement, code `PROVISEUR`), Surveillant Général, Professeur. Le Directeur et le SG sont créés à l'installation (`--amorcer`) ; le SG crée les comptes des professeurs. |
| RG-02 | Connexion par téléphone ou e-mail (au moins l'un des deux, chacun unique) et mot de passe. |
| RG-03 | Un mot de passe créé ou réinitialisé par le SG vaut `password` et doit être changé à la connexion suivante (8 caractères au moins, différent de `password`). |
| RG-04 | Une session prend fin après 12 heures sans utilisation, ou 90 jours avec « Rester connecté » ; chaque utilisation la prolonge. Changer ou réinitialiser le mot de passe ferme les sessions ouvertes sur les autres appareils. Un compte désactivé perd l'accès immédiatement. |
| RG-05 | Une année scolaire compte six séquences, deux par trimestre. Une seule année est active. |
| RG-06 | Une nouvelle année peut reprendre l'organisation d'une autre : groupes, classes, matières, coefficients, professeurs. |
| RG-07 | Une classe appartient à une année ; son nom est unique dans l'année. Une classe sans élève peut être supprimée. |
| RG-08 | Un groupe de matières appartient à une année et peut être rattaché à plusieurs classes. |
| RG-09 | Une matière appartient à une classe et à un groupe rattaché à cette classe ; coefficient entier de 1 à 20 ; au plus un professeur. |
| RG-10 | Supprimer une matière qui a des notes exige une confirmation et efface ses notes ; une matière notée ne change plus de classe. |
| RG-11 | Matricule scolaire généré : préfixe + 2 chiffres de l'année + rang sur 4 chiffres (`CTM26-0007`). Matricule national (cartescolaire.cm) facultatif et unique. |
| RG-12 | Un élève a au plus une inscription par année. Un élève qui a des notes ne change plus de classe dans l'année. |
| RG-13 | Import d'élèves « tout ou rien » : une seule ligne invalide et rien n'est enregistré. |
| RG-14 | Le SG et le Directeur créent les élèves ; seul le SG les modifie. |
| RG-15 | Seul le Directeur renvoie (date et motif obligatoires) et réintègre. Un élève renvoyé sort des listes, calculs, classements et bulletins ; ses notes sont conservées. |
| RG-16 | Une note par élève, matière et séquence, entre 0 et 20, deux décimales au plus. |
| RG-17 | Seul le professeur de la matière saisit ses notes, et seulement si la séquence est ouverte. |
| RG-18 | Le SG ouvre et ferme la saisie séquence par séquence ; une séquence fermée est en lecture seule et peut être rouverte. |
| RG-19 | Le professeur saisit la compétence visée de sa matière pour chaque séquence. |
| RG-20 | Une matière où aucun élève n'a de note sur une séquence est « non évaluée » et retirée du calcul pour tous ; dans une matière évaluée, l'élève sans note a 0. |
| RG-21 | Note de trimestre = moyenne des séquences évaluées du trimestre ; note annuelle = moyenne des trimestres évalués. |
| RG-22 | Moyennes de groupe et générale pondérées par les coefficients des matières évaluées. |
| RG-23 | Rangs sur les valeurs arrondies au centième ; les ex æquo partagent le rang et le suivant est sauté. |
| RG-24 | Grades (matière) et cotes (moyenne générale) suivent des barèmes modifiables par le SG ; borne basse incluse ; un barème commence à 0. |
| RG-25 | Un élève réussit avec une moyenne arrondie de 10 ou plus. |
| RG-26 | Bulletin bilingue, une page A4 par élève ; bloc discipline et emplacement du cachet laissés vides. |
| RG-27 | Le classement général range tous les élèves de l'établissement ensemble. |
| RG-28 | Sur mobile, les notes saisies sans réseau sont gardées puis envoyées automatiquement ; un refus du serveur est signalé et la note n'est pas perdue. |
| RG-29 | Le SG crée les spécialités (« Mécanique »), communes à toutes les années. Le nom d'une classe est calculé : niveau + spécialité + lettre A, B… dans l'ordre de création, la lettre n'apparaissant que si le niveau et la spécialité comptent plusieurs classes dans l'année (« 1re année Mécanique A »). |
| RG-30 | Chaque décision du SG sur l'organisation, la scolarité ou l'administration est consignée et approuvée d'office. Le Directeur, seul à consulter ce journal, peut la désapprouver pendant 4 semaines (motif obligatoire) ; passé ce délai, elle reste approuvée. Désapprouver défait l'action (classe créée supprimée, valeurs précédentes remises, élément supprimé recréé) et c'est définitif ; si l'action ne peut plus être défaite (élèves inscrits, notes saisies depuis), la désapprobation est refusée avec la raison. |
| RG-31 | Carte d'identité scolaire au format ID-1 (85,6 × 54 mm), dix par page A4 avec traits de coupe, pour des classes entières ou des élèves choisis. La photo est obligatoire : la sélection est vérifiée avant l'impression et les élèves sans photo sont écartés. |
| RG-32 | Notifications dans l'application : le SG est prévenu quand le Directeur désapprouve une de ses décisions (motif et action défaite) ; les professeurs actifs qui ont une matière dans l'année sont prévenus quand une séquence est ouverte à la saisie. |
| RG-33 | Le chef d'établissement s'intitule « Directeur », ou « Directrice » si sa civilité est « Mme » ; ce titre s'affiche dans l'application et s'imprime sur les cartes scolaires, les attestations et les certificats. L'en-tête officiel des documents est bilingue : République, ministère, délégations régionale et départementale, arrondissement, sigle et localité (« CETIC DE MEZESSE » / « GTC MEZESSE »), téléphone. |
| RG-34 | Seul le Directeur délivre l'attestation de présence effective au poste, à un personnel (enseignant ou SG ; jamais au Directeur lui-même, dont l'attestation relève de sa hiérarchie) dont la carrière est renseignée : matricule, grade, fonction et date de prise de service obligatoires, acte de nomination facultatif. Chaque attestation reçoit un numéro dans l'année scolaire (« N° 006/2026-2027/CETIC/D ») et garde les informations du jour où elle est délivrée. |
| RG-35 | Un élève figure au tableau d'honneur d'une période quand sa moyenne arrondie au centième atteint la moyenne minimale (12,00 par défaut), réglée par le Directeur ou le SG. Le certificat est bilingue, sans mention d'encouragements ni de félicitations, et signé par le professeur principal et le Directeur. Le bulletin porte la mention « TABLEAU D'HONNEUR / HONOUR ROLL ». |
