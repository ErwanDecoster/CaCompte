# 01 — Vision produit

## Le problème

Compter les points d'une partie de société se fait aujourd'hui sur un bout de papier ou dans
les Notes de l'iPhone. Trois frictions reviennent :

1. **L'arithmétique** — cumuler des colonnes de chiffres à la main, en fin de soirée, produit
   des erreurs et des disputes. Certains jeux (Tarot, Skyjo, Wizard) ont des formules que
   personne ne retient exactement.
2. **La condition de fin** — « on s'arrête à combien déjà ? », « c'est la dernière manche ou pas ? ».
   Chaque jeu a sa règle, souvent mal appliquée.
3. **La mémoire** — la feuille est jetée. Personne ne sait qui a gagné le plus de parties de
   Skyjo cette année, ni quel a été le pire score de l'histoire du groupe.

## La promesse

> Poser son téléphone au milieu de la table, saisir les scores tour par tour, et n'avoir plus
> jamais à réfléchir ni à additionner. L'app sait quand la partie s'arrête, qui a gagné, et
> raconte ce qui s'est passé.

Trois principes non négociables :

- **Hors-ligne d'abord.** Aucune fonctionnalité de la v1 ne requiert Internet. On joue en
  vacances, dans un chalet, dans un train.
- **Zéro compte.** Pas d'inscription, pas de mot de passe, pas d'email. Les joueurs sont des
  fiches locales, pas des identités.
- **Rapide à la saisie.** Entre deux manches, on a 10 secondes d'attention. Trois taps maximum
  pour enregistrer un tour complet.

## Personas

**Marion, 34 ans — l'organisatrice.** C'est elle qui sort les jeux et qui tient le score. Elle
veut arrêter de faire les additions. Elle crée les fiches joueurs une fois et les réutilise
toute l'année. Utilisation principale : iPhone, posé sur la table, en portrait.

**Le groupe du week-end — 5 personnes, 3 jeux, 2 jours.** Ils enchaînent les parties. Ils
veulent reprendre la même configuration de joueurs d'une partie à l'autre, et voir un
classement cumulé du week-end. Utilisation : iPad posé au centre, mode paysage, tout le monde
regarde.

**Théo, 11 ans — le vérificateur.** Il conteste systématiquement les scores. L'historique
manche par manche et l'écran de statistiques existent en grande partie pour lui.

## Parcours principal

```
Accueil
  └─ « Nouvelle partie »
       ├─ Choix du jeu ............ catalogue, recherche, « récents »
       ├─ Choix des joueurs ....... fiches existantes + « invité » ponctuel
       │                            réorganisation de l'ordre de jeu par glisser-déposer
       ├─ Options de variante ..... seuil de fin, règles optionnelles (pré-remplies)
       └─ « C'est parti »
            │
            ▼
       Partie en cours ─────────────────────────────┐
         · tableau des scores cumulés, leader mis en avant
         · « Manche 3 » → saisie d'une valeur par joueur
         · annulation / correction d'une manche déjà validée
         · l'app annonce elle-même « dernière manche »       │ boucle
         · l'app annonce elle-même la fin ────────────────────┘
            │
            ▼
       Résultats
         · podium animé
         · courbe d'évolution des scores
         · 4 à 6 faits marquants (« Alice : plus gros tour, 40 points »)
         · badges décernés
         · partage d'une image de résumé
            │
            ▼
       Historique (la partie est sauvegardée automatiquement, dès la manche 1)
```

## Périmètre v1

**Inclus**

- Fiches joueurs : pseudo, avatar, couleur ; création, édition, archivage
- Avatars : symbole SF + palette (défaut), emoji, ou photo de la photothèque
- Catalogue de 6 jeux au lancement (voir [05](05-catalogue-jeux.md) pour la priorisation)
- Partie tour par tour : saisie, correction, annulation, détection automatique de la fin
- Sauvegarde automatique et reprise d'une partie interrompue
- Écran de résultats avec statistiques et badges
- Historique des parties, filtrable par jeu et par joueur
- Fiche de profil par joueur : parties jouées, victoires, records
- Synchronisation iCloud entre les appareils du propriétaire
- Partie partagée en direct autour de la table, entre iPhone et Android (Wi-Fi local, secours Bluetooth)
- Français et anglais, Dynamic Type, VoiceOver, mode sombre

**Explicitement hors périmètre v1**

- Multijoueur à distance, comptes utilisateurs, classements en ligne
- Reconnaissance de score par photo / OCR
- Chronomètre de tour, gestion des mises, mode tournoi à plusieurs tables
- Règles complètes des jeux (l'app compte, elle n'arbitre pas et n'explique pas comment jouer)
- Monétisation

## Ce qui ferait échouer le produit

À garder en tête à chaque arbitrage :

- **Une saisie plus lente que le papier.** Si enregistrer une manche prend plus de 15 secondes
  à 5 joueurs, l'app est abandonnée. C'est la métrique produit numéro un.
- **Un score faux.** Une seule erreur de calcul détruit la confiance définitivement. D'où les
  golden files et la spécification partagée.
- **Une partie perdue.** Un crash en milieu de soirée qui efface 40 minutes de scores est
  rédhibitoire. D'où la persistance à chaque manche validée, pas à la fin.
- **Un catalogue trop mince.** Si le jeu qu'on sort ce soir n'est pas dedans, l'app ne s'ouvre
  pas. D'où le mode « jeu libre » générique dès la v1, en filet de sécurité.
