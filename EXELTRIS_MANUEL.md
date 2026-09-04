# EXELTRIS

### Manuel du joueur

Pour EXELVISION EXL 100 et EXELTEL

---

## Le jeu

Des pièces de quatre cases tombent une à une dans le puits. Vous les
déplacez et les faites pivoter pendant leur chute pour les emboîter.

Dès qu'une ligne du puits est **entièrement remplie**, elle clignote,
disparaît, et tout ce qui se trouvait au-dessus descend d'un cran.

La partie s'arrête quand une nouvelle pièce ne peut plus entrer dans le
puits, faute de place en haut.

---

## Démarrer

1. L'image d'accueil s'affiche et la musique démarre.
2. **ESPACE** passe à l'écran titre.
3. **ESPACE** à nouveau lance la partie.

Sur ces deux écrans, les touches **T**, **O** et **M** sont déjà actives :
vous pouvez choisir votre couleur, régler vos touches et couper la musique
avant même de commencer. Sur l'écran titre, les **flèches gauche et droite**
servent en plus à choisir le niveau de départ (voir plus bas).

---

## Choisir le niveau de départ

Sur l'écran titre, avant d'appuyer sur ESPACE, les flèches **gauche** et
**droite** font varier le niveau de départ affiché sous le titre, de 00 à
19. La partie démarre directement à ce niveau.

Ce choix reste valable pour toutes les parties suivantes tant que la
machine n'est pas éteinte — inutile de le refaire à chaque partie.

---

## Mode démo

Si personne ne touche à rien sur l'écran titre pendant environ cinq
secondes, une partie se lance automatiquement, jouée par la machine.
L'étiquette **Demo** apparaît en haut de l'écran pour le signaler.

Le déroulement ressemble à une vraie partie — score, niveau, lignes
supprimées — mais le placement des pièces n'est pas particulièrement
habile : suffisant pour montrer que le jeu tourne, sans prétendre bien
jouer.

**N'importe quelle touche** arrête la démonstration sur-le-champ et revient
à l'écran titre, prêt pour une vraie partie.

---

## Commandes

| Touche | Effet |
|---|---|
| **Flèche gauche** | déplacer la pièce à gauche |
| **Flèche droite** | déplacer la pièce à droite |
| **Flèche bas** | descente accélérée |
| **ESPACE** | faire pivoter la pièce |
| **Z** | chute immédiate jusqu'en bas |
| **P** | pause |
| **T** | couleur du décor |
| **O** | redéfinir les touches |
| **M** | musique en marche ou à l'arrêt |

Maintenir gauche ou droite fait glisser la pièce en continu. Même chose
avec la flèche bas pour la descente accélérée.

---

## L'écran

À gauche, un bandeau décoratif. Au centre, le puits : dix cases de large,
vingt de haut. À droite, le panneau d'informations.

**Score** — points accumulés.
**Niveau** — de 00 à 19 ; il augmente toutes les dix lignes.
**Lignes** — nombre total de lignes supprimées.
**Suivant** — la pièce qui arrive après celle en cours.

En bas à droite, un rappel permanent des quatre touches de réglage.

---

## Les sept pièces

| Pièce | Forme | Couleur |
|---|---|---|
| I | barre de quatre | cyan |
| O | carré | jaune |
| T | en T | magenta |
| S | en S | vert |
| Z | en Z | rouge |
| J | en J | bleu |
| L | en L | blanc |

Le L est blanc et non orange : la machine ne dispose que de huit couleurs,
et l'orange n'en fait pas partie.

---

## Marquer des points

Le nombre de lignes supprimées **d'un seul coup** change tout :

| Lignes d'un coup | Points |
|---|---|
| 1 | 40 |
| 2 | 100 |
| 3 | 300 |
| 4 | 1200 |

Ces valeurs sont ensuite multipliées par *(niveau + 1)*. Quatre lignes d'un
coup au niveau 5 rapportent donc 7200 points, contre 240 pour quatre lignes
prises une par une au même niveau.

S'ajoutent 1 point par case de descente accélérée et 2 points par case de
chute immédiate.

Chaque niveau accélère la chute. Au niveau 19, une pièce descend d'une case
toutes les cinq images : la partie devient une course.

---

## Redéfinir les touches

Appuyez sur **O**. Les cinq commandes vous sont demandées l'une après
l'autre : *Gauche*, *Droite*, *Descente*, *Rotation*, *Chute*. Frappez la
touche que vous voulez affecter à chacune ; son code s'affiche en
hexadécimal à côté du libellé.

N'importe quelle touche convient, y compris ESPACE et ENTRÉE — à condition
qu'elle ne soit pas déjà affectée à une autre commande de la liste : dans ce
cas, elle est refusée et redemandée. Le réglage prend effet aussitôt, et la
partie reprend là où elle en était.

Les réglages ne sont pas conservés à l'extinction.

---

## Changer la couleur

**T** fait défiler sept teintes pour tout le décor — cadre, texte, panneau
et bandeau : rouge, cyan, vert, jaune, bleu, magenta, blanc.

Les pièces gardent leur couleur propre, pour rester reconnaissables.

---

## La musique

L'air est *Korobeïniki*, une chanson populaire russe des années 1860, dans
le domaine public. Il tourne en boucle pendant toute la partie.

**M** l'arrête et la relance. **P** la suspend avec le jeu.

---

## Conseils

Gardez le puits **plat**. Une surface régulière accepte n'importe quelle
pièce ; un trou profond n'attend que la barre.

Ne visez pas les quatre lignes trop tôt. Une colonne creuse laissée
ouverte en attendant la barre est le meilleur moyen de perdre — surtout aux
niveaux élevés, où vous n'avez plus le temps de réparer.

Servez-vous de **Suivant**. Savoir ce qui arrive change la façon de poser la
pièce en cours.

La **chute immédiate** rapporte deux fois plus que la descente accélérée,
et vous fait gagner un temps précieux aux derniers niveaux.

---

*Exeltris — clone de Tetris en assembleur TMS7020 pour EXL 100.*
