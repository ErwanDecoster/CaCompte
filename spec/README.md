# `spec/` — Spécification partagée

**Source de vérité inter-plateformes.** Ce dossier ne contient que du JSON. Ni Swift, ni
Kotlin, ni aucun code exécutable.

Les deux implémentations — Apple et Android — lisent ces fichiers et rejouent ces parties.
C'est le seul mécanisme qui garantit qu'un score calculé sur iPhone est identique à celui
calculé sur un Pixel, sans partager une ligne de code.

```
spec/
├── schema/game-definition.schema.json   contrat de format (JSON Schema 2020-12)
├── games/*.json                         définitions déclaratives des jeux
└── golden/*.json                        parties complètes + résultats attendus
```

## Règle d'or

> **Une modification de règle commence toujours ici, jamais dans le code.**

L'ordre est strict :

1. Modifier ou créer `games/<id>.json`, valider contre le schéma.
2. Écrire ou mettre à jour les `golden/<id>-*.json`.
3. Faire passer les tests Swift.
4. Faire passer les tests Kotlin.

Écrire le golden avant l'implémentation n'est pas un rituel de TDD : c'est ce qui permet à la
seconde plateforme d'être écrite **sans lire le code de la première**.

## Versionnage

Deux axes indépendants, à ne pas confondre :

| Champ | Porte sur | Change quand |
|---|---|---|
| `specVersion` | le **format** de `GameDefinition` | on ajoute ou modifie un champ du schéma |
| `rulesVersion` | les **règles d'un jeu** | un calcul de score change, pour quelque raison que ce soit |

Incrémenter `rulesVersion` est **obligatoire** dès qu'un résultat peut changer, même pour une
correction de bug. Chaque partie enregistrée mémorise la version avec laquelle elle a été
jouée, et les anciens moteurs sont conservés indéfiniment (`SkyjoRulesV1` reste après l'arrivée
de `SkyjoRulesV2`). Un score affiché ne change jamais rétroactivement.

Les golden files déclarent la version qu'ils testent : les anciens restent en place et
continuent de tourner.

## Synchronisation avec le code

Les définitions sont embarquées dans les applications, jamais téléchargées — l'app fonctionne
hors ligne. Côté Apple, un script de build copie `games/` vers
`CaCompteKit/Sources/Catalog/GameDefinitions/` et **échoue si les deux diffèrent**. `spec/` est
la source ; la copie n'est jamais éditée à la main. (Le dossier ne s'appelle délibérément pas
`Resources` : un dossier de ce nom copié tel quel dans un bundle fait planter `codesign` sur
certaines versions de macOS/Xcode — voir README « Correctif post-Phase 6 ».)

## Jeux en attente de leur moteur

`games/.pending/` contient des définitions écrites en avance mais dont le moteur n'est pas
encore implémenté (ex. `yams.json`, prévu [Phase 7](../docs/12-roadmap.md)). Volontairement en
dehors de `games/*.json` pour ne pas casser le test d'exhaustivité du catalogue (« toute règle
référencée existe »). À déplacer dans `games/` seulement en même temps que ses golden files et
son moteur, jamais avant.

## Ajouter un jeu

1. `games/<id>.json` — valider contre le schéma
2. Au moins **deux** golden files : une partie nominale, et le cas limite qui fait la
   particularité du jeu
3. Si `engine` ≠ `generic.sum.v1`, implémenter `GameRules` jusqu'à ce que les golden passent
4. Enregistrer l'`engineID` dans la table du catalogue (un test vérifie l'exhaustivité)
5. Traduire les libellés dans les catalogues de chaînes de chaque plateforme

## Format d'un golden file

```jsonc
{
  "goldenId": "…",           // identifiant unique, sert de nom de cas de test
  "gameId": "skyjo",
  "rulesVersion": 1,
  "variants": { … },         // options de partie
  "participants": [ … ],     // identifiants stables, noms lisibles
  "rounds": [ … ],           // saisies brutes, dans l'ordre
  "expected": {
    "roundResults": [ … ],   // après CHAQUE manche : scores calculés, cumuls, statut
    "final": { … },          // raison de fin, classement
    "insights": [ … ]        // statistiques notables (sous-ensemble vérifié)
  }
}
```

Vérifier l'état **après chaque manche**, et pas seulement à la fin, est délibéré : une erreur
de calcul qui se compense entre deux manches passerait sinon inaperçue.

Les `insights` attendus sont un **sous-ensemble** : le test vérifie que ceux listés sont
présents et exacts, sans exiger l'exhaustivité. Les statistiques évoluent plus vite que les
règles, et un golden ne doit pas casser parce qu'un nouvel indicateur a été ajouté.
