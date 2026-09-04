# EXELTRIS — journal de développement

Clone de Tetris pour EXELVISION EXL100 / EXELTEL, écrit en assembleur TMS7020.
Testé et validé sur émulateur DCEXEL **et** sur EXL100 et EXELTEL réels.
Source unique : `exeltris.asm` (~4200 lignes), assemblé avec TASM 3.2.

```
tasm -tEXL -a -b exeltris.asm
obj2exl exeltris.obj exeltris.rom -t:ROM -r:0x1000 -p
```

Dépendances : `7020.equ`, `3556.equ`, `mixt_api.asm`, `INTmusic.asm`.

---

## 1. État du projet

Tout fonctionne, sur émulateur et sur machine réelle :

| Domaine | État |
|---|---|
| Puits 10×20 (+1 ligne cachée), 7 tétrominos, rotation Nintendo | complet |
| Sac de sept (piece bag), verrouillage différé | complet |
| Suppression de lignes, score, niveaux, aperçu suivant | complet |
| Niveau de départ réglable (écran titre, flèches) | complet |
| Mode démo automatique (attract mode) | complet |
| Image d'accueil + bandeau gauche (cathédrale + logo) en jeu | complet |
| Musique de fond (Korobeïniki), coupure/reprise | complet |
| Thème de couleur commutable (7 teintes) | complet |
| Police de texte et blocs entièrement redéfinis (BAGC3) | complet |
| Redéfinition des touches, avec contrôle anti-doublon | complet |
| Déploiement ROM cartouche, disquette (EXE/FD), K7, WAV, CRAM | validé de bout en bout |

---

## 2. Chaîne de déploiement (validée intégralement)

Le binaire **n'est pas repositionnable** : les adresses sont figées à l'assemblage
par la directive `.org`, pas recalculées au chargement. Deux builds distincts
sont donc nécessaires selon la destination.

### ROM cartouche / disquette (`.org $1000`)
```
tasm -tEXL -a -b exeltris.asm
obj2exl exeltris.obj exeltris.rom -t:ROM -r:0x1000 -p      ; cartouche
obj2exl exeltris.obj TRIS.BIN     -t:EXE                    ; disquette
dir2fd tris.fd tris/                                        ; image disquette
```
Sur disquette : copier `TRIS.BIN` sur une disquette contenant `EXEC`, puis
`EXEC TRIS` sous ExelDos.

### CRAM (ExelMémoire) / cassette (`.org $8004`)
Recompiler avec l'`.org` changé, puis :
```
tasm -tEXL -a -b exeltris.asm
python3 make_cram.py exeltris.obj exeltris.cram --name EXELTRIS --cram-name TRIS
```
Dans DCEXEL : sauvegarde de la CRAM vers un fichier `.K7`, rechargement
depuis ce K7 (`CALL EXEC(32772)` pour démarrer). Puis conversion cassette :
```
exlk72wav exeltris.k7        ; -> exeltris.wav, 44,1 kHz 8 bits
```
Le WAV rechargé depuis un vrai magnétophone sur EXL100/EXELTEL a démarré
correctement (`CALL EXEC(32772)`).

**Point de vigilance** : le programme fait sa propre initialisation complète
du VDP dès `start:` (`init_vdp`, `trap 13`...), en supposant qu'il est le tout
premier code exécuté après une mise sous tension. Lancé depuis le BASIC via
un loader K7/CRAM, le contexte matériel est différent (VDP déjà configuré) —
dans les faits ça a fonctionné sans adaptation, mais c'est la raison pour
laquelle ce point avait été signalé comme à tester avant de graver quoi que
ce soit.

---

## 3. Plan écran (40 × 25)

```
col  0..12  bandeau gauche : cathedrale (lig 2..10), logo EXELTRIS (lig 16..19)
col    13   colonne separatrice de zone (voir section 5)
col    14   bordure gauche du puits (trait simple, caracteres redefinis)
col 15..24  puits, 10 colonnes
col    25   bordure droite
col 29..38  panneau Score/Niveau/Lignes/Suivant (remonte de 2 lignes)
col 30..38  rappels de touches T/O/P/M

lig     1   bordure haute       lig 2..21  puits       lig 22  bordure basse
lig 23/24   messages centres (Pause, Partie finie, Appuyez sur espace,
            Niveau depart: XX)
```

Le puits interne fait en réalité **21 lignes**, dont une cachée au-dessus du
plateau visible (section 7).

---

## 4. Carte mémoire finale

| Zone | Usage |
|---|---|
| `$1000` ou `$8004` | début du code, selon la cible (section 2) |
| `$C400`–`$C46F` | variables du jeu (état pièce, touches, thème, démo...) |
| `$C600`–`$C6D1` | puits, 210 octets (10×21, ligne cachee incluse) |
| VRAM `$0000` | police ROM copiée par `trap 13` — **non utilisée pour l'affichage** |
| VRAM `$0F00` | BAGC2 : cathédrale (relogée depuis l'image d'accueil) |
| VRAM `$1400` | BAGC3 : **toute** la police de texte, les blocs, le cadre, le logo |
| VRAM `$7340` | page écran |

Numérotation des bancs de générateur, bits 4-3 de l'octet d'attribut,
confirmée par recoupement (exemple concret du manuel Glajean + commentaires
d'Exelnoid) : `$00`=BAGC0, `$08`=BAGC2, `$10`=BAGC1, `$18`=BAGC3. Une valeur
erronée (BAGC1/BAGC2 inversés) a circulé un moment dans cette session — voir
section 5.

---

## 5. Points durs — la police ROM ne fonctionne pas sur cette machine

C'est le fil conducteur le plus coûteux de tout le développement. Résumé
dans l'ordre où les couches se sont révélées :

**Le format d'attribut réel** (section 13.4 du doc projet, confirmé par
Glajean et Exelnoid) :
```
bits 7-5 : couleur d'avant-plan       bits 4-3 : banc de generateur
bits 2-0 : couleur de fond (bancs alphamosaiques uniquement)
```
Une hypothèse initiale erronée (foreground en bits 5-3) rendait certaines
pièces noir sur noir, donc invisibles bien que verrouillées — la cause des
« pièces fantômes » du tout début du projet.

**`trap 13` copie la police ROM en `$0000` (BAGC0), et c'est inexploitable
sur machine réelle.** Testée successivement sur les quatre bancs possibles
(`$00`, `$08`, `$10`, `$18`), toujours le même résultat sur EXL100 et
EXELTEL : barres, texte bruité, ou pavés pleins selon la variante. Sur
l'émulateur, plusieurs de ces essais semblaient fonctionner — ce qui a
prolongé la recherche inutilement. **Conclusion retenue : ne jamais compter
sur la police interne pour du texte sur cette machine.**

**Solution : une police maison, chargée par `trap 19`.** 63 glyphes 5×7
(chiffres, majuscules, minuscules, `:`), chargés dans BAGC3 — le seul banc
dont on a la certitude qu'il s'affiche correctement, puisque blocs, cadre et
logo y vivent déjà avec succès depuis le début. `to_slot` traduit chaque
code ASCII vers son emplacement dans cette police.

**Le code `$00` ET le code `$20` ne doivent jamais porter de dessin réel
dans une table de caractères affichable.** Deux découvertes distinctes,
toutes deux avec le même symptôme (bloc parasite ou barre) et le même
remède :
- `$20` est soit un délimiteur de zone VDP (comportement documenté, mais
  pas toujours celui observé), soit — selon la configuration de `CM2` — un
  simple caractère comme un autre. Dans les deux cas, tout glyphe qui s'y
  trouve peut s'afficher littéralement sur machine réelle.
- `$00` semble être le code utilisé en interne par `cls`/`set_window` pour
  effacer l'écran (« caractère nul »). Un flash bref mais réel de ce
  glyphe apparaissait à chaque effacement d'écran, tant que `$00` portait un
  vrai dessin dans le banc actif.

Remède appliqué partout où c'était nécessaire (logo, cathédrale) : repérer
la ou les cellules utilisant ces codes, fusionner le glyphe avec son voisin
le plus proche visuellement (souvent 1 à 4 pixels d'écart, indiscernable à
l'écran), libérer ainsi un emplacement, y transférer le vrai dessin, et
mettre `$00`/`$20` eux-mêmes à zéro.

**`CM2` (registre de commande du VDP) : la valeur `$E8` activait le
masquage (`DC3`) sans nécessité**, un bit qui n'a de sens que pour le
mécanisme de délimiteur `$20`. Remplacée par `$88` (synchronisation interne
+ `DC5`=1 pour BAGC3 alphamosaïque, tout le reste à zéro), en se basant sur
la Table 3.6 du manuel TMS3556 : `CM2` = `DC1..DC8` du bit 7 au bit 0.

**Double nettoyage d'écran à la transition intro→titre.** `intro_screen` se
terminait par son propre `set_window`+`clear_all`, et `title_draw`, appelé
immédiatement après, refaisait exactement la même chose — deux passages
complets sur les 1000 cellules pour une seule transition, visibles comme un
clignotement sur machine réelle. Supprimé le doublon.

---

## 6. Autres pièges de plateforme rencontrés

- **TASM évalue les expressions de gauche à droite, sans priorité des
  opérateurs.** `FLD_COL+FLD_W*2` vaut `(10+10)*2`, pas ce qu'on attendrait
  avec une priorité normale. Toute expression à deux opérateurs est écrite
  en dur ou décomposée en plusieurs `.equ`.
- **`.equ` ne supporte pas de référence avant.** Une expression comme
  `SUB_SRC .equ SCREEN_DATA+180` échoue si `SCREEN_DATA` est défini plus
  loin dans le fichier ; la même expression passe sans problème comme
  opérande direct d'une instruction (résolue en passe 2).
- **Les branchements conditionnels (`jeq`/`jne`/`jc`/`jnc`) sont limités à
  ±127 octets**, contrairement à `br` qui semble supporter une portée bien
  plus large (utilisé sans souci sur de longues distances, ex. retour à
  l'écran titre depuis la boucle principale). Remède systématique : inverser
  le test et sauter par `br` :
  ```asm
          cmp     %N,A
          jeq     @suite      ; au lieu de jne @loin (hors de portee)
          br      @loin
  suite:
  ```
- **Le générateur de caractères est rangé par PLANS de ligne**, pas
  caractère par caractère : `adresse = base + ligne*128 + slot`. Dix octets
  consécutifs modifient une ligne de dix caractères différents, pas un
  caractère de dix lignes.
- **Port de données VDP = P46, pas P45** (contrôle). Le pointeur d'écriture
  ne s'auto-incrémente pas : à repositionner avant chaque octet.
- **« Aucune touche » vaut `$04` sur certaines configurations, `$00` sur
  d'autres.** Le code de lecture clavier accepte les deux.
- **Une cellule alphamosaïque définit le fond des cellules alphanumériques
  qui suivent sur la même ligne, jusqu'à la prochaine cellule
  alphamosaïque.** D'où la nécessité d'une colonne séparatrice (col. 13)
  entre le bandeau gauche (alphamosaïque) et le reste de l'écran.
- **Polarité des branchements après `cmp`/`cmpa` dans cette base de code :
  `jc` se déclenche quand `A >= opérande`, `jnc` quand `A < opérande`.**
  Établi par déduction croisée sur plusieurs routines existantes (`hexdig`,
  les bornes de collision) et vérifié à plusieurs reprises. Une inversion de
  cette polarité a été la cause de plusieurs bugs de cette session (ligne
  cachée du puits, tests de plage dans le mode démo).
- **Pas de forme `SUB registre,registre` éprouvée dans ce fichier** — seule
  la forme immédiate `SUB %N,A` est utilisée partout. Les soustractions
  entre deux valeurs de registre sont faites par boucle de décomptes
  (`dec`/`inc`/branchements), jamais par complément à deux non vérifié.

---

## 7. Fonctionnalités ajoutées après la version initiale

**Sac de sept (piece bag).** `bag_fill` mélange un tableau de 0 à 6
(Fisher-Yates) avec le LFSR existant ; `bag_next` sert les pièces une à une
et redemande un mélange quand le sac est vide. Remplace un tirage purement
aléatoire qui pouvait faire attendre une pièce donnée quinze tours ou plus.

**Verrouillage différé.** Quand une pièce touche le sol, elle n'est plus
verrouillée immédiatement : un délai (`LOCK_DELAY` = 25 frames, ~0,5 s)
laisse le temps de la glisser ou de la faire pivoter sous une corniche.
Chaque mouvement réussi relance le délai, dans la limite de `LOCK_MAX` = 15
relances pour éviter un verrouillage repoussé indéfiniment. La chute
immédiate (touche Z) verrouille sans délai, comme attendu.

**Ligne cachée au-dessus du puits (`BUF_H`=1, `FLD_H_TOT`=21).** Convention
standard du Tetris moderne : certaines pièces (la barre I à l'apparition)
ne touchent jamais la ligne 0 de leur zone de rotation. Sans ligne tampon
cachée, cette ligne restait structurellement inutilisable et visible du
joueur, raccourcissant le puits d'une ligne. `draw_block` ne dessine jamais
cette ligne (elle n'a pas de position écran), mais la collision, le
verrouillage et la suppression de lignes l'incluent normalement.

**Niveau de départ réglable.** Flèches gauche/droite à l'écran titre pour
choisir de 0 à 19, affiché sous le titre. Le choix reste valable pour toutes
les parties de la session (l'écran titre n'est visité qu'une fois par mise
sous tension ; une fin de partie relance directement `new_game`).

**Mode démo (attract mode).** Après ~5 secondes d'inactivité à l'écran
titre (`IDLE_LIMIT`), une partie démarre automatiquement. `demo_pick`
choisit une rotation et une colonne au hasard pour chaque pièce (en tenant
compte de sa largeur réelle à cette rotation, via `calc_cells`, pour éviter
les tentatives vouées à l'échec) ; `demo_step` rejoue exactement les mêmes
fonctions qu'un joueur (`di_rot`, `try_move`, `di_hard`), au rythme d'une
action toutes les `DEMO_STEP_DELAY` = 8 images pour rester lisible. Un
compteur d'échecs (`DEMO_STUCK_MAX`) force une chute si la cible devient
inatteignable. N'importe quelle touche interrompt immédiatement et revient
à l'écran titre.

**Contrôle anti-doublon des touches.** Dans l'écran de redéfinition, chaque
nouvelle touche capturée est comparée à toutes celles déjà affectées dans
cette session de configuration ; en cas de doublon, elle est refusée et
redemandée.

**Bandeau gauche : cathédrale + logo.** Deux images issues d'exelimage,
recadrées et rechargées par `trap 19` dans des générateurs distincts, avec
gestion des cas `$00`/`$20` décrite en section 5.

---

## 8. Réglages ajustables

| Constante | Valeur | Effet |
|---|---|---|
| `VD_OUTER` | 12 | durée d'une frame (~20 ms) |
| `speed_tbl` | 120…5 | frames par case, par niveau |
| `DAS_DELAY` / `DAS_RATE` | 12 / 9 | répétition gauche-droite |
| `SOFT_DELAY` / `SOFT_RATE` | 10 / 7 | répétition de la descente |
| `KEY_LOCK` | 8 | verrou anti-rebond après une action |
| `LOCK_DELAY` / `LOCK_MAX` | 25 / 15 | verrouillage différé |
| `IDLE_LIMIT` | 250 | délai avant démarrage de la démo (~5 s) |
| `DEMO_STEP_DELAY` | 8 | rythme des actions en démo (~160 ms) |
| `DEMO_STUCK_MAX` | 20 | patience avant chute forcée en démo |

Le générateur aléatoire est un LFSR de Galois 16 bits, polynôme `$002D`,
période 65535. La version 8 bits initiale utilisait une **rotation** au
lieu d'un décalage : période réelle 32, et deux valeurs distinctes
seulement (I et Z) — bug corrigé avant l'introduction du sac de sept.

---

## 9. Reste à faire / pistes ouvertes

- **Accents.** Les libellés sont sans accent : `$E8`, un temps supposé être
  un « è », s'est révélé être un code d'attribut (clignotement). La police
  maison pourrait accueillir deux ou trois glyphes accentués si besoin.
- **Meilleur score, sauvegarde des réglages (touches, thème) en CRAM** —
  faisable, la mécanique CRAM étant maintenant validée de bout en bout pour
  ce projet.
- **IA de démo plus élaborée** — la version actuelle place les pièces au
  hasard (plausible, pas optimal) ; une évaluation de terrain (hauteur,
  trous, irrégularité) donnerait une démo qui joue vraiment bien, au prix
  d'un code sensiblement plus long.
- **Bruitages** — `beep` existe et n'est pas branché sur les événements de
  jeu (rotation, ligne, fin de partie) ; à faire cohabiter avec `INTmusic`
  sans la couper.
- **Vérifier la casse des touches** `T`, `O`, `M`, `P`, `Z` : testées en
  majuscules uniquement. Si le clavier envoie des minuscules touche Verr.
  Maj. relâchée, elles resteront muettes.
