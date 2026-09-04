; ============================================================================
; EXELTRIS  -  Tetris pour EXELVISION EXL100 / EXELTEL
; ============================================================================
; Target : TMS7020 + TMS3556 VDP
; Mode   : texte 40x25, blocs en caracteres REDEFINIS (generateur semi-graph.)
; API    : mixt_api.asm (Jester DevKit)
; Assembleur : TASM 3.2
;
;   tasm -tEXL -a -b exeltris.asm exeltris.obj
;   obj2exl.exe exeltris.obj exeltris.rom -t:ROM -r:0x1000 -p
;
; Version CRAM/K7 : remplacer .org $1000 par .org $8000
;
; ---------------------------------------------------------------------------
; v2 : 14 caracteres redefinis (2 par tetromino), motifs distincts par piece
;      rotation avec wall-kick simple, mise en page corrigee
; ---------------------------------------------------------------------------
;
; PLAN ECRAN (40 x 25)
;   col  0.. 8 : aide clavier          (9 colonnes utiles)
;   col  9     : bordure gauche
;   col 10..29 : puits, 10 cases de 2 cellules
;   col 30     : bordure droite
;   col 31     : separation
;   col 32..39 : panneau score / niveau / lignes / suivant
;   lig  1     : bordure haute      lig 2..21 : puits      lig 22 : bordure basse
;
; TOUCHES (AZERTY)
;   Q gauche   D droite   ENTREE descente   ESPACE rotation
;   Z chute rapide   P pause
; ============================================================================

#include "7020.equ"
#include "3556.equ"

; ============================================================================
; ---  CONSTANTES DEPENDANT DE TA CONFIG  ------------------------------------
; ============================================================================
; Les blocs ne sont plus des mosaiques videotex mais des caracteres que l'on
; redefinit soi-meme. Il ne reste donc que quatre valeurs a confirmer :
;
;   CG2  bits d'attribut selectionnant le banc de generateur.
; ----------------------------------------------------------------------------
CGEN_BASE       .equ    $0000           ; police ROM (BAGC0)
CHAR_BYTES      .equ    8
CH_BASE         .equ    $60

INV_VID         .equ    $04             ; video inverse (bit 2, cf. set_invideo
                                        ; de mixt_api). INVERSE existe deja
                                        ; dans 3556.equ : autre nom ici.
; Les sept caracteres du jeu sont charges par TRAP 19 dans BAGC3, aux slots
; $30..$36 -- au-dela des $00..$24 occupes par le logo. C'est la SEULE
; methode qui fonctionne sur machine reelle : l'ecriture directe en VRAM
; ($0000/$0500) que j'utilisais avant marchait sur l'emulateur mais
; corrompait tout l'ecran sur EXL100 et EXELTEL.
; Les codes evitent $00, $20 et $7F, reserves.
CH_BLOCK        .equ    $30             ; pave plein (pieces)
CH_HZ           .equ    $31             ; trait horizontal
CH_VT           .equ    $32             ; trait vertical
CH_TL           .equ    $33             ; coin haut gauche
CH_TR           .equ    $34             ; coin haut droit
CH_BL           .equ    $35             ; coin bas gauche
CH_BR           .equ    $36             ; coin bas droit
CH_SOLID        .equ    CH_BLOCK
; Les blocs utilisent le caractere $7F, redefini en pave plein par
; init_chars. Les pieces se distinguent par leur couleur.
CH_BLANK        .equ    $37             ; glyphe vide charge avec les autres.
                                        ; $0D serait un code de CONTROLE
                                        ; (retour chariot), pas un glyphe :
                                        ; les cases vides sortaient pleines.

; --- Attribut de caractere (mixt_api.asm + SECTION 13.4 du doc projet) ------
;   bits 7-5 : couleur d'avant-plan
;   bits 4-3 : banc de generateur  BAGC0=$00 BAGC1=$10 BAGC2=$08 BAGC3=$18
;   bits 2-0 : couleur de FOND, mais UNIQUEMENT pour BAGC2/BAGC3 (bit 3 = 1).
;
; BAGC0/BAGC1 sont alphanumeriques : ils n'ont PAS de bits de fond, leur
; fond vient du "delimiteur de zone" MIXT, c'est-a-dire de la derniere
; cellule alphamosaique de la ligne. C'est pour cela que ma couleur de
; cadre se propageait jusqu'au bout de la ligne : j'utilisais $10 (BAGC1).
;
; On travaille donc en BAGC2 : chaque cellule porte son propre fond, et un
; simple ESPACE avec un fond colore donne un pave plein. Pas besoin de
; video inverse ni de caracteres redefinis.
FG_BLACK        .equ    $00
FG_RED          .equ    $20
FG_GREEN        .equ    $40
FG_YELLOW       .equ    $60
FG_BLUE         .equ    $80
FG_MAGENTA      .equ    $A0
FG_CYAN         .equ    $C0
FG_WHITE        .equ    $E0

BG_BLACK        .equ    $00
BG_RED          .equ    $01
BG_GREEN        .equ    $02
BG_YELLOW       .equ    $03
BG_BLUE         .equ    $04
BG_MAGENTA      .equ    $05
BG_CYAN         .equ    $06
BG_WHITE        .equ    $07

; Constate a l'essai : avec $08 l'avant-plan fonctionne (le texte s'affiche)
; mais les bits de fond ne donnent RIEN -> cellules noires, puits vide.
; La table de la section 13.2 decrit la disposition 4 bancs RELOGEE par
; exelimage, pas la configuration par defaut dans laquelle on tourne.
; On reste donc sur $10, seule valeur dont on a la preuve qu'elle rend des
; couleurs correctes (capture de 14h18), et les blocs sont un caractere
; imprimable colore. Un vrai pave plein demandera de reloger un generateur.
; Section 4.2.4 du manuel TMS3556 : le code $20 est RESERVE dans chaque
; generateur comme delimiteur de zone. Sur un tel caractere l'octet
; d'attribut change de sens :
;   caractere normal : BF GF RF | CG1 CG0 | INV DH DW
;   delimiteur ($20) : BF GF RF | MSK INC | BB GB RB
; Les bits 4-3, ou l'on met le numero de generateur, deviennent MSK et INC.
; Avec CG2 = $10 (BAGC1), chaque ESPACE d'une chaine armait donc MSK, dont
; l'effet est d'afficher en espaces toutes les cellules suivantes jusqu'au
; delimiteur suivant : la fin de chaque ligne de texte etait effacee.
; La police ROM est en BAGC0 (trap 13 l'y ecrit), dont le selecteur est $00 :
; bits 4-3 a zero, donc MSK et INC eteints sur les espaces.
; Numerotation des bancs (bits 4-3), confirmee par Exelnoid qui tourne sur
; machine reelle : $00 = BAGC0, $08 = BAGC1, $10 = BAGC2, $18 = BAGC3.
; J'avais interverti BAGC1 et BAGC2 pendant toute la mise au point.
; trap 13 charge la police en $0000, que BAGC2 designe par defaut : le texte
; s'affiche donc avec $10, comme le fait Exelnoid.
; Essai de la police ROM (BAGC2) sans caractere redefini : ECHEC, mais
; instructif. Le manuel dit qu'une cellule delimiteur ($20) s'affiche
; TOUJOURS en aplat de la couleur d'AVANT-PLAN de son propre attribut,
; jamais en noir/transparent -- sauf si le masquage (DC3) est actif ET
; le bit MSK arme sur cette cellule, auquel cas elle prend la couleur de
; FOND a la place. Avec DC3=0 (notre reglage), $20 est donc un pave plein
; de la couleur du texte (le carre rouge observe), pas un espace. Avec
; DC3=1, c'est la propagation de masquage d'origine qui revient. Aucun
; reglage de CM2 ne rend $20 a la fois sur et reellement vide : la police
; personnalisee (glyphe vide sur un code different de $20) est necessaire,
; pas un contournement possible autrement.
CG2             .equ    $18             ; NOTRE police, dans BAGC3
CG_BLK          .equ    $18             ; BAGC3 : blocs et cadre, aucun
                                        ; d'eux n'utilise le code $20

; Tout le decor (texte, cadre, titre, aide) prend la couleur du theme,
; calculee au vol dans atr_ui. Seules les pieces gardent leur couleur
; propre. Le theme par defaut est le rouge, pour rester dans le ton de
; l'image d'accueil.
ATR_TEXT        .equ    FG_WHITE|CG_BLK    ; conserve pour reference
ATR_TITLE       .equ    FG_CYAN|CG_BLK
ATR_HELP        .equ    FG_GREEN|CG_BLK
ATR_EMPTY       .equ    FG_BLACK|CG_BLK
ATR_WALL        .equ    FG_BLUE|CG_BLK     ; cadre bleu ; le carre creux
                                        ; le trait simple le distingue des
                                        ; pieces, pleines
ATR_FLASH       .equ    FG_WHITE|CG_BLK

; ============================================================================
; CONSTANTES DE JEU
; ============================================================================
SCR             .equ    $7340           ; page ecran en VRAM
; ATRCAR est defini par mixt_api.asm ligne 17 : ne pas le redefinir.

FLD_W           .equ    10              ; largeur du puits en cases
FLD_H           .equ    20              ; hauteur du puits (NES/Guideline ;
                                        ; le Game Boy en fait 18)
FLD_COL         .equ    15              ; colonne texte de la case x=0
; Une case = UNE cellule texte, soit 8x10 pixels : c'est a peu pres carre.
; Avec deux cellules de large la case faisait 16x10, une fois et demie plus
; large que haute, et toutes les pieces paraissaient etirees.
FLD_ROW         .equ    2               ; ligne texte de la case y=0
FLD_CX          .equ    FLD_COL+FLD_W   ; colonne centrale du puits (=20)
; Ligne tampon cachee au-dessus du puits visible (convention Guideline) :
; en interne le puits fait 21 lignes, seules les 20 du bas sont dessinees.
; Sans elle, certaines pieces (la barre I, dont l'apparition ne touche
; jamais la ligne 0 de sa boite de rotation) ne pouvaient jamais remplir
; la toute premiere ligne visible : la partie pouvait finir avec cette
; ligne encore vide, sans que le joueur ait vraiment pu l'utiliser.
BUF_H           .equ    1               ; lignes cachees au-dessus du puits
FLD_H_TOT       .equ    21              ; FLD_H+BUF_H, en dur (idem FLD_SIZE)
FLD_SIZE        .equ    210             ; FLD_W*FLD_H_TOT, en dur pour eviter
                                        ; toute ambiguite d'expression

PAN_COL         .equ    29              ; panneau droit, dans son cadre
PRV_COL         .equ    31              ; apercu piece suivante
PRV_ROW         .equ    12              ; suit "Suivant:", remonte de 2

SCR_CX          .equ    20              ; centre de l'ecran 40 colonnes
MSG_ROW         .equ    23              ; messages SOUS le puits (jamais dedans)
MSG_ROW2        .equ    24

SPAWN_X         .equ    3
SPAWN_Y         .equ    0

IDLE_LIMIT      .equ    250             ; ~5 s sans touche au titre -> demo
DEMO_STUCK_MAX  .equ    20              ; ~1,6 s sans progres -> chute forcee
                                        ; (compte les PAS, pas les frames :
                                        ; voir DEMO_STEP_DELAY)
DEMO_STEP_DELAY .equ    8               ; ~160 ms entre deux actions de la
                                        ; demo : sinon tout s'enchainait en
                                        ; une image, illisible pour qui
                                        ; regarde.

; Codes clavier (releves dans le source d'Exelnoid)
KEY_ARR_LEFT    .equ    $83             ; fleche gauche (KEYLF = 131)
KEY_ARR_RIGHT   .equ    $81             ; fleche droite (KEYRI = 129)
KEY_ARR_DOWN    .equ    $82             ; fleche bas    (KEYDN = 130)
KEY_ENTER       .equ    $0D
KEY_SPACE       .equ    $20
KEY_Z           .equ    $5A
KEY_M           .equ    $4D             ; marche/arret de la musique

KEY_LOCK        .equ    8               ; frames de verrou apres une action
LOCK_DELAY      .equ    25              ; verrouillage differe : ~0,5 s pour
LOCK_MAX        .equ    15              ; glisser encore, 15 relances maxi
DAS_DELAY       .equ    12              ; frames avant auto-repeat
DAS_RATE        .equ    9               ; recharge => repeat toutes les 3 frames
SOFT_DELAY      .equ    10              ; ENTREE : delai avant repetition
SOFT_RATE       .equ    7               ; puis une case toutes les 3 frames

; Duree d'une "frame". La boucle interne fait 256 DJNZ (~8 cycles chacun).
; A 56, une frame durait ~90 ms : au niveau 0 la gravite attend 48 frames,
; soit plus de 4 secondes par case -- les pieces semblaient immobiles.
; 12 donne ~20 ms. Si les pieces tombent trop vite, augmenter ; trop lent,
; diminuer. La table speed_tbl est calee sur une frame de 20 ms.
VD_OUTER        .equ    12

; ============================================================================
; VARIABLES (SRAM)
; ============================================================================
cur_pc          .equ    $C400           ; piece courante 0..6
cur_rot         .equ    $C401
cur_x           .equ    $C402
cur_y           .equ    $C403
next_pc         .equ    $C404
rng_lo          .equ    $C405           ; LFSR 16 bits (l'ancien 8 bits ne
rng_hi          .equ    $C411           ; sortait que des 0 et des 4)
key_raw         .equ    $C412           ; lecture brute du clavier
key_prev        .equ    $C43D           ; lecture precedente (anti-rebond)
key_lock        .equ    $C43E           ; verrou apres une action
lf_t1           .equ    $C43F           ; temporaires du LFSR
lf_t2           .equ    $C440
lf_t3           .equ    $C441
soft_ctr        .equ    $C442           ; cadence de la descente douce
dc_slot         .equ    $C443           ; slot en cours de redefinition
dc_src          .equ    $C444           ; offset du motif dans blk_bmp
dc_i            .equ    $C457           ; index dans chars_tbl
bag             .equ    $C458           ; sac de sept pieces (7 octets)
bag_i           .equ    $C45F           ; prochaine piece a tirer du sac
landed          .equ    $C460           ; 1 = la piece touche, delai en cours
lock_ctr        .equ    $C461           ; frames restantes avant verrouillage
lock_moves      .equ    $C462           ; relances du delai deja accordees
ps_row          .equ    $C464           ; put_str : ligne
ps_col          .equ    $C465           ;           colonne courante
ps_hi           .equ    $C466           ;           pointeur chaine, poids fort
ps_lo           .equ    $C467           ;           pointeur chaine, poids faible
ps_ch           .equ    $C468           ;           caractere courant
start_lvl       .equ    $C469           ; niveau de depart, choisi au titre
idle_ctr        .equ    $C46A           ; frames sans touche, au titre
demo_mode       .equ    $C46B           ; 1 = partie jouee par la demo
demo_rot        .equ    $C46C           ; rotation visee par la demo
demo_x          .equ    $C46D           ; colonne visee par la demo
demo_stuck      .equ    $C46E           ; PAS sans progres, dans la demo
demo_delay      .equ    $C46F           ; compte a rebours entre deux pas
theme           .equ    $C445           ; index de couleur du decor (0..6)
atr_ui          .equ    $C446           ; attribut courant du decor (texte)
atr_frm         .equ    $C463           ; idem, banc des blocs (cadre)
intro_bg        .equ    $C447           ; index de couleur de fond de l'image
; touches redefinissables, dans cet ordre (l'ecran d'options les indexe)
k_left          .equ    $C448
k_right         .equ    $C449
k_down          .equ    $C44A
k_rot           .equ    $C44B
k_drop          .equ    $C44C
opt_i           .equ    $C44D
opt_key         .equ    $C44E
music_on        .equ    $C44F           ; 1 = musique active (touche M)
; parametres de la fenetre recopiee depuis l'image d'accueil
w_srch          .equ    $C450           ; adresse source, poids fort
w_srcl          .equ    $C451           ; adresse source, poids faible
w_w             .equ    $C452           ; largeur en cellules
w_h             .equ    $C453           ; hauteur en cellules
w_col           .equ    $C454           ; colonne d'arrivee
w_row           .equ    $C455           ; ligne d'arrivee
w_skip          .equ    $C456           ; 80 - largeur*2
drop_ctr        .equ    $C406
drop_spd        .equ    $C407
key_cur         .equ    $C408
key_last        .equ    $C409
level           .equ    $C40A
game_over       .equ    $C40B
locked          .equ    $C40C
fail_why        .equ    $C40D           ; DIAG 1=mur X 2=sol Y 3=case occupee
fail_idx        .equ    $C40E           ; DIAG index field[] fautif
fail_val        .equ    $C40F           ; DIAG valeur lue dans field[]
dbg_lock        .equ    $C410           ; DIAG 1 = premier blocage fige

tmp_a           .equ    $C413
tmp_b           .equ    $C414
tmp_c           .equ    $C415           ; attribut pour draw_block
tmp_e           .equ    $C417
tmp_f           .equ    $C418
tmp_g           .equ    $C419
tmp_x           .equ    $C41A           ; case x
tmp_y           .equ    $C41B           ; case y

cellx           .equ    $C41C           ; 4 octets
celly           .equ    $C420           ; 4 octets

try_x           .equ    $C424
try_y           .equ    $C425
try_rot         .equ    $C426
cand_x          .equ    $C427
cand_y          .equ    $C428
cand_rot        .equ    $C429
ok_flag         .equ    $C42A

nlines          .equ    $C42B
row_ctr         .equ    $C42C
lvl_ctr         .equ    $C42D
paused          .equ    $C42E
das_ctr         .equ    $C42F

score_dig       .equ    $C430           ; 6 chiffres, poids fort en premier
lines_dig       .equ    $C436           ; 3 chiffres
tmp_h           .equ    $C439
seed_ctr        .equ    $C43A
blk_l           .equ    $C43B           ; code caractere moitie gauche
blk_r           .equ    $C43C           ; code caractere moitie droite

; Le puits etait en $C500 ; des cases fantomes y apparaissaient en cours
; de partie. Deplace en $C600 pour ecarter un conflit d'adresse.
field           .equ    $C600           ; 10*21 = 210 octets (FLD_SIZE),
                                        ; ligne cachee incluse ; 0=vide,
                                        ; 1..7=piece

;        .org    $8004
	.org    $1000
; ============================================================================
; INITIALISATION
; ============================================================================
start:
        dint
        mov     %$58,B
        ldsp
        movp    P40,A
        movp    P36,A
        call    @init_vdp
        eint

        ; Police ROM en $0000, et BAGC0 programme EXPLICITEMENT dessus.
        ; Les deux moities comptent : sans la programmation, la base de BAGC0
        ; restait celle laissee par le moniteur et les lettres sortaient
        ; bruitees ; avec $0200, l'emulateur suivait TEMP8 mais la machine
        ; reelle ecrivait quand meme en $0000, d'ou un banc vide (barres).
        movd    %$0000,TEMP8
        trap    13


        clr     A                       ; theme 0 = rouge
        sta     @theme
        call    @set_theme

        clr     A                       ; niveau de depart 0 -- OUBLI : cette
        sta     @start_lvl              ; case n'etait jamais initialisee et
                                        ; contenait n'importe quoi au demarrage
                                        ; ("1P" observe au lieu de "00").
        sta     @demo_mode              ; pas de demo en cours au demarrage

        mov     %1,A                    ; musique active au demarrage
        sta     @music_on

        mov     %KEY_ARR_LEFT,A         ; touches par defaut : fleches pour
        sta     @k_left                 ; le deplacement lateral, ENTREE
        mov     %KEY_ARR_RIGHT,A        ; pour la descente, ESPACE pour la
        sta     @k_right                ; rotation, Z pour la chute rapide.
        mov     %KEY_ARR_DOWN,A         ; Toutes redefinissables par la
        sta     @k_down                 ; touche O.
        mov     %KEY_SPACE,A
        sta     @k_rot
        mov     %KEY_Z,A
        sta     @k_drop

        call    @intro_load             ; generateurs de l'image d'accueil

        ; R35 = image de VDP06 utilisee par l'IT $F6BD : garde la couleur
        mov     %$88,A
        sta     @$23

        call    @init_textapi
        call    @set_25LINE

        movd    %SCR,R1
        call    @set_vidbuf
        movd    %SCR,R1
        call    @set_screen_adr

        movd    %screen_data2+24,R1
        call    @set_MIXTMODE

        lda     @atr_ui
        movd    %$0000,TEMP1
        movd    %$1928,TEMP2            ; 25 lignes x 40 colonnes
        call    @set_window             ; efface tout l'ecran
                                        ; (pas de clear_all ici : nos glyphes
                                        ; ne sont charges qu'a la fin de
                                        ; intro_screen)

;       call    @init_chars             ; SUPPRIME : ecriture directe en
                                        ; VRAM, incorrecte sur machine
                                        ; reelle. Voir le trap 19 dans
                                        ; intro_screen.
        call    @beep                   ; DIAG : bip direct sur le buzzer
        call    @music_go               ; la musique demarre des l'intro
        call    @intro_screen           ; image d'accueil, ESPACE pour passer
        br      @title                  ; title_draw est une SOUS-ROUTINE :
                                        ; sans ce saut on tombait dedans, son
                                        ; rets depilait une adresse jamais
                                        ; empilee et tw_loop n'etait jamais
                                        ; atteint (d'ou O / M / T inertes)

; ----------------------------------------------------------------------------
; ECRAN TITRE (sert aussi a semer le generateur aleatoire)
; ----------------------------------------------------------------------------
; --- ecran titre : ESPACE lance la partie, O / M / T restent actifs -------
title_draw:
        lda     @atr_ui                 ; efface tout (l'ecran d'options a
        movd    %$0000,TEMP1            ; pu ecrire n'importe ou)
        movd    %$1928,TEMP2
        call    @set_window
        movp    %$05,P45                ; DC5 = 1 : BAGC3 doit rester
        movp    %$88,P45                ; ALPHAMOSAIQUE. set_window remet CM2
                                        ; a zero et l'efface, ce qui rendait
                                        ; nos cellules alphanumeriques : sans
                                        ; fond propre, elles heritaient de
                                        ; celui du logo (la barre a droite).
                                        ; Valeur $88 (et non $E8) : table 3.6
                                        ; du manuel TMS3556, CM2 = DC1..DC8 du
                                        ; bit 7 au bit 0. $E8=11101000 activait
                                        ; aussi DC3 (masquage), sans necessite.
                                        ; Cette lecture de la table vient du
                                        ; manuel TMS3556 lui-meme, PAS d'Exelnoid :
                                        ; Exelnoid tourne en mode bitmap plein,
                                        ; jamais en alphamosaique, et ne peut
                                        ; donc rien confirmer sur CM2/DC5. Seule
                                        ; sa table des bancs de generateurs
                                        ; (bits 4-3 de l'attribut) restait valable
                                        ; comme reference, le mode d'affichage
                                        ; n'y changeant rien.
        call    @clear_all              ; $20 est un glyphe parasite ici
        call    @draw_static
        lda     @atr_ui
        sta     @ATRCAR
        mov     %10,A               ; lig 10, col 16 : "EXELTRIS" centre
        sta     @ps_row
        mov     %16,A
        sta     @ps_col
        movd    %s_title_e-1,R1
        sta     @ps_hi
        mov     B,A
        sta     @ps_lo
        call    @put_str
        lda     @atr_ui
        sta     @ATRCAR
        mov     %24,A                    ; lig 24 col 11 : Appuyez sur espace
        sta     @ps_row
        mov     %11,A
        sta     @ps_col
        movd    %s_press_e-1,R1
        sta     @ps_hi
        mov     B,A
        sta     @ps_lo
        call    @put_str
        call    @draw_start_lvl
        rets

; --- "Niveau depart: XX", lig 22, affiche seul (pas de redraw complet) -----
draw_start_lvl:
; Sous le puits, ligne MSG_ROW (23), centre sur les 40 colonnes -- comme
; "Appuyez sur espace" (ligne 24). Le puits ne fait que 10 colonnes de
; large (une par case, pas deux comme je le croyais) : la premiere version,
; placee a l'interieur, debordait largement sur le panneau de droite.
        lda     @atr_ui
        sta     @ATRCAR
        mov     %MSG_ROW,A
        sta     @ps_row
        mov     %11,A                   ; "Niveau depart: XX" = 17 car,
        sta     @ps_col                 ; centre sur 40 colonnes : col 11
        movd    %s_slvl_e-1,R1
        sta     @ps_hi
        mov     B,A
        sta     @ps_lo
        call    @put_str
        lda     @start_lvl
        clr     B
        cmp     %10,A
        jnc     @dsl_un
        sub     %10,A
        mov     %1,B
dsl_un: sta     @tmp_a                  ; unites
        mov     B,A
        sta     @tmp_b                  ; dizaines
        mov     %26,B                   ; 11 + 15 : apres "Niveau depart: "
        mov     %MSG_ROW,A
        call    @locate
        lda     @tmp_b
        add     %$30,A
        call    @to_slot
        call    @put_char
        mov     %27,B
        mov     %MSG_ROW,A
        call    @locate
        lda     @tmp_a
        add     %$30,A
        call    @to_slot
        call    @put_char
        rets

title:
        call    @title_draw
        mov     %1,A
        sta     @seed_ctr
        clr     A                       ; etat clavier propre
        sta     @key_cur
        sta     @key_last
        sta     @key_prev
        sta     @key_lock
        sta     @idle_ctr               ; on ne redeclenche pas la demo tout
        call    @wait_release           ; de suite apres l'avoir interrompue
tw_loop:
        call    @wait_frame
        lda     @seed_ctr               ; entropie : duree avant appui
        inc     A
        sta     @seed_ctr
        call    @read_key
        lda     @key_cur
        jne     @tw_active              ; une touche est enfoncee
        lda     @idle_ctr               ; rien depuis un moment : compte
        inc     A
        sta     @idle_ctr
        cmp     %IDLE_LIMIT,A
        jc      @demo_start             ; jc : idle_ctr >= IDLE_LIMIT
        br      @tw_loop
tw_active:
        clr     A
        sta     @idle_ctr
        lda     @key_cur                ; recharge : ecrase par le clr
        cmpa    @key_last               ; sur front seulement
        jeq     @tw_loop
        cmp     %KEY_SPACE,A
        jeq     @tw_go
        cmp     %$4F,A                  ; O : redefinition des touches
        jne     @tw_k1
        call    @options_screen
        call    @title_draw
        br      @tw_loop
tw_k1:
        cmp     %KEY_M,A                ; M : musique
        jne     @tw_k1b
        call    @di_music
        br      @tw_loop
tw_k1b:
        cmp     %KEY_ARR_LEFT,A         ; niveau de depart -1
        jne     @tw_k1c
        lda     @start_lvl
        jeq     @tw_lvl_show            ; deja a 0
        dec     A
        sta     @start_lvl
        br      @tw_lvl_show
tw_k1c:
        cmp     %KEY_ARR_RIGHT,A        ; niveau de depart +1
        jne     @tw_k2
        lda     @start_lvl
        cmp     %19,A
        jeq     @tw_lvl_show            ; deja au maximum
        inc     A
        sta     @start_lvl
tw_lvl_show:
        call    @draw_start_lvl
        br      @tw_loop
tw_k2:
        cmp     %$54,A                  ; T : couleur
        jne     @tw_loop
        lda     @theme
        inc     A
        cmp     %7,A
        jne     @tw_t
        clr     A
tw_t:
        sta     @theme
        call    @set_theme
        call    @title_draw
        br      @tw_loop

demo_start:
        mov     %1,A
        sta     @demo_mode
        br      @tw_go                  ; meme amorce que ESPACE : graine +
                                        ; new_game. spawn_piece choisira la
                                        ; cible de la premiere piece.

tw_go:
        lda     @seed_ctr
        jne     @tw_seed
        mov     %$A5,A                  ; graine jamais nulle
tw_seed:
        sta     @rng_lo
        mov     %$AC,A
        sta     @rng_hi

; ============================================================================
; NOUVELLE PARTIE
; ============================================================================
new_game:
        clr     A
        sta     @game_over
        sta     @dbg_lock
        sta     @paused
        sta     @lvl_ctr
        sta     @das_ctr
        sta     @key_cur
        sta     @key_last
        sta     @key_prev
        sta     @key_lock
        sta     @soft_ctr
        sta     @key_raw
        sta     @landed
        sta     @lock_ctr
        sta     @lock_moves

        mov     %6,B                    ; score a zero
ng_sc:  dec     B
        clr     A
        sta     @score_dig(B)
        mov     B,A
        jne     @ng_sc

        mov     %3,B                    ; lignes a zero
ng_ln:  dec     B
        clr     A
        sta     @lines_dig(B)
        mov     B,A
        jne     @ng_ln

        mov     %FLD_SIZE,B             ; puits vide
ng_fld: dec     B
        clr     A
        sta     @field(B)
        mov     B,A
        jne     @ng_fld

        lda     @start_lvl              ; niveau choisi au titre
        sta     @level
        call    @set_speed
        call    @draw_static
        call    @clear_msg              ; enleve le "APPUYEZ SUR ESPACE"
                                        ; laisse par l'ecran titre
        call    @draw_field
        call    @show_score
        call    @show_lines
        call    @show_level

        call    @music_go

        mov     %7,A                    ; sac vide : rempli au 1er tirage
        sta     @bag_i
        call    @bag_next               ; premiere piece "suivante"
        sta     @next_pc
        call    @spawn_piece

        lda     @demo_mode              ; petite etiquette, pour que la
        jeq     @ng_end                 ; partie qui se joue seule ne
        lda     @atr_ui                 ; ressemble pas a un bug
        sta     @ATRCAR
        clr     A
        sta     @ps_row                 ; lig 0, col 0 : au-dessus du cadre
        sta     @ps_col
        movd    %s_demo_e-1,R1
        sta     @ps_hi
        mov     B,A
        sta     @ps_lo
        call    @put_str
ng_end:

; ============================================================================
; BOUCLE PRINCIPALE
; ============================================================================
main_loop:
        call    @wait_frame
        call    @lfsr                   ; libre : ajoute de l'entropie reelle
        call    @read_key
;       call    @show_ctr               ; DIAG gravite

        lda     @paused
        jeq     @ml_run
        call    @do_pause
        br      @main_loop
ml_run:
        lda     @demo_mode
        jeq     @ml_real
        lda     @key_cur                ; une VRAIE touche interrompt la demo
        jeq     @ml_demo_go
        clr     A
        sta     @demo_mode
        br      @title                  ; retour propre a l'ecran titre
ml_demo_go:
        lda     @demo_delay             ; rythme la demo : un pas visible
        jeq     @ml_demo_act            ; toutes les DEMO_STEP_DELAY images,
        dec     A                       ; pas une action instantanee par
        sta     @demo_delay             ; image (illisible pour un spectateur)
        br      @ml_after
ml_demo_act:
        mov     %DEMO_STEP_DELAY,A
        sta     @demo_delay
        call    @demo_step
        br      @ml_after
ml_real:
        call    @do_input
ml_after:
        lda     @game_over
        jne     @ml_over
        call    @do_gravity
        lda     @game_over
        jne     @ml_over
        br      @main_loop

ml_over:
; En demo, on ne s'arrete pas sur "Partie finie / Appuyez sur espace" --
; personne ne serait la pour appuyer. Retour direct au titre, qui remettra
; son propre minuteur d'inactivite a zero.
        lda     @demo_mode
        jeq     @ml_over_real
        clr     A
        sta     @demo_mode
        br      @title
ml_over_real:
        call    @over_screen
        br      @new_game

; ============================================================================
; REDEFINITION DES CARACTERES
; ============================================================================
; Redefinit le caractere $7F en pave plein.
;
; Le generateur n'est PAS range caractere par caractere : les 10 octets
; consecutifs ecrits precedemment n'ont change qu'UNE ligne de balayage de
; $7F, les 9 autres etant parties dans les caracteres voisins. C'est la
; signature d'un rangement par PLANS de ligne :
;       adresse = base + ligne*128 + slot
; Un generateur fait donc 10 x 128 = 1280 octets ($500), ce qui colle avec
; la carte VRAM du projet ($0000-$04FF = generateur 0, $0500-$09FF = 1).
;
; Pour le slot $7F les 10 adresses sont donc, a partir de la base :
;       $007F $00FF $017F $01FF $027F $02FF $037F $03FF $047F $04FF
; soit poids fort = ligne/2 et poids faible = $7F ou $FF en alternance.
init_chars:
        clr     A                       ; generateur 0 : base $0000
        sta     @lf_t1
        call    @def_set
        mov     %$05,A                  ; generateur 1 : base $0500
        sta     @lf_t1
        ; tombe dans def_set

; charge les NCHARS caracteres decrits par chars_tbl dans le generateur
; dont le poids fort de base est dans lf_t1
def_set:
        sta     @lf_t1
        clr     A
        sta     @dc_i
ds_loop:
        lda     @dc_i                   ; slot
        rl      A
        mov     A,B
        lda     @chars_tbl(B)
        sta     @dc_slot
        lda     @dc_i                   ; offset du motif
        rl      A
        inc     A
        mov     A,B
        lda     @chars_tbl(B)
        sta     @dc_src
        call    @def_char
        lda     @dc_i
        inc     A
        sta     @dc_i
        cmp     %NCHARS,A
        jne     @ds_loop
        rets

; ecrit les 10 lignes du motif dc_src dans le slot dc_slot
def_char:
        clr     A
        sta     @lf_t3                  ; ligne = 0
dch_loop:
        lda     @lf_t3                  ; poids fort = base + ligne/2
        mov     A,B
        lda     @cg_hi(B)
        mov     A,B
        lda     @lf_t1
        add     B,A
        sta     @lf_t2

        lda     @lf_t3                  ; poids faible = slot, +$80 si la
        and     %1,A                    ; ligne est impaire
        jeq     @dch_even
        mov     %$80,A
        br      @dch_lo
dch_even:
        clr     A
dch_lo:
        mov     A,B
        lda     @dc_slot
        add     B,A
        mov     A,B                     ; B = poids faible
        lda     @lf_t2                  ; A = poids fort
        call    @set_acmpxy

        lda     @lf_t3                  ; octet du motif
        mov     A,B
        lda     @dc_src
        add     B,A
        mov     A,B
        lda     @blk_bmp(B)
        movp    A,P46                   ; P46 = port de donnees VDP
        lda     @lf_t3
        inc     A
        sta     @lf_t3
        cmp     %10,A
        jne     @dch_loop
        rets

cg_hi:  .byte   0,0,1,1,2,2,3,3,4,4
cg_lo:  .byte   $7F,$FF,$7F,$FF,$7F,$FF,$7F,$FF,$7F,$FF

; Table des caracteres a redefinir : slot, puis offset du motif dans blk_bmp
NCHARS  .equ    8
chars_tbl:
        .byte   CH_BLOCK,0
        .byte   CH_HZ,10
        .byte   CH_VT,20
        .byte   CH_TL,30
        .byte   CH_TR,40
        .byte   CH_BL,50
        .byte   CH_BR,60
        .byte   CH_BLANK,70

; Motifs, premiere ligne ecrite = BAS de la cellule, 8 pixels de large.
; Le trait passe au milieu de la cellule : pixel 3 en vertical, ligne 5
; en horizontal.
blk_bmp:                                ; 0  : pave plein des pieces
        .byte   $00                     ; ligne du bas noire : separateur
        .byte   $FE,$FE,$FE,$FE         ; bit 0 a zero : colonne de droite
        .byte   $FE,$FE,$FE,$FE,$FE     ; noire, les blocs restent separes
        .byte   $00,$00,$00,$00,$00     ; 10 : trait horizontal
        .byte   $FF,$00,$00,$00,$00
        .byte   $10,$10,$10,$10,$10     ; 20 : trait vertical
        .byte   $10,$10,$10,$10,$10
        .byte   $10,$10,$10,$10,$10     ; 30 : coin haut gauche
        .byte   $1F,$00,$00,$00,$00
        .byte   $10,$10,$10,$10,$10     ; 40 : coin haut droit
        .byte   $F0,$00,$00,$00,$00
        .byte   $00,$00,$00,$00,$00     ; 50 : coin bas gauche
        .byte   $1F,$10,$10,$10,$10
        .byte   $00,$00,$00,$00,$00     ; 60 : coin bas droit
        .byte   $F0,$10,$10,$10,$10
blank_bmp:                              ; 70 : case vide ($37), sert aussi a
        .byte   $00,$00,$00,$00,$00     ; retablir le delimiteur $20
        .byte   $00,$00,$00,$00,$00

; ============================================================================
; ECRAN D'INTRO (image produite par EXELIMAGE)
; ----------------------------------------------------------------------------
; Les donnees (BAGC2_DATA, BAGC3_DATA, SCREEN_DATA) sont dans introdata.asm.
; L'image reloge BAGC2 en $0A00 et BAGC3 en $0F00 et y charge 128 caracteres
; chacun. Aucun conflit avec le jeu : Exeltris dessine en $10 (BAGC1) et ses
; deux caracteres redefinis sont dans les generateurs 0 et 1, en VRAM $0000
; et $0500. Registres differents, memoire differente.
;
; DC5 doit etre remis a 1 APRES set_25LINE pour que BAGC3 reste alphamosaique.
; ============================================================================
; --- morceaux de l'image d'accueil affiches a gauche du puits --------------
; Les generateurs BAGC2/BAGC3 restent charges apres l'intro et le jeu dessine
; en BAGC1 : les caracteres de l'image sont toujours disponibles.
;
; Les offsets sont calcules A LA MAIN : TASM evalue de gauche a droite, donc
; SCREEN_DATA+ligne*80+colonne*2 serait faux.  offset = ligne*80 + colonne*2
;   cathedrale : ligne 2,  colonne 10  ->  2*80 + 10*2 =  180
;   logo       : ligne 16, colonne 5   -> 16*80 +  5*2 = 1290
;
; Le logo fait environ 29 cellules de large dans l'image alors que le
; bandeau de gauche n'en a que 13 : seules les premieres lettres tiennent.
SEP_COL         .equ    13              ; colonne separatrice (cadre en 14)
SEP_ROW         .equ    2
SEP_H           .equ    20              ; couvre cathedrale (2..10) et
                                        ; logo (18..21)
LOGO_COL        .equ    0               ; logo EXELTRIS : 12 x 3 cellules
LOGO_ROW        .equ    16              ; remonte de 2 lignes

; La ROM ecrit en permanence des donnees de caracteres en $0A00 (section
; 13.7 du doc projet) : y loger BAGC2 marchait sur l'emulateur et corrompait
; l'ecran sur machine reelle. Zones sures confirmees : $0200, $0800, $0F00,
; $1400.
INTRO_BAGC2     .equ    $0F00
INTRO_BAGC3     .equ    $1400

; Chargement des generateurs. A appeler TOT, avant init_textapi et
; set_25LINE : c'est l'ordre du programme genere par exelimage, et
; set_25LINE est connu pour perturber DC5.
intro_load:
        movp    %$01,P45                ; BAGC2 (registre $0D) -> $0F00
        movp    %$FE,P45
        movp    %$02,P45
        movp    %$0E,P45                ; poids fort = (adresse>>8) - 1
        movp    %$0D,P45
        movp    %$00,P45
        movp    %$00,P45

        movp    %$05,P45                ; BAGC3 (registre $0E) -> $1400,
        movp    %$88,P45                ; DC5 = 1 pour le garder alphamosaique
        movp    %$01,P45
        movp    %$FE,P45
        movp    %$02,P45
        movp    %$13,P45
        movp    %$0E,P45
        movp    %$00,P45
        movp    %$00,P45

        movd    %BAGC2_DATA,TEMP3
        movd    %INTRO_BAGC2,TEMP2
        mov     %$00,TEMP7
        mov     %128,TEMP4-1
        trap    19
        movd    %BAGC3_DATA,TEMP3
        movd    %INTRO_BAGC3,TEMP2
        mov     %$00,TEMP7
        mov     %128,TEMP4-1
        trap    19
        rets

; Affichage de l'image, une fois l'API texte initialisee.
intro_screen:
        ; L'effacement interne de set_window remplit l'ecran avec le code
        ; $20. En $08 (BAGC2) celui-ci fait encore partie du dessin de
        ; l'image (chargee juste avant) : d'ou le motif texture observe au
        ; demarrage. BAGC0 ($00), lui, n'a pas encore ete detourne a ce
        ; stade : trap 13 y a copie la police ROM des le tout debut, et son
        ; slot $20 est le veritable espace, vide.
        mov     %$00,A                  ; fenetre plein ecran, fond noir
        movd    %$0000,TEMP1
        movd    %$1928,TEMP2
        call    @set_window
        movp    %$05,P45                ; DC5 = 1, apres set_window
        movp    %$88,P45
        call    @write_screen

        clr     A                       ; etat clavier propre pour l'intro
        sta     @key_cur
        sta     @key_last
        sta     @key_prev
        sta     @key_lock
        call    @wait_release
is_wait:
        call    @wait_frame
        call    @read_key               ; anti-rebond commun au jeu
        lda     @key_cur
        cmpa    @key_last
        jeq     @is_wait                ; pas de front : on attend
        cmp     %$20,A
        jeq     @is_done
        cmp     %$54,A                  ; T : couleur suivante
        jne     @is_wait
        lda     @theme
        inc     A
        cmp     %7,A
        jne     @is_t
        clr     A
is_t:
        sta     @theme
        call    @set_theme
        call    @write_screen           ; on repeint l'image
        br      @is_wait
is_done:

        movd    %LOGO_CHR,TEMP3         ; le logo prend la place de la
        movd    %INTRO_BAGC3,TEMP2      ; cathedrale dans BAGC3 : elle n'en
        mov     %$00,TEMP7              ; logo en $00..$24
        mov     %37,TEMP4-1
        trap    19

        movd    %FONT_CHR,TEMP3         ; NOTRE police, slots $40..$7E.
        movd    %INTRO_BAGC3,TEMP2      ; trap 13 et la police ROM ne sont pas
        mov     %$40,TEMP7              ; exploitables sur machine reelle ;
        mov     %63,TEMP4-1             ; trap 19 dans BAGC3, si.
        trap    19

        movd    %blk_bmp,TEMP3          ; les 7 caracteres du jeu, slots
        movd    %INTRO_BAGC3,TEMP2      ; $30..$36, apres ceux du logo
        mov     %$30,TEMP7
        mov     %8,TEMP4-1              ; 7 motifs + la case vide
        trap    19

        movd    %blank_bmp,TEMP3        ; efface le slot $20 des deux bancs :
        movd    %INTRO_BAGC3,TEMP2      ; l'image d'accueil y charge un glyphe
        mov     %$20,TEMP7              ; et il s'affiche sur machine reelle,
        mov     %1,TEMP4-1              ; contrairement a ce que dit 4.2.4
        trap    19
        movd    %blank_bmp,TEMP3
        movd    %INTRO_BAGC2,TEMP2
        mov     %$20,TEMP7
        mov     %1,TEMP4-1
        trap    19

        ; BAGC2 REND PAS repointe vers $0000 : depuis l'abandon de la police
        ; ROM, plus rien n'a besoin de ce banc ailleurs. Il reste sur
        ; INTRO_BAGC2 ($0F00) : la cathedrale y est toujours disponible,
        ; et peut etre redessinee en jeu par draw_sub/draw_win.

        ; Pas de set_window/clear_all ici : intro_screen est immediatement
        ; suivi de title_draw (voir "br @title" apres l'appel), qui fait ce
        ; nettoyage lui-meme. Le faire deux fois de suite pour le meme
        ; ecran double inutilement le passage a $20 puis au blanc.
        rets

; --- recopie les deux fenetres, puis pose la colonne separatrice -----------
draw_sub:
; La cathedrale redevient affichable : depuis l'abandon de la police ROM
; (voir plus haut), BAGC2 n'est plus jamais repointe ailleurs -- son
; contenu reste celui charge par l'intro, cathedrale comprise.
        mov     %SCREEN_DATA+180>>8,A   ; cathedrale
        sta     @w_srch
        mov     %SCREEN_DATA+180&$FF,A
        sta     @w_srcl
        mov     %13,A                   ; colonnes 0..12, comme le logo
        sta     @w_w
        mov     %9,A                    ; lignes 2..10 : uniquement BAGC2
        sta     @w_h
        clr     A
        sta     @w_col
        mov     %2,A
        sta     @w_row
        mov     %54,A                   ; 80 - 13*2
        sta     @w_skip
        call    @draw_win
ds_logo:
        call    @draw_logo

; Colonne separatrice. Les cellules de l'image sont ALPHAMOSAIQUES et
; portent un fond ; celles du jeu sont ALPHANUMERIQUES et n'en ont pas :
; elles heritent du fond de la derniere cellule alphamosaique de la ligne.
; Sans ce separateur la couleur de l'image se propage jusqu'au bord droit.
; On n'ecrit PAS le caractere $00 : dans BAGC2 c'est un glyphe plein (celui
; de la cathedrale), et il restait visible. On prend $0C du jeu du logo,
; dont les 10 octets sont nuls : la cellule ne montre que son fond, noir.
; Deux colonnes (12 et 13) pour degager franchement avant le cadre.
        mov     %$18,A                  ; BAGC3, avant-plan et fond noirs
        sta     @ATRCAR
        clr     A
        sta     @$C3FC
sep_loop:
        mov     %SEP_COL,B
        lda     @$C3FC
        add     %SEP_ROW,A
        call    @locate
        mov     %$0D,A                  ; $0D = glyphe vide dans ce jeu
        call    @put_char
        lda     @$C3FC
        inc     A
        sta     @$C3FC
        cmp     %SEP_H,A
        jne     @sep_loop
        rets

; --- logo EXELTRIS : 3 lignes de 12 cellules, glyphes dans BAGC3 ----------
draw_logo:
        lda     @intro_bg               ; BAGC3 + fond du theme
        mov     A,B
        mov     %$18,A
        or      B,A
        sta     @ATRCAR
        clr     A
        sta     @tmp_a                  ; ligne
lg_row:
        clr     A
        sta     @tmp_b                  ; colonne
lg_col:
        lda     @tmp_b
        add     %LOGO_COL,A
        mov     A,B
        lda     @tmp_a
        add     %LOGO_ROW,A
        call    @locate
        lda     @tmp_a                  ; index = ligne*13 + colonne
        mov     A,B
        lda     @mul13(B)
        mov     A,B
        lda     @tmp_b
        add     B,A
        mov     A,B
        lda     @logo_map(B)
        call    @put_char
        lda     @tmp_b
        inc     A
        sta     @tmp_b
        cmp     %13,A                   ; 13 colonnes : la derniere est le
        jne     @lg_col                 ; masque plein, fourni par l'image
        lda     @tmp_a
        inc     A
        sta     @tmp_a
        cmp     %4,A                    ; 4 lignes : la derniere masque aussi
        jne     @lg_row
        rets

; --- recopie une fenetre de SCREEN_DATA decrite par w_* --------------------
draw_win:
        lda     @w_srch
        sta     @$C3D0
        lda     @w_srcl
        sta     @$C3D1
        clr     A
        sta     @$C3FC                  ; ligne dans la fenetre
sub_row:
        clr     A
        sta     @$C3FD                  ; colonne dans la fenetre
sub_col:
        lda     @$C3FC                  ; position ecran
        mov     A,B
        lda     @w_row
        add     B,A
        sta     @$C3D3
        mov     A,TEMP3
        lda     @$C3FD
        mov     A,B
        lda     @w_col
        add     B,A
        mov     A,B
        lda     @$C3D3
        call    @calcul_pointer
        movd    TEMP3,TEMP1
        dint
        trap    9
        lda     @$C3D0                  ; octet d'attribut
        mov     A,TEMP1-1
        lda     @$C3D1
        mov     A,TEMP1
        lda     *TEMP1
        and     %$F8,A                  ; fond = couleur du theme
        sta     @$C3D2
        push    B
        lda     @intro_bg
        mov     A,B
        lda     @$C3D2
        or      B,A
        pop     B
        wvdp(A)
        lda     @$C3D1
        inc     A
        sta     @$C3D1
        jnz     @sub_nc1
        lda     @$C3D0
        inc     A
        sta     @$C3D0
sub_nc1:
        lda     @$C3D0                  ; octet de caractere
        mov     A,TEMP1-1
        lda     @$C3D1
        mov     A,TEMP1
        lda     *TEMP1
        wvdp(A)
        eint
        lda     @$C3D1
        inc     A
        sta     @$C3D1
        jnz     @sub_nc2
        lda     @$C3D0
        inc     A
        sta     @$C3D0
sub_nc2:
        lda     @$C3FD
        inc     A
        sta     @$C3FD
        cmpa    @w_w
        jc      @sub_eol                ; jl hors de portee : on inverse
        br      @sub_col
sub_eol:
        lda     @w_skip                 ; saute la fin de la ligne source
        mov     A,B
        lda     @$C3D1
        add     B,A
        jnc     @sub_lo
        sta     @$C3D1
        lda     @$C3D0
        inc     A
        sta     @$C3D0
        br      @sub_next
sub_lo:
        sta     @$C3D1
sub_next:
        lda     @$C3FC
        inc     A
        sta     @$C3FC
        cmpa    @w_h
        jc      @sub_end
        br      @sub_row
sub_end:
        rets

; recopie SCREEN_DATA (25 lignes x 40 cellules x 2 octets) dans la page video
write_screen:
        mov     %SCREEN_DATA>>8,A
        sta     @$C3D0
        mov     %SCREEN_DATA&$FF,A
        sta     @$C3D1
        clr     A
        sta     @$C3FC
ws_row:
        clr     A
        sta     @$C3FD
ws_col:
        lda     @$C3FC
        mov     A,TEMP3
        lda     @$C3FD
        mov     A,B
        lda     @$C3FC
        call    @calcul_pointer
        movd    TEMP3,TEMP1
        dint
        trap    9
        lda     @$C3D0
        mov     A,TEMP1-1
        lda     @$C3D1
        mov     A,TEMP1
        lda     *TEMP1                  ; octet d'attribut : on remplace ses
        and     %$F8,A                  ; bits de fond par la couleur du
        sta     @$C3D2                  ; theme, le reste est conserve
        push    B
        lda     @intro_bg
        mov     A,B
        lda     @$C3D2
        or      B,A
        pop     B
        wvdp(A)
        lda     @$C3D1
        inc     A
        sta     @$C3D1
        jnz     @ws_nc1
        lda     @$C3D0
        inc     A
        sta     @$C3D0
ws_nc1:
        lda     @$C3D0
        mov     A,TEMP1-1
        lda     @$C3D1
        mov     A,TEMP1
        lda     *TEMP1
        wvdp(A)
        eint
        lda     @$C3D1
        inc     A
        sta     @$C3D1
        jnz     @ws_nc2
        lda     @$C3D0
        inc     A
        sta     @$C3D0
ws_nc2:
        lda     @$C3FD
        inc     A
        sta     @$C3FD
        cmp     %40,A
        jl      @ws_col
        lda     @$C3FC
        inc     A
        sta     @$C3FC
        cmp     %25,A
        jl      @ws_row
        rets

; ============================================================================
; DIAGNOSTIC SON : bip direct sur le buzzer, comme les bruitages d'Exelnoid.
; N'utilise ni le timer, ni les interruptions, ni l'API musique. S'il est
; audible, le buzzer et le son de l'emulateur fonctionnent, et le probleme
; est du cote du timer / de l'interruption. A retirer ensuite.
; ============================================================================
beep:
        push    A
        push    B
        dint
        mov     %150,B                  ; nombre de demi-periodes
bp_loop:
        xorp    %8,P6                   ; bit 3 du port K7 = buzzer
        mov     %100,A
bp_wait:
        dec     A
        jne     @bp_wait
        djnz    B,bp_loop
        eint
        pop     B
        pop     A
        rets

; ============================================================================
; MUSIQUE : (re)demarre la partition depuis le debut
; ============================================================================
; (re)demarre la partition seulement si la musique est active
music_go:
        lda     @music_on
        jeq     @mg_end
        call    @music_start
mg_end: rets

; reprend apres une pause, seulement si la musique est active
music_unpause:
        lda     @music_on
        jeq     @mu_end
        call    @music_play
mu_end: rets

; touche M : bascule marche/arret
di_music:
        mov     %KEY_LOCK,A
        sta     @key_lock
        lda     @music_on
        jne     @dm_off
        mov     %1,A                    ; etait arretee : on relance
        sta     @music_on
        call    @music_start
        rets
dm_off:
        clr     A                       ; etait active : on coupe
        sta     @music_on
        call    @music_stop
        rets

music_start:
        call    @music_stop             ; remet music_adr a zero et arrete
                                        ; le timer : evite que l'interruption
                                        ; lise un pointeur a moitie ecrit
        and     %$EF,FLGCOM             ; bit 4 = "lecture en cours"
        movd    %music_score_end-1,R1
        sta     @music_adr
        mov     B,A
        sta     @music_adr+1
        movd    %music_score_end-1,R1
        sta     @rept_adr
        mov     B,A
        sta     @rept_adr+1
        call    @music_play
        rets

; ============================================================================
; REDEFINITION DES TOUCHES (touche O)
; Les cinq commandes de jeu sont demandees l'une apres l'autre ; la touche
; frappee est memorisee telle quelle, et son code est affiche en hexa. C'est
; ainsi que l'on affecte les fleches du clavier : je ne connais pas leurs
; codes sur cette machine, donc les valeurs par defaut restent Q et D.
; ============================================================================
di_options:
        mov     %KEY_LOCK,A
        sta     @key_lock
        call    @options_screen
        lda     @atr_ui                 ; efface tout : le menu ecrit dans
        movd    %$0000,TEMP1            ; des zones que draw_static ne
        movd    %$1928,TEMP2            ; repeint pas
        call    @set_window
        movp    %$05,P45                ; DC5 = 1 : BAGC3 doit rester
        movp    %$88,P45                ; ALPHAMOSAIQUE. set_window remet CM2
                                        ; a zero et l'efface, ce qui rendait
                                        ; nos cellules alphanumeriques : sans
                                        ; fond propre, elles heritaient de
                                        ; celui du logo (la barre a droite).
        call    @clear_all              ; $20 est un glyphe parasite ici
        call    @draw_static            ; on repeint le jeu
        call    @clear_msg
        call    @draw_field
        call    @draw_piece
        call    @show_score
        call    @show_lines
        call    @show_level
        call    @draw_next
        rets

options_screen:
        lda     @atr_ui
        movd    %$0000,TEMP1
        movd    %$1928,TEMP2
        call    @set_window             ; efface tout l'ecran
        movp    %$05,P45                ; DC5 = 1 : BAGC3 doit rester
        movp    %$88,P45                ; ALPHAMOSAIQUE. set_window remet CM2
                                        ; a zero et l'efface, ce qui rendait
                                        ; nos cellules alphanumeriques : sans
                                        ; fond propre, elles heritaient de
                                        ; celui du logo (la barre a droite).
        call    @clear_all              ; $20 est un glyphe parasite ici
        lda     @atr_ui
        sta     @ATRCAR
        mov     %2,A                    ; lig 2 col 8 : Redefinition des touches
        sta     @ps_row
        mov     %8,A
        sta     @ps_col
        movd    %s_redef_e-1,R1
        sta     @ps_hi
        mov     B,A
        sta     @ps_lo
        call    @put_str
        mov     %5,A                    ; lig 5 col 9 : Appuyez sur la touche
        sta     @ps_row
        mov     %9,A
        sta     @ps_col
        movd    %s_hitkey_e-1,R1
        sta     @ps_hi
        mov     B,A
        sta     @ps_lo
        call    @put_str

        clr     A
        sta     @opt_i
op_loop:
        lda     @opt_i                  ; ligne = 8 + i*2
        rl      A
        add     %8,A
        sta     @tmp_a
        sta     @ps_row                 ; put_str repositionne lui-meme
        mov     %10,A
        sta     @ps_col
        lda     @opt_i                  ; libelle de la commande
        mov     A,B
        lda     @opt_hi(B)
        sta     @ps_hi
        lda     @opt_i
        mov     A,B
        lda     @opt_lo(B)
        sta     @ps_lo
        call    @put_str

        call    @wait_rel_long
op_wait:
        call    @wait_frame
        call    @read_key
        lda     @key_cur
        jeq     @op_wait
        cmpa    @key_last
        jeq     @op_wait
        sta     @opt_key

        ; refuse une touche deja affectee a une commande precedente (les
        ; indices 0..opt_i-1 sont deja definis a ce stade). Utilise tmp_c,
        ; PAS tmp_a : tmp_a porte la ligne d'affichage posee plus haut dans
        ; op_loop, et attendue telle quelle par hex2 juste apres ce bloc --
        ; l'ecraser ici envoyait le code hexa n'importe ou a l'ecran.
        clr     A
        sta     @tmp_c
op_dupchk:
        lda     @tmp_c
        cmpa    @opt_i
        jeq     @op_nodup               ; toutes les affectations precedentes
                                        ; ont ete comparees, sans doublon
        mov     A,B
        lda     @k_left(B)
        cmpa    @opt_key
        jeq     @op_dup
        lda     @tmp_c
        inc     A
        sta     @tmp_c
        br      @op_dupchk
op_dup:
        call    @wait_rel_long          ; touche refusee : on redemande,
        br      @op_wait                ; apres un relachement franc
op_nodup:

        lda     @opt_i                  ; memorise la touche
        mov     A,B
        lda     @opt_key
        sta     @k_left(B)

        mov     %22,A                   ; affiche son code en hexa
        sta     @tmp_b
        lda     @opt_key
        call    @hex2

        lda     @opt_i
        inc     A
        sta     @opt_i
        cmp     %5,A
        jeq     @op_done                ; jeq hors de portee de @op_loop
        br      @op_loop                ; depuis l'ajout du controle anti-
op_done:                                ; doublon : on inverse le test
        call    @wait_rel_long
        rets

; ============================================================================
; THEME DE COULEUR
; ============================================================================
set_theme:
        lda     @theme
        mov     A,B
        lda     @theme_tbl(B)
        sta     @tmp_a
        or      %CG2,A
        sta     @atr_ui
        lda     @tmp_a
        or      %CG_BLK,A
        sta     @atr_frm
        lda     @theme                  ; meme couleur, en index 0-7, pour
        mov     A,B                     ; les bits de fond de l'image
        lda     @theme_bgt(B)
        sta     @intro_bg
        rets

; touche T : couleur suivante, puis on repeint tout le decor
di_theme:
        mov     %KEY_LOCK,A
        sta     @key_lock
        lda     @theme
        inc     A
        cmp     %7,A
        jne     @dt_ok
        clr     A
dt_ok:
        sta     @theme
        call    @set_theme
        call    @draw_static
        call    @clear_msg
        call    @draw_field
        call    @draw_piece
        call    @show_score
        call    @show_lines
        call    @show_level
        call    @draw_next
        rets

; ============================================================================
; CLAVIER
; ============================================================================
; Anti-rebond, comme dans Exelnoid : la touche doit etre lue identique deux
; frames de suite avant d'etre prise en compte. On decremente aussi le verrou
; qui interdit deux actions coup sur coup.
read_key:
        lda     @key_lock               ; verrou d'action
        jeq     @rk_scan
        dec     A
        sta     @key_lock
rk_scan:
        mov     VALUE0,A
        cmp     %$04,A                  ; $04 = pas de touche -> 0
        jne     @rk_val
        clr     A
rk_val:
        sta     @key_raw
        jeq     @rk_stable              ; relachement : valide tout de suite,
                                        ; sinon une lecture qui oscille entre
                                        ; la touche et $04 bloquait key_cur
                                        ; sur la touche indefiniment
        cmpa    @key_prev               ; identique a la frame precedente ?
        jeq     @rk_stable
        sta     @key_prev               ; non : instable, on ne valide rien
        rets
rk_stable:
        lda     @key_cur
        sta     @key_last
        lda     @key_raw
        sta     @key_cur
        rets

; Selon la version de la machine/de l'emulateur, "aucune touche" vaut $04
; ou $00. N'attendre que $04 pouvait bloquer indefiniment sur l'intro.
wait_release:
        call    @wait_frame
        mov     VALUE0,A
        jeq     @wr_ok
        cmp     %$04,A
        jne     @wait_release
wr_ok:  rets

; Attend un relachement FRANC : plusieurs frames de suite sans touche. Sert
; avant de saisir une touche a redefinir, sinon le O qui a ouvert le menu
; est relu aussitot comme premiere affectation.
wait_rel_long:
        mov     %8,B
wrl_loop:
        call    @wait_frame
        mov     VALUE0,A
        jeq     @wrl_down
        cmp     %$04,A
        jeq     @wrl_down
        mov     %8,B                    ; touche encore enfoncee : on repart
        br      @wrl_loop
wrl_down:
        djnz    B,wrl_loop
        rets

do_pause:
        lda     @key_lock               ; meme anti-rebond que les autres
        jne     @dp_end                 ; actions sur front
        lda     @key_cur
        cmpa    @key_last
        jeq     @dp_end
        cmp     %$50,A                  ; 'P'
        jne     @dp_end
        mov     %KEY_LOCK,A
        sta     @key_lock
        clr     A
        sta     @paused
        call    @music_unpause
        call    @clear_msg
        call    @draw_field             ; resynchro ecran <- field[]
        call    @draw_piece             ; la piece en vol n'est PAS dans
                                        ; field[] : draw_field l'effacait,
                                        ; elle ne reapparaissait qu'a la
                                        ; descente suivante
dp_end: rets

; ============================================================================
; ENTREES JOUEUR
; ============================================================================
do_input:
        lda     @key_cur
        jeq     @di_end                 ; aucune touche : rien a faire
        cmpa    @k_left
        jeq     @di_left
        cmpa    @k_right
        jeq     @di_right
        cmpa    @k_down
        jeq     @di_down

        clr     A
        sta     @das_ctr

        lda     @key_lock               ; une action vient d'avoir lieu ?
        jne     @di_end
        lda     @key_cur                ; autres touches : sur front montant
        cmpa    @key_last
        jeq     @di_end
        cmpa    @k_rot
        jne     @di_k0                  ; jeq hors de portee : on inverse
        br      @di_rot
di_k0:
        cmpa    @k_drop
        jne     @di_k1
        br      @di_hard
di_k1:
        cmp     %$54,A                  ; 'T' : couleur du decor
        jne     @di_k2
        br      @di_theme
di_k2:
        cmp     %$4F,A                  ; 'O' : options
        jne     @di_k3
        br      @di_options
di_k3:
        cmp     %KEY_M,A                ; 'M' : musique
        jne     @di_k4
        br      @di_music
di_k4:
        cmp     %$50,A                  ; 'P' pause
        jne     @di_end
        br      @di_pause
di_end:
        rets

di_left:
        call    @das_check
        lda     @ok_flag
        jeq     @di_end
        lda     @cur_x
        dec     A
        sta     @cand_x
        br      @di_move

di_right:
        call    @das_check
        lda     @ok_flag
        jeq     @di_end
        lda     @cur_x
        inc     A
        sta     @cand_x
di_move:
        lda     @cur_y
        sta     @cand_y
        lda     @cur_rot
        sta     @cand_rot
        call    @try_move
        rets

; ENTREE maintenue : sans cadence, drop_one etait appele a CHAQUE frame,
; soit une cinquantaine de cases par seconde -- une chute rapide deguisee.
di_down:
        clr     A
        sta     @das_ctr
        lda     @key_cur
        cmpa    @key_last
        jne     @dd_now                 ; nouvel appui : on descend aussitot
        lda     @soft_ctr
        inc     A
        sta     @soft_ctr
        cmp     %SOFT_DELAY,A
        jc      @dd_rep                 ; delai ecoule
        rets
dd_rep:
        mov     %SOFT_RATE,A            ; recharge : repetition reguliere
        sta     @soft_ctr
        br      @dd_go
dd_now:
        clr     A
        sta     @soft_ctr
dd_go:
        call    @drop_one
        lda     @landed
        jne     @dd_end
        call    @add_point              ; +1 point par case descendue
dd_end:
        lda     @drop_spd               ; on recharge la gravite
        sta     @drop_ctr
        rets

; --- rotation horaire, avec rattrapage lateral (wall-kick simple) -----------
; Le Tetris d'origine ne rattrape pas : supprimer les deux blocs dr_k1/dr_k2
; pour un comportement strictement classique.
di_rot:
        mov     %KEY_LOCK,A             ; verrou anti-rebond
        sta     @key_lock
        lda     @cur_rot
        inc     A
        and     %3,A
        sta     @cand_rot
        lda     @cur_y
        sta     @cand_y
        lda     @cur_x
        sta     @cand_x
        call    @try_move
        lda     @ok_flag
        jne     @dr_end
dr_k1:
        lda     @cur_x                  ; decale d'une case a gauche
        dec     A
        sta     @cand_x
        call    @try_move
        lda     @ok_flag
        jne     @dr_end
dr_k2:
        lda     @cur_x                  ; puis d'une case a droite
        inc     A
        sta     @cand_x
        call    @try_move
dr_end:
        rets

di_hard:
        mov     %KEY_LOCK,A
        sta     @key_lock
        br      @dh_loop
dh_loop:
        call    @drop_one
        lda     @landed                 ; touche le sol : verrouillage
        jne     @dh_lock                ; immediat, sans delai
        call    @add_point              ; +2 points par case
        call    @add_point
        br      @dh_loop
dh_lock:
        call    @do_lock
dh_end:
        rets

di_pause:
        mov     %KEY_LOCK,A
        sta     @key_lock
        mov     %1,A
        sta     @paused
        call    @music_pause
        lda     @atr_ui
        sta     @ATRCAR
        mov     %23,A               ; lig 23 col 18 : PAUSE centre
        sta     @ps_row
        mov     %18,A
        sta     @ps_col
        movd    %s_pause_e-1,R1
        sta     @ps_hi
        mov     B,A
        sta     @ps_lo
        call    @put_str
        rets

; --- auto-repeat gauche/droite : ok_flag=1 s'il faut bouger -----------------
das_check:
        mov     %1,A
        sta     @ok_flag
        lda     @key_cur
        cmpa    @key_last
        jne     @dsc_new
        lda     @das_ctr
        inc     A
        sta     @das_ctr
        cmp     %DAS_DELAY,A
        jc      @dsc_rep                ; C=1 => das_ctr >= DAS_DELAY
        clr     A
        sta     @ok_flag
        rets
dsc_rep:
        mov     %DAS_RATE,A
        sta     @das_ctr
        rets
dsc_new:
        clr     A
        sta     @das_ctr
        rets

; ============================================================================
; GRAVITE
; ============================================================================
do_gravity:
        lda     @landed
        jeq     @dg_fall
        call    @can_fall               ; la piece a pu etre glissee au-dessus
        lda     @ok_flag                ; d'un vide pendant le delai : dans ce
        jeq     @dg_wait                ; cas elle doit repartir, pas se
        clr     A                       ; verrouiller en l'air
        sta     @landed
        br      @dg_fall
dg_wait:
        lda     @lock_ctr
        jeq     @dg_lock
        dec     A
        sta     @lock_ctr
        rets
dg_lock:
        call    @do_lock
        rets
dg_fall:
        lda     @drop_ctr
        jeq     @dg_now
        dec     A
        sta     @drop_ctr
        rets
dg_now:
        lda     @drop_spd
        sta     @drop_ctr
        call    @drop_one
        rets

drop_one:
        clr     A
        sta     @locked
        lda     @cur_x
        sta     @cand_x
        lda     @cur_rot
        sta     @cand_rot
        lda     @cur_y
        inc     A
        sta     @cand_y
        call    @try_move
        lda     @ok_flag
        jne     @do_ok
        mov     %1,A                    ; la piece touche : on arme le delai
        sta     @landed                 ; au lieu de verrouiller tout de suite
        mov     %LOCK_DELAY,A
        sta     @lock_ctr
        rets
do_ok:
        clr     A                       ; elle est repartie vers le bas
        sta     @landed
        sta     @lock_moves
        rets

; la piece peut-elle encore descendre d'une case ?  ok_flag = 1 si oui.
; Ne deplace rien : sert seulement a savoir si le delai de verrouillage
; doit continuer a courir.
can_fall:
        lda     @cur_x
        sta     @try_x
        lda     @cur_rot
        sta     @try_rot
        lda     @cur_y
        inc     A
        sta     @try_y
        call    @calc_cells
        call    @test_cells
        rets

; verrouillage effectif de la piece, puis piece suivante
do_lock:
        call    @lock_piece
        call    @draw_field             ; ecran resynchronise sur field[]
        call    @check_lines
        call    @spawn_piece
        clr     A
        sta     @landed
        sta     @lock_ctr
        sta     @lock_moves
        mov     %1,A
        sta     @locked
        rets

; ============================================================================
; DIAGNOSTIC : affiche en lig 19 col 32 la raison du dernier blocage puis
; l'index field[] teste, en hexa.  1=mur  2=sol  3=case occupee
; A retirer une fois le bug trouve.
; ============================================================================
show_dbg:
        lda     @dbg_lock               ; deja fige ?
        jne     @sd_end
        lda     @cur_y                  ; blocage bas = plausible, on ignore
        cmp     %12,A
        jc      @sd_end
        mov     %1,A                    ; premier blocage HAUT = anomalie
        sta     @dbg_lock
        lda     @atr_ui
        sta     @ATRCAR

        mov     %18,A                   ; lig 18 : raison  cur_y  cur_pc
        sta     @tmp_a
        mov     %32,A
        sta     @tmp_b
        lda     @fail_why
        call    @hex2
        mov     %35,A
        sta     @tmp_b
        lda     @cur_y
        call    @hex2
        mov     %38,A
        sta     @tmp_b
        lda     @cur_pc
        call    @hex2

        ; --- relecture de field[] aux 4 cases que lock_piece vient d'ecrire
        ; on doit y lire cur_pc+1 partout.  Des 00 = l'ecriture n'a pas pris.
        mov     %19,A
        sta     @tmp_a
        mov     %32,A
        sta     @tmp_b
        clr     A
        sta     @tmp_g
        call    @sd_one
        mov     %35,A
        sta     @tmp_b
        mov     %1,A
        sta     @tmp_g
        call    @sd_one
        mov     %20,A
        sta     @tmp_a
        mov     %32,A
        sta     @tmp_b
        mov     %2,A
        sta     @tmp_g
        call    @sd_one
        mov     %35,A
        sta     @tmp_b
        mov     %3,A
        sta     @tmp_g
        call    @sd_one
sd_end: rets

sd_one:                                 ; field[ cellx[tmp_g], celly[tmp_g] ]
        lda     @tmp_g
        mov     A,B
        lda     @cellx(B)
        sta     @tmp_x
        lda     @tmp_g
        mov     A,B
        lda     @celly(B)
        sta     @tmp_y
        call    @fld_index
        lda     @field(B)
        call    @hex2
        rets

; --- affiche A en 2 chiffres hexa en (tmp_a, tmp_b) ------------------------
hex2:
        sta     @tmp_e
        lda     @tmp_b
        mov     A,B
        lda     @tmp_a
        call    @locate
        lda     @tmp_e
        rl      A
        rl      A
        rl      A
        rl      A
        and     %$0F,A
        call    @hexdig
        lda     @tmp_b
        inc     A
        mov     A,B
        lda     @tmp_a
        call    @locate
        lda     @tmp_e
        and     %$0F,A
        call    @hexdig
        rets

; --- DIAG : compteur de gravite, lig 21 col 32 -----------------------------
show_ctr:
        lda     @atr_ui
        sta     @ATRCAR
        mov     %21,A
        sta     @tmp_a
        mov     %32,A
        sta     @tmp_b
        lda     @drop_ctr
        call    @hex2
        rets

hexdig:
        cmp     %10,A
        jnc     @hd_num
        add     %7,A
hd_num: add     %$30,A                  ; code ASCII (chiffre ou A-F)
        call    @to_slot                ; -> slot de notre police (BAGC3) :
                                        ; put_char en ASCII brut tombait sur
                                        ; des cases du logo/des blocs.
        call    @put_char
        rets

; ============================================================================
; DEPLACEMENT TESTE (cand_x / cand_y / cand_rot) -> ok_flag
; ============================================================================
try_move:
        lda     @cand_x
        sta     @try_x
        lda     @cand_y
        sta     @try_y
        lda     @cand_rot
        sta     @try_rot
        call    @calc_cells
        call    @test_cells
        lda     @ok_flag
        jne     @tm_ok
        rets
tm_ok:
        call    @erase_piece            ; efface a l'ancienne position
        lda     @cand_x
        sta     @cur_x
        lda     @cand_y
        sta     @cur_y
        lda     @cand_rot
        sta     @cur_rot
        call    @draw_piece
        lda     @landed                 ; la piece etait posee : le mouvement
        jeq     @tm_end                 ; relance le delai, mais pas
        lda     @lock_moves             ; indefiniment
        cmp     %LOCK_MAX,A
        jc      @tm_end
        inc     A
        sta     @lock_moves
        mov     %LOCK_DELAY,A
        sta     @lock_ctr
tm_end:
        rets

; ============================================================================
; CALCUL DES 4 CASES (cur_pc, try_rot, try_x, try_y) -> cellx[] / celly[]
; index = piece*32 + rot*8 + i*2
; ============================================================================
calc_cells:
        lda     @cur_pc
        rl      A
        rl      A
        rl      A
        rl      A
        rl      A                       ; x32 (max 6*32=192, bit7 jamais perdu)
        sta     @tmp_a
        lda     @try_rot
        and     %3,A
        rl      A
        rl      A
        rl      A                       ; x8
        mov     A,B
        lda     @tmp_a
        add     B,A
        sta     @tmp_a                  ; index de base

        clr     A
        sta     @tmp_b                  ; i = 0
cc_loop:
        lda     @tmp_b
        rl      A                       ; i*2
        mov     A,B
        lda     @tmp_a
        add     B,A
        mov     A,B                     ; B = base + i*2
        lda     @pieces(B)              ; dx
        sta     @tmp_e
        inc     B
        lda     @pieces(B)              ; dy
        sta     @tmp_f

        lda     @try_x                  ; x = try_x + dx
        mov     A,B
        lda     @tmp_e
        add     B,A
        sta     @tmp_g
        lda     @tmp_b
        mov     A,B
        lda     @tmp_g
        sta     @cellx(B)

        lda     @try_y                  ; y = try_y + dy
        mov     A,B
        lda     @tmp_f
        add     B,A
        sta     @tmp_g
        lda     @tmp_b
        mov     A,B
        lda     @tmp_g
        sta     @celly(B)

        lda     @tmp_b
        inc     A
        sta     @tmp_b
        cmp     %4,A
        jne     @cc_loop
        rets

; ============================================================================
; COLLISION sur cellx[]/celly[] -> ok_flag
; Coordonnees non signees : x=-1 devient 255, donc >= FLD_W, rejete.
; ============================================================================
test_cells:
        mov     %1,A
        sta     @ok_flag
        clr     A
        sta     @tmp_b
tc_loop:
        lda     @tmp_b
        mov     A,B
        lda     @cellx(B)
        sta     @tmp_x
        cmp     %FLD_W,A
        jc      @tc_badx                ; x >= 10
        lda     @tmp_b
        mov     A,B
        lda     @celly(B)
        sta     @tmp_y
        cmp     %FLD_H_TOT,A            ; borne haute etendue : la ligne
        jc      @tc_bady                ; cachee (0) est une position valide

        call    @fld_index              ; B = y*10 + x
        mov     B,A
        sta     @fail_idx               ; DIAG
        mov     A,B
        lda     @field(B)
; --- BISECTION : commenter la ligne suivante pour ignorer le contenu du
;     puits. Les pieces ne pourront alors s'arreter que sur le sol.
;       . si elles s'arretent encore en l'air -> le probleme est dans
;         cellx/celly (calc_cells ou la table pieces)
;       . si elles descendent toujours jusqu'au sol -> field[] contient
;         des cases occupees fantomes
        jne     @tc_badf                ; case occupee

        lda     @tmp_b
        inc     A
        sta     @tmp_b
        cmp     %4,A
        jne     @tc_loop
        rets
tc_badx:
        mov     %1,A                    ; DIAG : bute sur un mur
        br      @tc_bad
tc_bady:
        mov     %2,A                    ; DIAG : bute sur le sol
        br      @tc_bad
tc_badf:
        sta     @fail_val               ; DIAG : valeur reellement lue
        mov     %3,A                    ; DIAG : case du puits occupee
tc_bad:
        sta     @fail_why
        clr     A
        sta     @ok_flag
        rets

; --- index dans le puits : B = tmp_y*10 + tmp_x -----------------------------
fld_index:
        lda     @tmp_y
        rl      A                       ; 2y
        sta     @tmp_h
        rl      A                       ; 4y
        rl      A                       ; 8y
        mov     A,B
        lda     @tmp_h
        add     B,A                     ; 10y
        mov     A,B
        lda     @tmp_x
        add     B,A                     ; 10y + x
        mov     A,B
        rets

; ============================================================================
; VERROUILLAGE
; ============================================================================
lock_piece:
        call    @set_try_cur
        call    @calc_cells
        clr     A
        sta     @tmp_b
lp_loop:
        lda     @tmp_b
        mov     A,B
        lda     @cellx(B)
        sta     @tmp_x
        lda     @tmp_b
        mov     A,B
        lda     @celly(B)
        sta     @tmp_y
        call    @fld_index
        lda     @cur_pc
        inc     A                       ; 1..7
        sta     @field(B)
        lda     @tmp_b
        inc     A
        sta     @tmp_b
        cmp     %4,A
        jne     @lp_loop
        rets

set_try_cur:
        lda     @cur_x
        sta     @try_x
        lda     @cur_y
        sta     @try_y
        lda     @cur_rot
        sta     @try_rot
        rets

; ============================================================================
; LIGNES COMPLETES
; ============================================================================
check_lines:
        clr     A
        sta     @nlines
        mov     %FLD_H_TOT-1,A          ; on part du bas, ligne cachee incluse
        sta     @row_ctr
cl_row:
        lda     @row_ctr
        sta     @tmp_y
        clr     A
        sta     @tmp_x
cl_col:
        call    @fld_index
        lda     @field(B)
        jeq     @cl_next                ; un trou : ligne incomplete
        lda     @tmp_x
        inc     A
        sta     @tmp_x
        cmp     %FLD_W,A
        jne     @cl_col

        lda     @nlines                 ; ligne pleine
        inc     A
        sta     @nlines
        call    @flash_row
        call    @remove_row
        br      @cl_row                 ; meme indice : tout a glisse

cl_next:
        lda     @row_ctr
        jeq     @cl_done
        dec     A
        sta     @row_ctr
        br      @cl_row
cl_done:
        lda     @nlines
        jne     @cl_score
        rets
cl_score:
        call    @add_score
        call    @add_lines
        call    @draw_field
        call    @show_score
        call    @show_lines
        call    @show_level
        rets

flash_row:
        lda     @atr_frm
        sta     @tmp_c
        mov     %CH_BLOCK,A
        sta     @blk_l
        sta     @blk_r
        clr     A
        sta     @tmp_x
fr_loop:
        lda     @row_ctr
        sta     @tmp_y
        call    @draw_block
        lda     @tmp_x
        inc     A
        sta     @tmp_x
        cmp     %FLD_W,A
        jne     @fr_loop
        mov     %5,B
fr_wait:
        push    B
        call    @wait_frame
        pop     B
        djnz    B,fr_wait
        rets

remove_row:
        lda     @row_ctr
        sta     @tmp_y
        clr     A
        sta     @tmp_x
        call    @fld_index
        mov     B,A
        add     %FLD_W-1,A
        sta     @tmp_a                  ; index de fin de ligne
rr_loop:
        lda     @tmp_a
        cmp     %FLD_W,A
        jnc     @rr_top                 ; plus rien au-dessus
        sub     %FLD_W,A
        mov     A,B                     ; B = index - 10
        lda     @field(B)
        sta     @tmp_b
        lda     @tmp_a
        mov     A,B
        lda     @tmp_b
        sta     @field(B)
        lda     @tmp_a
        dec     A
        sta     @tmp_a
        br      @rr_loop
rr_top:
        mov     %FLD_W,B                ; ligne 0 videe
rr_clr: dec     B
        clr     A
        sta     @field(B)
        mov     B,A
        jne     @rr_clr
        rets

; ============================================================================
; APPARITION D'UNE PIECE
; ============================================================================
spawn_piece:
        lda     @next_pc
        sta     @cur_pc
        call    @bag_next
        sta     @next_pc
        clr     A
        sta     @cur_rot
        mov     %SPAWN_X,A
        sta     @cur_x
        mov     %SPAWN_Y,A
        sta     @cur_y
        clr     A                       ; delai de verrouillage au repos
        sta     @landed
        sta     @lock_ctr
        sta     @lock_moves
        lda     @drop_spd
        sta     @drop_ctr

        call    @draw_next

        call    @set_try_cur            ; place libre ?
        call    @calc_cells
        call    @test_cells
        lda     @ok_flag
        jne     @sp_ok
        mov     %1,A
        sta     @game_over
        rets
sp_ok:
        call    @draw_piece
        lda     @demo_mode
        jeq     @sp_end
        call    @demo_pick              ; choisit la cible de cette piece
sp_end:
        rets

; --- choisit une rotation et une colonne cibles pour la piece en cours -----
; Pas d'evaluation du terrain : juste une rotation et une colonne au hasard,
; suffisant pour un mode demo qui doit avoir l'air de jouer, pas bien jouer.
; demo_step se charge d'atteindre cette cible sans jamais rester bloque
; (voir DEMO_STUCK_MAX).
demo_pick:
        call    @lfsr
        and     %3,A
        sta     @demo_rot

        ; Mesure le decalage le plus a droite de la piece a CETTE rotation
        ; (calc_cells avec try_x=0 donne directement les dx en cellx[]).
        ; Sans ca, une colonne cible tiree au hasard pouvait pousser la
        ; piece contre le mur, ou la fin de partie ne coincidait pas ---
        ; d'ou l'impression de gauche/droite "pas bonne".
        clr     A
        sta     @try_x
        sta     @try_y
        lda     @demo_rot
        sta     @try_rot
        call    @calc_cells

        lda     @cellx                  ; max de cellx[0..3]
        sta     @tmp_b
        mov     %1,B
dpk_loop:
        lda     @cellx(B)
        cmpa    @tmp_b
        jnc     @dpk_next               ; jnc : A < tmp_b, pas un nouveau max
        sta     @tmp_b
dpk_next:
        inc     B
        mov     B,A
        cmp     %4,A
        jne     @dpk_loop

        ; colonne maxi valide = FLD_W-1 - max_dx (boucle de decomptes : pas
        ; de forme SUB registre-registre eprouvee ailleurs dans ce fichier).
        ; tmp_a = resultat qu'on decremente ; A = compteur d'iterations
        ; restantes (copie de max_dx), qu'on doit preserver via B a chaque
        ; tour puisque lda/dec touchent le meme accumulateur que le calcul.
        mov     %FLD_W-1,A
        sta     @tmp_a                  ; resultat, initialise a FLD_W-1
        lda     @tmp_b                  ; compteur = max_dx
dpk_sub:
        jeq     @dpk_subdone            ; compteur a zero : termine
        dec     A
        mov     A,B                     ; sauvegarde le compteur
        lda     @tmp_a
        dec     A
        sta     @tmp_a
        mov     B,A                     ; recharge le compteur pour la suite
        br      @dpk_sub
dpk_subdone:
        ; tmp_a contient deja FLD_W-1-max_dx : la borne attendue par rnd_mod
        call    @rnd_mod                ; A = alea uniforme dans 0..tmp_a
        sta     @demo_x

        clr     A
        sta     @demo_stuck
        sta     @demo_delay             ; premiere action de cette piece
                                        ; immediate, pas de temps mort
        rets

; --- un pas de jeu automatique : tourne, deplace, puis lache -------------
; Rejoue exactement les memes fonctions que le joueur (try_move, di_rot,
; di_hard) : la demo ne triche pas, elle appuie juste sur les touches
; elle-meme. Si un mouvement echoue plusieurs fois de suite (cible
; inatteignable pour cette piece/rotation), on force la chute plutot que
; de rester bloque indefiniment.
demo_step:
        lda     @cur_rot
        cmpa    @demo_rot
        jeq     @dstep_x
        call    @di_rot
        br      @dstep_check
dstep_x:
        lda     @cur_x
        cmpa    @demo_x
        jeq     @dstep_drop
        jc      @dstep_left             ; jc : cur_x > demo_x (pas egal, deja teste)
        lda     @cur_x
        inc     A
        sta     @cand_x
        br      @dstep_move
dstep_left:
        lda     @cur_x
        dec     A
        sta     @cand_x
dstep_move:
        lda     @cur_y
        sta     @cand_y
        lda     @cur_rot
        sta     @cand_rot
        call    @try_move
        br      @dstep_check
dstep_drop:
        call    @di_hard
        clr     A
        sta     @demo_stuck
        rets
dstep_check:
        lda     @ok_flag
        jne     @dstep_ok
        lda     @demo_stuck             ; ce mouvement a echoue
        inc     A
        sta     @demo_stuck
        cmp     %DEMO_STUCK_MAX,A
        jc      @dstep_force            ; jc : trop d'echecs, on force
        rets
dstep_force:
        call    @di_hard
        clr     A
        sta     @demo_stuck
        rets
dstep_ok:
        clr     A
        sta     @demo_stuck
        rets

; ============================================================================
; ALEATOIRE : LFSR de Galois 8 bits, resultat 0..6 dans A
; ============================================================================
; SAC DE SEPT
; Les sept pieces sont tirees sans remise : chacune sort une fois par groupe
; de sept, dans un ordre melange. Le tirage purement aleatoire precedent
; pouvait faire attendre la barre quinze pieces d'affilee.
;
; A = alea uniforme dans 0..tmp_a (tmp_a <= 6)
rnd_mod:
        call    @lfsr
        and     %7,A
        cmpa    @tmp_a
        jeq     @rm_ok
        jc      @rnd_mod                ; > tmp_a : on retire
rm_ok:  rets

; remplit le sac avec 0..6 puis le melange (Fisher-Yates)
bag_fill:
        clr     A
        sta     @tmp_a
bf_init:
        lda     @tmp_a
        mov     A,B
        lda     @tmp_a
        sta     @bag(B)
        lda     @tmp_a
        inc     A
        sta     @tmp_a
        cmp     %7,A
        jne     @bf_init

        mov     %6,A                    ; pour i de 6 a 1 : echanger avec un
        sta     @tmp_a                  ; rang tire dans 0..i
bf_mix:
        call    @rnd_mod
        sta     @tmp_b                  ; j
        lda     @tmp_a
        mov     A,B
        lda     @bag(B)
        sta     @tmp_c                  ; bag[i]
        lda     @tmp_b
        mov     A,B
        lda     @bag(B)
        sta     @tmp_e                  ; bag[j]
        lda     @tmp_a
        mov     A,B
        lda     @tmp_e
        sta     @bag(B)
        lda     @tmp_b
        mov     A,B
        lda     @tmp_c
        sta     @bag(B)
        lda     @tmp_a
        dec     A
        sta     @tmp_a
        jne     @bf_mix

        clr     A
        sta     @bag_i
        rets

; tire la piece suivante du sac, en le remplissant s'il est vide
bag_next:
        lda     @bag_i
        cmp     %7,A
        jnc     @bn_ok
        call    @bag_fill
bn_ok:
        lda     @bag_i
        mov     A,B
        lda     @bag(B)
        sta     @tmp_h
        lda     @bag_i
        inc     A
        sta     @bag_i
        lda     @tmp_h
        rets

; LFSR de Galois 16 bits, polynome $002D, periode 65535.
; L'ancienne version 8 bits utilisait une ROTATION : sa periode reelle etait
; de 32 et ses 3 bits de poids faible ne prenaient que les valeurs 0 et 4,
; d'ou uniquement des pieces I et Z. On utilise ici l'octet de poids fort.
; Sortie : A = rng_hi
lfsr:
        lda     @rng_hi                 ; bit 15 : faut-il la retroaction ?
        and     %$80,A
        sta     @lf_t1
        lda     @rng_lo                 ; bit 7 de lo : entrera dans hi
        and     %$80,A
        sta     @lf_t2

        lda     @rng_lo                 ; lo << 1  (rl puis on force bit0 a 0)
        rl      A
        and     %$FE,A
        sta     @rng_lo

        lda     @rng_hi                 ; hi << 1
        rl      A
        and     %$FE,A
        sta     @lf_t3
        lda     @lf_t2                  ; injection du bit venu de lo
        jeq     @lf_nb
        lda     @lf_t3
        or      %$01,A
        sta     @lf_t3
lf_nb:
        lda     @lf_t3
        sta     @rng_hi

        lda     @lf_t1                  ; retroaction polynome $002D
        jeq     @lf_no
        lda     @rng_lo
        xor     %$2D,A
        sta     @rng_lo
lf_no:
        lda     @rng_hi                 ; etat nul impossible, on se protege
        jne     @lf_ok
        lda     @rng_lo
        jne     @lf_ok
        mov     %$AC,A
        sta     @rng_hi
        mov     %$E1,A
        sta     @rng_lo
lf_ok:
        lda     @rng_hi
        rets

; ============================================================================
; AFFICHAGE DE LA PIECE
; ============================================================================
draw_piece:
        call    @set_try_cur
        call    @calc_cells
        lda     @cur_pc
        mov     A,B
        lda     @pc_color(B)
        sta     @tmp_c
        lda     @cur_pc
        cmp     %7,A                    ; piece hors table ?
        jc      @dp_bad
        mov     A,B
        mov     %CH_BLOCK,A             ; pave plein (video inverse)
        sta     @blk_l
        sta     @blk_r
        br      @draw_cells
dp_bad:
        lda     @atr_ui
        sta     @tmp_c
        mov     %$3F,A                  ; '?' : piece illegale, visible
        sta     @blk_l
        sta     @blk_r
        br      @draw_cells

erase_piece:
        call    @set_try_cur
        call    @calc_cells
        mov     %ATR_EMPTY,A
        sta     @tmp_c
        mov     %CH_BLANK,A
        sta     @blk_l
        sta     @blk_r
        ; tombe dans draw_cells

draw_cells:
        clr     A
        sta     @tmp_g
dc_loop:
        lda     @tmp_g
        mov     A,B
        lda     @cellx(B)
        sta     @tmp_x
        lda     @tmp_g
        mov     A,B
        lda     @celly(B)
        sta     @tmp_y
        call    @draw_block
        lda     @tmp_g
        inc     A
        sta     @tmp_g
        cmp     %4,A
        jne     @dc_loop
        rets

; --- une case du puits = UNE cellule texte (8x10 px) ------------------------
; entrees : tmp_x, tmp_y (coord puits), tmp_c (attribut), blk_l
draw_block:
        lda     @tmp_x                  ; garde-fou : une case hors du puits
        cmp     %FLD_W,A                ; ne doit JAMAIS etre dessinee
        jc      @db_out
        lda     @tmp_y
        cmp     %BUF_H,A                ; ligne cachee (0) : jamais dessinee,
        jnc     @db_out                 ; elle n'a pas de position ecran
                                        ; (jc = "A >= operande" : il fallait
                                        ; jnc pour "A < BUF_H", pas jc)
        cmp     %FLD_H_TOT,A
        jc      @db_out                 ; hors du puits etendu : invalide
        lda     @tmp_c
        sta     @ATRCAR
        lda     @tmp_x
        add     %FLD_COL,A
        mov     A,B                     ; B = colonne texte
        lda     @tmp_y
        sub     %BUF_H,A                ; ligne VISIBLE : la cachee est retiree
        add     %FLD_ROW,A              ; A = ligne texte
        call    @locate
        lda     @blk_l
        call    @put_char
db_out: rets

draw_field:
        clr     A
        sta     @tmp_y
df_row:
        clr     A
        sta     @tmp_x
df_col:
        call    @fld_index
        lda     @field(B)
        jne     @df_full
        mov     %ATR_EMPTY,A
        sta     @tmp_c
        mov     %CH_BLANK,A
        sta     @blk_l
        sta     @blk_r
        br      @df_draw
df_full:
        dec     A                       ; 1..7 -> 0..6
        sta     @tmp_a
        cmp     %7,A                    ; hors table ? pc_char n'a que 7
        jc      @df_bad                 ; entrees : au-dela on lisait des
        mov     A,B                     ; caracteres de controle INVISIBLES
        lda     @pc_color(B)
        sta     @tmp_c
        mov     %CH_BLOCK,A             ; pave plein, comme la piece en vol
        sta     @blk_l
        sta     @blk_r
        br      @df_draw
df_bad:
        lda     @atr_ui
        sta     @tmp_c
        mov     %$3F,A                  ; '?' : case occupee par une valeur
        sta     @blk_l                  ; illegale, jusqu'ici invisible
        sta     @blk_r
df_draw:
        call    @draw_block
        lda     @tmp_x
        inc     A
        sta     @tmp_x
        cmp     %FLD_W,A
        jne     @df_col
        lda     @tmp_y
        inc     A
        sta     @tmp_y
        cmp     %FLD_H_TOT,A            ; parcourt aussi la ligne cachee : sans
        jne     @df_row                 ; cela la derniere ligne visible (la
        rets                            ; 21e du tableau) n'etait jamais lue

; ============================================================================
; APERCU DE LA PIECE SUIVANTE
; ============================================================================
draw_next:
        mov     %ATR_EMPTY,A            ; efface la zone 4 lignes x 8 colonnes
        sta     @ATRCAR
        clr     A
        sta     @tmp_a
dn_clr_r:
        clr     A
        sta     @tmp_b
dn_clr_c:
        lda     @tmp_b
        add     %PRV_COL,A
        mov     A,B
        lda     @tmp_a
        add     %PRV_ROW,A
        call    @locate
        mov     %CH_BLANK,A
        call    @put_char
        lda     @tmp_b
        inc     A
        sta     @tmp_b
        cmp     %4,A
        jne     @dn_clr_c
        lda     @tmp_a
        inc     A
        sta     @tmp_a
        cmp     %4,A
        jne     @dn_clr_r

        lda     @next_pc                ; index table = piece*32, rotation 0
        rl      A
        rl      A
        rl      A
        rl      A
        rl      A
        sta     @tmp_a
        lda     @next_pc
        mov     A,B
        lda     @pc_color(B)
        sta     @ATRCAR
        mov     %CH_BLOCK,A
        sta     @blk_l
        sta     @blk_r
        clr     A
        sta     @tmp_b                  ; i = 0
dn_loop:
        lda     @tmp_b
        rl      A
        mov     A,B
        lda     @tmp_a
        add     B,A
        mov     A,B
        lda     @pieces(B)              ; dx
        add     %PRV_COL,A
        sta     @tmp_e
        lda     @tmp_b
        rl      A
        mov     A,B
        lda     @tmp_a
        add     B,A
        inc     A
        mov     A,B
        lda     @pieces(B)              ; dy
        add     %PRV_ROW,A
        sta     @tmp_f

        lda     @tmp_e
        mov     A,B
        lda     @tmp_f
        call    @locate
        lda     @blk_l
        call    @put_char

        lda     @tmp_b
        inc     A
        sta     @tmp_b
        cmp     %4,A
        jne     @dn_loop
        rets

; ============================================================================
; SCORE / LIGNES / NIVEAU
; ============================================================================
add_point:                              ; +1 point
        mov     %5,A
        sta     @tmp_a                  ; chiffre courant (5 = unites)
        mov     %1,A
        sta     @tmp_e                  ; report a propager
ap_loop:
        lda     @tmp_a
        mov     A,B
        lda     @score_dig(B)
        mov     A,B
        lda     @tmp_e
        add     B,A                     ; chiffre + report
        clr     B
        cmp     %10,A
        jnc     @ap_store
        sub     %10,A
        mov     %1,B
ap_store:
        sta     @tmp_f
        mov     B,A
        sta     @tmp_e
        lda     @tmp_a
        mov     A,B
        lda     @tmp_f
        sta     @score_dig(B)
        lda     @tmp_e
        jeq     @ap_done
        lda     @tmp_a
        jeq     @ap_done
        dec     A
        sta     @tmp_a
        br      @ap_loop
ap_done:
        call    @show_score
        rets

; --- (40 / 100 / 300 / 1200) x (niveau+1) -----------------------------------
add_score:
        lda     @nlines
        dec     A
        and     %3,A
        mov     A,B
        lda     @mul6(B)
        sta     @tmp_a                  ; offset dans sc_base
        lda     @level
        inc     A
        sta     @tmp_b                  ; nombre de repetitions
as_rep:
        mov     %5,A
        sta     @tmp_g                  ; chiffre courant
        clr     A
        sta     @tmp_e                  ; report
as_dig:
        lda     @tmp_g                  ; sc_base[base + i]
        mov     A,B
        lda     @tmp_a
        add     B,A
        mov     A,B
        lda     @sc_base(B)
        sta     @tmp_h

        lda     @tmp_g                  ; score_dig[i]
        mov     A,B
        lda     @score_dig(B)
        sta     @tmp_f

        lda     @tmp_h
        mov     A,B
        lda     @tmp_e
        add     B,A                     ; addend + report
        mov     A,B
        lda     @tmp_f
        add     B,A                     ; + chiffre
        clr     B
        cmp     %10,A
        jnc     @as_store
        sub     %10,A
        mov     %1,B
as_store:
        sta     @tmp_f
        mov     B,A
        sta     @tmp_e
        lda     @tmp_g
        mov     A,B
        lda     @tmp_f
        sta     @score_dig(B)

        lda     @tmp_g
        jeq     @as_rep_end
        dec     A
        sta     @tmp_g
        br      @as_dig
as_rep_end:
        lda     @tmp_b
        dec     A
        sta     @tmp_b
        jne     @as_rep
        rets

add_lines:
        lda     @nlines
        sta     @tmp_a
al_one:
        mov     %2,A
        sta     @tmp_g
        mov     %1,A
        sta     @tmp_e
al_dig:
        lda     @tmp_g
        mov     A,B
        lda     @lines_dig(B)
        mov     A,B
        lda     @tmp_e
        add     B,A
        clr     B
        cmp     %10,A
        jnc     @al_store
        sub     %10,A
        mov     %1,B
al_store:
        sta     @tmp_f
        mov     B,A
        sta     @tmp_e
        lda     @tmp_g
        mov     A,B
        lda     @tmp_f
        sta     @lines_dig(B)
        lda     @tmp_e
        jeq     @al_lvl
        lda     @tmp_g
        jeq     @al_lvl
        dec     A
        sta     @tmp_g
        br      @al_dig
al_lvl:
        lda     @lvl_ctr                ; 10 lignes -> niveau suivant
        inc     A
        sta     @lvl_ctr
        cmp     %10,A
        jnc     @al_next
        clr     A
        sta     @lvl_ctr
        lda     @level
        cmp     %19,A
        jc      @al_next                ; deja au maximum
        inc     A
        sta     @level
        call    @set_speed
al_next:
        lda     @tmp_a
        dec     A
        sta     @tmp_a
        jne     @al_one
        rets

set_speed:
        lda     @level
        cmp     %20,A
        jnc     @ss_ok
        mov     %19,A
ss_ok:  mov     A,B
        lda     @speed_tbl(B)
        sta     @drop_spd
        rets

show_score:
        lda     @atr_ui
        sta     @ATRCAR
        clr     A
        sta     @tmp_a
ss_loop:
        lda     @tmp_a
        add     %PAN_COL,A
        mov     A,B
        mov     %2,A                    ; ligne 2, colonnes 32..37
        call    @locate
        lda     @tmp_a
        mov     A,B
        lda     @score_dig(B)
        add     %$30,A
        call    @to_slot        ; chiffre -> slot de notre police
        call    @put_char
        lda     @tmp_a
        inc     A
        sta     @tmp_a
        cmp     %6,A
        jne     @ss_loop
        rets

show_lines:
        lda     @atr_ui
        sta     @ATRCAR
        clr     A
        sta     @tmp_a
sl_loop:
        lda     @tmp_a
        add     %PAN_COL,A
        mov     A,B
        mov     %8,A                    ; ligne 8, colonnes 32..34
        call    @locate
        lda     @tmp_a
        mov     A,B
        lda     @lines_dig(B)
        add     %$30,A
        call    @to_slot        ; chiffre -> slot de notre police
        call    @put_char
        lda     @tmp_a
        inc     A
        sta     @tmp_a
        cmp     %3,A
        jne     @sl_loop
        rets

show_level:
        lda     @atr_ui
        sta     @ATRCAR
        lda     @level
        clr     B
        cmp     %10,A
        jnc     @svl_un
        sub     %10,A
        mov     %1,B
svl_un:
        sta     @tmp_a                  ; unites
        mov     B,A
        sta     @tmp_b                  ; dizaines
        mov     %PAN_COL,B
        mov     %5,A
        call    @locate
        lda     @tmp_b
        add     %$30,A
        call    @to_slot        ; chiffre -> slot de notre police
        call    @put_char
        mov     %PAN_COL+1,B
        mov     %5,A
        call    @locate
        lda     @tmp_a
        add     %$30,A
        call    @to_slot        ; chiffre -> slot de notre police
        call    @put_char
        rets

; ============================================================================
; DECOR FIXE
; ============================================================================
draw_static:
        ; --- cadre du puits, en trait simple ---
        lda     @atr_frm
        sta     @ATRCAR
        clr     A
        sta     @tmp_a                  ; traits horizontaux haut et bas
ds_top:
        lda     @tmp_a
        add     %FLD_COL,A
        mov     A,B
        mov     %FLD_ROW-1,A
        call    @locate
        mov     %CH_HZ,A
        call    @put_char
        lda     @tmp_a
        add     %FLD_COL,A
        mov     A,B
        mov     %FLD_ROW+FLD_H,A
        call    @locate
        mov     %CH_HZ,A
        call    @put_char
        lda     @tmp_a
        inc     A
        sta     @tmp_a
        cmp     %FLD_W,A
        jne     @ds_top

        clr     A                       ; montants verticaux
        sta     @tmp_a
ds_side:
        mov     %FLD_COL-1,B
        lda     @tmp_a
        add     %FLD_ROW,A
        call    @locate
        mov     %CH_VT,A
        call    @put_char
        mov     %25,B
        lda     @tmp_a
        add     %FLD_ROW,A
        call    @locate
        mov     %CH_VT,A
        call    @put_char
        lda     @tmp_a
        inc     A
        sta     @tmp_a
        cmp     %FLD_H,A
        jne     @ds_side

        mov     %FLD_COL-1,B            ; les quatre coins
        mov     %FLD_ROW-1,A
        call    @locate
        mov     %CH_TL,A
        call    @put_char
        mov     %25,B
        mov     %FLD_ROW-1,A
        call    @locate
        mov     %CH_TR,A
        call    @put_char
        mov     %FLD_COL-1,B
        mov     %FLD_ROW+FLD_H,A
        call    @locate
        mov     %CH_BL,A
        call    @put_char
        mov     %25,B
        mov     %FLD_ROW+FLD_H,A
        call    @locate
        mov     %CH_BR,A
        call    @put_char

        ; --- panneau droit, colonne 32 (libelles de 5 a 7 caracteres) ---
        lda     @atr_ui
        sta     @ATRCAR
        mov     %1,A               ; lig 1 : Score:
        sta     @ps_row
        mov     %29,A
        sta     @ps_col
        movd    %s_score_e-1,R1
        sta     @ps_hi
        mov     B,A
        sta     @ps_lo
        call    @put_str
        mov     %4,A               ; lig 4 : Niveau:
        sta     @ps_row
        mov     %29,A
        sta     @ps_col
        movd    %s_level_e-1,R1
        sta     @ps_hi
        mov     B,A
        sta     @ps_lo
        call    @put_str
        mov     %7,A               ; lig 7 : Lignes:
        sta     @ps_row
        mov     %29,A
        sta     @ps_col
        movd    %s_lines_e-1,R1
        sta     @ps_hi
        mov     B,A
        sta     @ps_lo
        call    @put_str
        mov     %10,A               ; lig 10 : Suivant:
        sta     @ps_row
        mov     %29,A
        sta     @ps_col
        movd    %s_next_e-1,R1
        sta     @ps_hi
        mov     B,A
        sta     @ps_lo
        call    @put_str

        ; --- rappel des options, en bas a droite ---
        mov     %19,A               ; lig 19 col 30
        sta     @ps_row
        mov     %30,A
        sta     @ps_col
        movd    %s_ktheme_e-1,R1
        sta     @ps_hi
        mov     B,A
        sta     @ps_lo
        call    @put_str
        mov     %20,A               ; lig 20 col 30
        sta     @ps_row
        mov     %30,A
        sta     @ps_col
        movd    %s_opt_e-1,R1
        sta     @ps_hi
        mov     B,A
        sta     @ps_lo
        call    @put_str
        mov     %21,A               ; lig 21 col 30
        sta     @ps_row
        mov     %30,A
        sta     @ps_col
        movd    %s_kpause_e-1,R1
        sta     @ps_hi
        mov     B,A
        sta     @ps_lo
        call    @put_str
        mov     %22,A               ; lig 22 col 30
        sta     @ps_row
        mov     %30,A
        sta     @ps_col
        movd    %s_kmusic_e-1,R1
        sta     @ps_hi
        mov     B,A
        sta     @ps_lo
        call    @put_str

        call    @draw_sub               ; morceau de l'image, a gauche
        rets

; --- efface les 40x25 cellules avec NOTRE glyphe vide ----------------------
; set_window remplit l'ecran de caracteres $20. Sur machine reelle ce code
; s'affiche (glyphe parasite en barres), au lieu d'etre traite en simple
; delimiteur de zone. On repasse donc derriere avec CH_BLANK ($37 de BAGC3),
; dont on sait qu'il est bien vide : c'est celui des cases du puits.
clear_all:
        mov     %ATR_EMPTY,A
        sta     @ATRCAR
        clr     A
        sta     @tmp_a
ca_row:
        clr     A
        sta     @tmp_b
ca_col:
        lda     @tmp_b
        mov     A,B
        lda     @tmp_a
        call    @locate
        mov     %CH_BLANK,A
        call    @put_char
        lda     @tmp_b
        inc     A
        sta     @tmp_b
        cmp     %40,A
        jne     @ca_col
        lda     @tmp_a
        inc     A
        sta     @tmp_a
        cmp     %25,A
        jne     @ca_row
        rets

; --- ecrit une chaine inversee caractere par caractere ---------------------
; Necessaire pour les chaines contenant des ESPACES. Le code $20 est un
; delimiteur de zone (manuel 4.2.4) : sur ce caractere les bits 4-3 de
; l'attribut ne designent plus le generateur mais MSK et INC. Un espace
; ecrit avec l'attribut du texte ($10 = BAGC1) armait donc MSK, dont l'effet
; est d'afficher en espaces toute la fin de la ligne. On donne aux espaces
; un attribut nul : ni masquage, ni incrustation, fond noir.
; Entrees : ps_row, ps_col, ps_hi:ps_lo (dernier caractere), atr_ui.
; ASCII -> slot de notre police. Hors table, on rend le glyphe vide.
to_slot:
        cmp     %$20,A
        jne     @tsl_d
        mov     %CH_BLANK,A
        rets
tsl_d:  cmp     %$3A,A                  ; ':'
        jne     @tsl_d2
        mov     %$7E,A
        rets
tsl_d2: cmp     %$30,A
        jnc     @tsl_bad
        cmp     %$3A,A
        jc      @tsl_maj
        sub     %$30,A                  ; chiffre -> $40+
        add     %$40,A
        rets
tsl_maj:
        cmp     %$41,A
        jnc     @tsl_bad
        cmp     %$5B,A
        jc      @tsl_min
        sub     %$41,A                  ; majuscule -> $4A+
        add     %$4A,A
        rets
tsl_min:
        cmp     %$61,A
        jnc     @tsl_bad
        cmp     %$7B,A
        jc      @tsl_bad
        sub     %$61,A                  ; minuscule -> $64+
        add     %$64,A
        rets
tsl_bad:
        mov     %CH_BLANK,A
        rets

put_str:
ps_loop:
        lda     @ps_hi
        mov     A,TEMP1-1
        lda     @ps_lo
        mov     A,TEMP1
        lda     *TEMP1
        jeq     @ps_end                 ; 0 en tete : fin de chaine
        sta     @ps_ch
        call    @to_slot
        sta     @ps_ch
        lda     @atr_ui
ps_set:
        sta     @ATRCAR
        lda     @ps_col
        mov     A,B
        lda     @ps_row
        call    @locate
        lda     @ps_ch
        call    @put_char
        lda     @ps_col
        inc     A
        sta     @ps_col
        lda     @ps_lo                  ; pointeur - 1
        jne     @ps_dec
        lda     @ps_hi
        dec     A
        sta     @ps_hi
ps_dec:
        lda     @ps_lo
        dec     A
        sta     @ps_lo
        br      @ps_loop
ps_end:
        rets

; --- efface les deux lignes de message (a l'interieur du puits) -------------
clear_msg:
        mov     %ATR_EMPTY,A
        sta     @ATRCAR
        clr     A
        sta     @tmp_a
cm_loop:
        lda     @tmp_a
        mov     A,B
        mov     %MSG_ROW,A
        call    @locate
        mov     %CH_BLANK,A
        call    @put_char
        lda     @tmp_a
        mov     A,B
        mov     %MSG_ROW2,A
        call    @locate
        mov     %CH_BLANK,A
        call    @put_char
        lda     @tmp_a
        inc     A
        sta     @tmp_a
        cmp     %30,A                   ; on s'arrete avant l'indicateur (O)
        jne     @cm_loop
        rets

; ============================================================================
; FIN DE PARTIE
; ============================================================================
over_screen:
        call    @music_stop
        call    @clear_msg              ; enleve un eventuel PAUSE residuel
        lda     @atr_ui
        sta     @ATRCAR
        mov     %23,A                    ; lig 23 col 14 : Partie finie
        sta     @ps_row
        mov     %14,A
        sta     @ps_col
        movd    %s_over_e-1,R1
        sta     @ps_hi
        mov     B,A
        sta     @ps_lo
        call    @put_str
        lda     @atr_ui
        sta     @ATRCAR
        mov     %24,A                    ; lig 24 col 11 : Appuyez sur espace
        sta     @ps_row
        mov     %11,A
        sta     @ps_col
        movd    %s_press_e-1,R1
        sta     @ps_hi
        mov     B,A
        sta     @ps_lo
        call    @put_str
        call    @wait_release
os_wait:
        call    @wait_frame
        mov     VALUE0,A
        cmp     %$20,A
        jne     @os_wait
        rets

; ============================================================================
; TEMPORISATION ~20 ms (a recalibrer)
; ============================================================================
wait_frame:
        push    A
        push    B
        mov     %VD_OUTER,A
wf_out:
        clr     B                       ; 256 iterations
wf_in:  djnz    B,wf_in
        dec     A
        jne     @wf_out
        pop     B
        pop     A
        rets

; ============================================================================
; TABLES
; ============================================================================
; --- couleurs des pieces : I O T S Z J L ------------------------------------
; Les attributs de couleur ne se comportent pas comme suppose : certaines
; valeurs s'affichent (I=$30, T=$28, L=$38, mur=$20) et d'autres rendent la
; case INVISIBLE (Z=$08 notamment).  Une piece invisible tombe, se verrouille
; dans field[] et bloque les suivantes : c'est la cause des pieces "en l'air"
; et de l'impression de ne recevoir que des barres.
; En attendant de connaitre le vrai format d'attribut (mixt_api / 3556.equ),
; toutes les pieces utilisent l'attribut du texte, qui lui s'affiche.
; Les pieces restent distinguables par leur lettre.
; fond colore + espace = pave plein, une couleur par piece
pc_color:
        .byte   FG_CYAN|CG_BLK             ; I
        .byte   FG_YELLOW|CG_BLK           ; O
        .byte   FG_MAGENTA|CG_BLK          ; T
        .byte   FG_GREEN|CG_BLK            ; S
        .byte   FG_RED|CG_BLK              ; Z
        .byte   FG_BLUE|CG_BLK             ; J
        .byte   FG_WHITE|CG_BLK            ; L

; --- lettre affichee pour chaque piece : I O T S Z J L ----------------------
pc_char:
        .byte   $49,$4F,$54,$53,$5A,$4A,$4C     ; I O T S Z J L

; --- libelles de l'ecran de redefinition, dans l'ordre de k_left..k_drop ---
opt_hi: .byte   s_o1_e-1>>8,s_o2_e-1>>8,s_o3_e-1>>8,s_o4_e-1>>8,s_o5_e-1>>8
opt_lo: .byte   s_o1_e-1&$FF,s_o2_e-1&$FF,s_o3_e-1&$FF,s_o4_e-1&$FF,s_o5_e-1&$FF

; --- couleurs du decor, parcourues par la touche T --------------------------
theme_tbl:
        .byte   FG_RED,FG_CYAN,FG_GREEN,FG_YELLOW
        .byte   FG_BLUE,FG_MAGENTA,FG_WHITE
; les memes couleurs en index 0-7, pour le champ "fond" des attributs
theme_bgt:
        .byte   1,6,2,3,4,5,7

; --- vitesse de chute : frames par case, indexee par niveau 0..19 -----------
; frames par case. A ~20 ms la frame, le niveau 0 fait ~1 s par case,
; ce qui est la vitesse du Tetris d'origine. Si c'est encore trop rapide,
; augmenter les premieres valeurs ou VD_OUTER.
speed_tbl:
        .byte   120,105,92,80,68,56,45,34,24,18
        .byte   15,13,12,11,10,9,8,7,6,5

mul6:   .byte   0,6,12,18

sc_base:
        .byte   0,0,0,0,4,0             ; 1 ligne  ->   40
        .byte   0,0,0,1,0,0             ; 2 lignes ->  100
        .byte   0,0,0,3,0,0             ; 3 lignes ->  300
        .byte   0,0,1,2,0,0             ; 4 lignes -> 1200

; ============================================================================
; MOTIFS DES BLOCS  -  14 caracteres de CHAR_BYTES octets
; Un bloc = 2 cellules cote a cote : moitie gauche puis moitie droite.
; bit 7 = pixel le plus a gauche. La premiere et la derniere ligne forment
; le liseré horizontal, bit7 (gauche) et bit0 (droite) le liseré vertical.
; ----------------------------------------------------------------------------
; ============================================================================
; TETROMINOS
; 7 pieces x 4 rotations x 4 cases x (dx,dy), boite 4x4, coordonnees 0..3.
; Rotation horaire obtenue par (x,y) -> (2-y,x) dans la boite 3x3
; (4x4 pour le I), systeme Nintendo, verifiee rotation par rotation.
; ============================================================================
pieces:
; --- 0 : I ------------------------------------------------------------------
        .byte   0,1, 1,1, 2,1, 3,1      ; ....  XXXX  ....  ....
        .byte   2,0, 2,1, 2,2, 2,3      ; ..X.  ..X.  ..X.  ..X.
        .byte   0,1, 1,1, 2,1, 3,1
        .byte   2,0, 2,1, 2,2, 2,3
; --- 1 : O ------------------------------------------------------------------
        .byte   1,0, 2,0, 1,1, 2,1      ; .XX.  .XX.
        .byte   1,0, 2,0, 1,1, 2,1
        .byte   1,0, 2,0, 1,1, 2,1
        .byte   1,0, 2,0, 1,1, 2,1
; --- 2 : T ------------------------------------------------------------------
        .byte   0,0, 1,0, 2,0, 1,1      ; XXX / .X.
        .byte   2,0, 2,1, 2,2, 1,1      ; ..X / .XX / ..X
        .byte   0,2, 1,2, 2,2, 1,1      ; .X. / XXX
        .byte   0,0, 0,1, 0,2, 1,1      ; X.. / XX. / X..
; --- 3 : S ------------------------------------------------------------------
        .byte   1,0, 2,0, 0,1, 1,1      ; .XX / XX.
        .byte   1,0, 1,1, 2,1, 2,2      ; .X. / .XX / ..X
        .byte   1,1, 2,1, 0,2, 1,2      ; .XX / XX.
        .byte   0,0, 0,1, 1,1, 1,2      ; X.. / XX. / .X.
; --- 4 : Z ------------------------------------------------------------------
        .byte   0,0, 1,0, 1,1, 2,1      ; XX. / .XX
        .byte   2,0, 1,1, 2,1, 1,2      ; ..X / .XX / .X.
        .byte   0,1, 1,1, 1,2, 2,2      ; XX. / .XX
        .byte   1,0, 0,1, 1,1, 0,2      ; .X. / XX. / X..
; --- 5 : J ------------------------------------------------------------------
        .byte   0,0, 0,1, 1,1, 2,1      ; X.. / XXX
        .byte   1,0, 2,0, 1,1, 1,2      ; .XX / .X. / .X.
        .byte   0,1, 1,1, 2,1, 2,2      ; XXX / ..X
        .byte   1,0, 1,1, 0,2, 1,2      ; .X. / .X. / XX.
; --- 6 : L ------------------------------------------------------------------
        .byte   2,0, 0,1, 1,1, 2,1      ; ..X / XXX
        .byte   1,0, 1,1, 1,2, 2,2      ; .X. / .X. / .XX
        .byte   0,1, 1,1, 2,1, 0,2      ; XXX / X..
        .byte   0,0, 1,0, 1,1, 1,2      ; XX. / .X. / .X.

; ============================================================================
; TEXTES  -  convention Exelvision : chaines INVERSEES, 0 en tete
; Longueurs verifiees pour la mise en page ci-dessus.
; ============================================================================
s_title:        .byte   0,"SIRTLEXE"            ; EXELTRIS      8 car, col 16
s_title_e:
s_score:        .byte   0,":erocS"               ; Score:        6 car
s_score_e:
s_level:        .byte   0,":uaeviN"              ; Niveau:       7 car
s_level_e:
s_lines:        .byte   0,":sengiL"              ; Lignes:       7 car
s_lines_e:
s_next:         .byte   0,":tnaviuS"             ; Suivant:      8 car
s_next_e:
s_press:        .byte   0,"ecapse rus zeyuppA"   ; Appuyez sur espace  18 car
s_press_e:
s_pause:        .byte   0,"esuaP"                ; Pause         5 car
s_pause_e:
s_over:         .byte   0,"einif eitraP"         ; Partie finie 12 car
s_over_e:
s_slvl:         .byte   0," :traped uaeviN"      ; "Niveau depart: " 15 car (espace incl.)
s_slvl_e:
s_demo:         .byte   0,"omeD"                       ; "Demo"          4 car
s_demo_e:
; Pas d'accent : $E8 n'est pas un e accent grave mais un code d'attribut
; (clignotement), il transformait le "h" suivant en caractere clignotant.
s_ktheme:       .byte   0,"emehT:T"              ; T:Theme       7 car
s_ktheme_e:
s_opt:          .byte   0,"snoitpO:O"            ; O:Options     9 car
s_opt_e:
s_kpause:       .byte   0,"esuaP:P"              ; P:Pause       7 car
s_kpause_e:
s_kmusic:       .byte   0,"euqisuM:M"            ; M:Musique     9 car
s_kmusic_e:
s_redef:        .byte   0,"sehcuot sed noitinifedeR" ; Redefinition des touches
s_redef_e:
s_hitkey:       .byte   0,"ehcuot al rus zeyuppA" ; Appuyez sur la touche
s_hitkey_e:
s_o1:           .byte   0,"ehcuaG"               ; Gauche
s_o1_e:
s_o2:           .byte   0,"etiorD"               ; Droite
s_o2_e:
s_o3:           .byte   0,"etnecseD"             ; Descente
s_o3_e:
s_o4:           .byte   0,"noitatoR"             ; Rotation
s_o4_e:
s_o5:           .byte   0,"etuhC"                ; Chute
s_o5_e:

; --- donnees obligatoires pour l'init MIXT MODE (25 octets, un par ligne) ---
screen_data1    .byte $00,$18,$18,$18,$18,$18,$18,$18,$18,$18,$18,$18,$18
                .byte $18,$18,$18,$18,$18,$18,$18,$18,$18,$18,$18,$00
screen_data2    .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
                .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00

; ============================================================================
; MUSIQUE : "Korobeiniki", chanson populaire russe de 1861 (poeme de
; Nekrasov, premieres editions musicales 1898). La MELODIE est dans le
; domaine public. C'est bien la chanson traditionnelle qui est transcrite
; ici -- ligne melodique seule, sans harmonie ni basse -- et non
; l'arrangement de 1989 pour Game Boy, lui protege.
;
; Format de INTmusic.asm : la partition se lit en DECREMENTANT l'adresse,
; donc elle est ecrite a l'envers. Chaque evenement occupe 3 octets, dans
; l'ordre croissant des adresses : duree(poids fort), duree(poids faible),
; note. L'octet 0 en tete marque la fin de lecture. Index 1 = silence,
; index note = numero MIDI - 12 (index 48 = DO4 = 261,6 Hz, verifie sur
; les tables du timer).
;
; La duree se compte en tics du timer, et le timer bat a la frequence de
; la note : duree = 2 x frequence x temps. Elle differe donc pour chaque
; hauteur, d'ou les valeurs toutes distinctes ci-dessous.
music_score:
        .byte   0                       ; fin de partition
        .byte   $0A,$44,68             ; SOLD5 x4
        .byte   $05,$63,69             ; LA5 x2
        .byte   $01,$F6,64             ; MI5 x1
        .byte   $01,$8E,60             ; DO5 x1
        .byte   $03,$06,59             ; SI4 x2
        .byte   $03,$94,62             ; RE5 x2
        .byte   $03,$30,60             ; DO5 x2
        .byte   $04,$06,64             ; MI5 x2
        .byte   $03,$06,59             ; SI4 x2
        .byte   $02,$89,56             ; SOLD4 x2
        .byte   $02,$B2,57             ; LA4 x2
        .byte   $03,$30,60             ; DO5 x2
        .byte   $03,$06,59             ; SI4 x2
        .byte   $03,$94,62             ; RE5 x2
        .byte   $03,$30,60             ; DO5 x2
        .byte   $04,$06,64             ; MI5 x2
        .byte   $00,$26,1              ; SIL x1
        .byte   $01,$50,57             ; LA4 x1
        .byte   $01,$50,57             ; LA4 x1
        .byte   $01,$8E,60             ; DO5 x1
        .byte   $01,$F6,64             ; MI5 x1
        .byte   $01,$BE,62             ; RE5 x1
        .byte   $00,$BC,60             ; DO5 x0.5
        .byte   $00,$B3,59             ; SI4 x0.5
        .byte   $01,$79,59             ; SI4 x1
        .byte   $00,$BC,60             ; DO5 x0.5
        .byte   $00,$D3,62             ; RE5 x0.5
        .byte   $01,$F6,64             ; MI5 x1
        .byte   $00,$BC,60             ; DO5 x0.5
        .byte   $02,$FE,64             ; MI5 x1.5
        .byte   $00,$F7,65             ; FA5 x0.5
        .byte   $01,$1B,67             ; SOL5 x0.5
        .byte   $02,$A0,69             ; LA5 x1
        .byte   $00,$F7,65             ; FA5 x0.5
        .byte   $02,$A9,62             ; RE5 x1.5
        .byte   $00,$26,1              ; SIL x1
        .byte   $01,$50,57             ; LA4 x1
        .byte   $01,$50,57             ; LA4 x1
        .byte   $01,$8E,60             ; DO5 x1
        .byte   $01,$F6,64             ; MI5 x1
        .byte   $01,$BE,62             ; RE5 x1
        .byte   $00,$BC,60             ; DO5 x0.5
        .byte   $02,$40,59             ; SI4 x1.5
        .byte   $00,$BC,60             ; DO5 x0.5
        .byte   $00,$D3,62             ; RE5 x0.5
        .byte   $01,$F6,64             ; MI5 x1
        .byte   $00,$BC,60             ; DO5 x0.5
        .byte   $00,$9F,57             ; LA4 x0.5
        .byte   $01,$50,57             ; LA4 x1
        .byte   $00,$B3,59             ; SI4 x0.5
        .byte   $00,$BC,60             ; DO5 x0.5
        .byte   $01,$BE,62             ; RE5 x1
        .byte   $00,$BC,60             ; DO5 x0.5
        .byte   $00,$B3,59             ; SI4 x0.5
        .byte   $01,$F6,64             ; MI5 x1
music_score_end:


; ============================================================================
; LOGO "EXELTRIS" (sortie EXELIMAGE) : 36 caracteres de 10 octets.
; Charge dans BAGC3 APRES l'intro : la cathedrale n'a plus besoin de ce banc,
; car la fenetre affichee en jeu (lignes 2..10 de l'image) n'utilise que des
; cellules BAGC2. Les 36 glyphes remplacent donc sans dommage ceux de BAGC3.
; ============================================================================
LOGO_CHR:
        .byte   $00,$00,$00,$00,$00,$00,$00,$00,$00,$00  ; $00  ; NEUTRALISE : code possible du cls de set_window
        .byte   $FE,$BC,$BC,$3C,$38,$20,$60,$F8,$FF,$FF  ; $01
        .byte   $0F,$07,$27,$27,$73,$F1,$F8,$FF,$FF,$FF  ; $02
        .byte   $CF,$CF,$CF,$C6,$C0,$C0,$E0,$FF,$FF,$FF  ; $03
        .byte   $F1,$71,$71,$71,$71,$71,$E0,$FF,$FF,$FF  ; $04
        .byte   $FF,$FF,$FD,$FD,$FD,$FC,$7C,$FF,$FF,$FF  ; $05
        .byte   $E3,$E3,$E3,$E3,$E3,$00,$00,$FF,$FF,$FF  ; $06
        .byte   $F8,$F8,$F8,$98,$98,$18,$10,$FF,$FF,$FF  ; $07
        .byte   $F3,$71,$71,$71,$61,$43,$03,$FF,$FF,$FF  ; $08
        .byte   $E3,$E3,$E3,$E3,$E1,$E1,$C0,$FF,$FF,$FF  ; $09
        .byte   $C3,$C7,$CF,$CF,$C7,$E3,$E0,$F8,$FF,$FF  ; $0A
        .byte   $FF,$FF,$9F,$9F,$9F,$9F,$1F,$3F,$FF,$FF  ; $0B
        .byte   $FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF  ; $0C  ; vide ; couvre aussi l'ancien $13 (2 px d'ecart)
        .byte   $00,$00,$00,$00,$00,$00,$00,$00,$00,$00  ; $0D
        .byte   $C7,$C7,$C7,$C7,$C7,$C0,$C0,$E0,$F3,$E3  ; $0E
        .byte   $99,$DC,$FC,$FE,$FE,$FF,$FF,$FF,$FE,$FE  ; $0F
        .byte   $C3,$C3,$C7,$C7,$07,$0F,$0F,$1F,$1F,$0F  ; $10
        .byte   $CF,$8F,$8F,$8F,$8F,$83,$81,$C1,$E3,$C7  ; $11
        .byte   $31,$B1,$F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1  ; $12
        .byte   $FF,$FF,$FF,$FF,$FF,$FF,$FF,$F0,$F8,$F8  ; $13  ; ex-$20 : bas du logo (glyphe reel)
        .byte   $E3,$E3,$E3,$E3,$E3,$E3,$E3,$E3,$E3,$E3  ; $14
        .byte   $F8,$F8,$F8,$F8,$F8,$F8,$F8,$F8,$F8,$F8  ; $15
        .byte   $61,$61,$E3,$C3,$C3,$87,$87,$8F,$C7,$E3  ; $16
        .byte   $DF,$DF,$DF,$FF,$FF,$F8,$E0,$E0,$C0,$C1  ; $17
        .byte   $9F,$8F,$8F,$8F,$0F,$0F,$1F,$1F,$3F,$FF  ; $18
        .byte   $FF,$FF,$FF,$FF,$FF,$FF,$FC,$F8,$E3,$E7  ; $19
        .byte   $FF,$FF,$FF,$FF,$FF,$FF,$3F,$23,$13,$99  ; $1A
        .byte   $FF,$FF,$FF,$FF,$FF,$FF,$FF,$F0,$E1,$E3  ; $1B  ; couvre aussi l'ancien $22 (4 px d'ecart)
        .byte   $FF,$FF,$FF,$FF,$FF,$FF,$FF,$F0,$E6,$CF  ; $1C
        .byte   $FF,$FF,$FF,$FF,$FF,$FF,$FF,$60,$70,$31  ; $1D
        .byte   $FF,$FF,$FF,$FF,$FF,$FF,$FF,$07,$C7,$F7  ; $1E
        .byte   $FF,$FF,$FF,$FF,$FF,$FF,$FF,$80,$C3,$E3  ; $1F
        .byte   $00,$00,$00,$00,$00,$00,$00,$00,$00,$00  ; $20  ; NEUTRALISE : $20 est un delimiteur VDP, jamais affiche
        .byte   $FF,$FF,$FF,$FF,$FF,$FF,$FF,$38,$70,$70  ; $21
        .byte   $E7,$E7,$C7,$C3,$E0,$E0,$F0,$FF,$FF,$FF  ; $22  ; ex-$00 : debut du logo (glyphe reel)
        .byte   $FF,$FF,$FF,$FF,$FF,$FF,$FF,$E0,$87,$CF  ; $23
        .byte   $FF,$FF,$FF,$FF,$FF,$FF,$FF,$7F,$3F,$1F  ; $24

logo_map:
        .byte   $22,$01,$02,$03,$04,$05,$06,$07,$08,$09,$0A,$0B,$0C
        .byte   $0E,$0F,$10,$11,$12,$0C,$14,$15,$16,$14,$17,$18,$0C
        .byte   $19,$1A,$1B,$1C,$1D,$1E,$1F,$13,$21,$1B,$23,$24,$0C
        .byte   $0C,$0C,$0C,$0C,$0C,$0C,$0C,$0C,$0C,$0C,$0C,$0C,$0C
mul13:  .byte   0,13,26,39

; ============================================================================
; NOTRE POLICE  -  63 glyphes 5x7, charges dans BAGC3 aux slots $40..$7E
; Ordre : 0-9, A-Z, a-z, ':'  (voir to_slot)
FONT_CHR:
        .byte   $00,$00,$70,$88,$C8,$A8,$98,$88,$70,$00  ; 0
        .byte   $00,$00,$70,$20,$20,$20,$20,$60,$20,$00  ; 1
        .byte   $00,$00,$F8,$40,$20,$10,$08,$88,$70,$00  ; 2
        .byte   $00,$00,$70,$88,$08,$10,$20,$10,$F8,$00  ; 3
        .byte   $00,$00,$10,$10,$F8,$90,$50,$30,$10,$00  ; 4
        .byte   $00,$00,$70,$88,$08,$08,$F0,$80,$F8,$00  ; 5
        .byte   $00,$00,$70,$88,$88,$F0,$80,$40,$30,$00  ; 6
        .byte   $00,$00,$40,$40,$40,$20,$10,$08,$F8,$00  ; 7
        .byte   $00,$00,$70,$88,$88,$70,$88,$88,$70,$00  ; 8
        .byte   $00,$00,$60,$10,$08,$78,$88,$88,$70,$00  ; 9
        .byte   $00,$00,$88,$88,$88,$F8,$88,$88,$70,$00  ; A
        .byte   $00,$00,$F0,$88,$88,$F0,$88,$88,$F0,$00  ; B
        .byte   $00,$00,$70,$88,$80,$80,$80,$88,$70,$00  ; C
        .byte   $00,$00,$E0,$90,$88,$88,$88,$90,$E0,$00  ; D
        .byte   $00,$00,$F8,$80,$80,$F0,$80,$80,$F8,$00  ; E
        .byte   $00,$00,$80,$80,$80,$F0,$80,$80,$F8,$00  ; F
        .byte   $00,$00,$78,$88,$88,$B8,$80,$88,$70,$00  ; G
        .byte   $00,$00,$88,$88,$88,$F8,$88,$88,$88,$00  ; H
        .byte   $00,$00,$70,$20,$20,$20,$20,$20,$70,$00  ; I
        .byte   $00,$00,$60,$90,$10,$10,$10,$10,$38,$00  ; J
        .byte   $00,$00,$88,$90,$A0,$C0,$A0,$90,$88,$00  ; K
        .byte   $00,$00,$F8,$80,$80,$80,$80,$80,$80,$00  ; L
        .byte   $00,$00,$88,$88,$88,$A8,$A8,$D8,$88,$00  ; M
        .byte   $00,$00,$88,$88,$88,$98,$A8,$C8,$88,$00  ; N
        .byte   $00,$00,$70,$88,$88,$88,$88,$88,$70,$00  ; O
        .byte   $00,$00,$80,$80,$80,$F0,$88,$88,$F0,$00  ; P
        .byte   $00,$00,$68,$90,$A8,$88,$88,$88,$70,$00  ; Q
        .byte   $00,$00,$88,$90,$A0,$F0,$88,$88,$F0,$00  ; R
        .byte   $00,$00,$F0,$08,$08,$70,$80,$80,$78,$00  ; S
        .byte   $00,$00,$20,$20,$20,$20,$20,$20,$F8,$00  ; T
        .byte   $00,$00,$70,$88,$88,$88,$88,$88,$88,$00  ; U
        .byte   $00,$00,$20,$50,$88,$88,$88,$88,$88,$00  ; V
        .byte   $00,$00,$88,$D8,$A8,$A8,$88,$88,$88,$00  ; W
        .byte   $00,$00,$88,$88,$50,$20,$50,$88,$88,$00  ; X
        .byte   $00,$00,$20,$20,$20,$20,$50,$88,$88,$00  ; Y
        .byte   $00,$00,$F8,$80,$40,$20,$10,$08,$F8,$00  ; Z
        .byte   $00,$00,$78,$88,$78,$08,$70,$00,$00,$00  ; a
        .byte   $00,$00,$F0,$88,$88,$88,$F0,$80,$80,$00  ; b
        .byte   $00,$00,$70,$88,$80,$80,$78,$00,$00,$00  ; c
        .byte   $00,$00,$78,$88,$88,$88,$78,$08,$08,$00  ; d
        .byte   $00,$00,$70,$80,$F8,$88,$70,$00,$00,$00  ; e
        .byte   $00,$00,$40,$40,$40,$E0,$40,$48,$30,$00  ; f
        .byte   $00,$00,$70,$08,$78,$88,$88,$78,$00,$00  ; g
        .byte   $00,$00,$88,$88,$88,$88,$F0,$80,$80,$00  ; h
        .byte   $00,$00,$70,$20,$20,$20,$60,$00,$20,$00  ; i
        .byte   $00,$00,$60,$90,$10,$10,$30,$00,$10,$00  ; j
        .byte   $00,$00,$90,$A0,$C0,$A0,$90,$80,$80,$00  ; k
        .byte   $00,$00,$70,$20,$20,$20,$20,$20,$60,$00  ; l
        .byte   $00,$00,$A8,$A8,$A8,$A8,$D0,$00,$00,$00  ; m
        .byte   $00,$00,$88,$88,$88,$88,$F0,$00,$00,$00  ; n
        .byte   $00,$00,$70,$88,$88,$88,$70,$00,$00,$00  ; o
        .byte   $00,$00,$80,$80,$F0,$88,$88,$F0,$00,$00  ; p
        .byte   $00,$00,$08,$08,$78,$88,$88,$78,$00,$00  ; q
        .byte   $00,$00,$80,$80,$80,$C8,$B0,$00,$00,$00  ; r
        .byte   $00,$00,$F0,$08,$70,$80,$78,$00,$00,$00  ; s
        .byte   $00,$00,$30,$48,$40,$40,$E0,$40,$40,$00  ; t
        .byte   $00,$00,$68,$98,$88,$88,$88,$00,$00,$00  ; u
        .byte   $00,$00,$20,$50,$88,$88,$88,$00,$00,$00  ; v
        .byte   $00,$00,$50,$A8,$A8,$88,$88,$00,$00,$00  ; w
        .byte   $00,$00,$88,$50,$20,$50,$88,$00,$00,$00  ; x
        .byte   $00,$00,$70,$08,$78,$88,$88,$88,$00,$00  ; y
        .byte   $00,$00,$F8,$40,$20,$10,$F8,$00,$00,$00  ; z
        .byte   $00,$00,$00,$30,$30,$00,$30,$30,$00,$00  ; deux-points

; ============================================================================
; DONNEES DE L'ECRAN D'INTRO (sortie EXELIMAGE, integree telle quelle)
;   BAGC2_DATA / BAGC3_DATA : 128 caracteres de 10 octets chacun
;   SCREEN_DATA             : 25 lignes x 40 cellules x 2 octets (attribut,
;                             caractere)
; ============================================================================
BAGC2_DATA:
        .byte   $FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF  ; $00
        .byte   $F8,$F9,$FB,$FA,$FD,$FE,$FF,$FF,$FF,$FF  ; $01  ancien $20, deplace ici
        .byte   $0F,$1F,$BF,$BF,$BF,$BF,$BF,$BF,$BF,$FF  ; $02
        .byte   $FE,$FD,$FD,$FB,$FB,$FB,$FB,$FB,$FB,$FD  ; $03
        .byte   $CF,$C7,$C7,$83,$03,$03,$03,$03,$03,$87  ; $04
        .byte   $EC,$F5,$F7,$F6,$F6,$FA,$FA,$FD,$FD,$FE  ; $05
        .byte   $AA,$B5,$9D,$AB,$95,$AB,$97,$BB,$AB,$97  ; $06
        .byte   $BF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF  ; $07
        .byte   $EF,$EF,$EF,$EF,$EF,$EF,$EF,$EF,$EF,$EF  ; $08
        .byte   $BA,$93,$DB,$CA,$D9,$C8,$DD,$ED,$E8,$ED  ; $09
        .byte   $AA,$BB,$BB,$AA,$91,$BB,$95,$B6,$B2,$B6  ; $0A
        .byte   $BF,$BF,$BF,$BF,$7F,$7F,$7F,$FF,$FF,$FF  ; $0B
        .byte   $EF,$EF,$EF,$EF,$FF,$FF,$FF,$FF,$FF,$FF  ; $0C
        .byte   $1F,$1F,$BF,$BF,$BF,$BF,$BF,$BF,$BF,$BF  ; $0D
        .byte   $83,$39,$BB,$BB,$C7,$EF,$EF,$EF,$EF,$EF  ; $0E
        .byte   $FC,$FE,$FE,$FE,$FE,$FF,$FF,$FF,$FF,$FF  ; $0F
        .byte   $AA,$F5,$F7,$A2,$75,$22,$55,$7F,$3A,$91  ; $10
        .byte   $AA,$B6,$BE,$AE,$94,$AC,$95,$BD,$A8,$9D  ; $11
        .byte   $B7,$D7,$F7,$A7,$6F,$AF,$5F,$DF,$DF,$5F  ; $12
        .byte   $FB,$FB,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF  ; $13
        .byte   $E2,$FA,$FE,$FE,$FE,$FE,$FF,$FF,$FF,$FF  ; $14
        .byte   $A8,$AB,$EF,$EF,$EF,$0F,$1F,$1F,$1F,$1F  ; $15
        .byte   $E2,$F2,$FC,$FC,$FE,$FF,$FF,$FF,$FF,$FF  ; $16
        .byte   $EC,$00,$FC,$FC,$01,$39,$39,$BB,$83,$83  ; $17
        .byte   $3F,$7F,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF  ; $18
        .byte   $FE,$FD,$FB,$FB,$FB,$FB,$FB,$FB,$FB,$FD  ; $19
        .byte   $8A,$D5,$DF,$CA,$45,$EA,$45,$EF,$EA,$45  ; $1A
        .byte   $AB,$B5,$BF,$AB,$95,$AB,$97,$BF,$AA,$96  ; $1B
        .byte   $AA,$36,$3F,$6D,$55,$2D,$5B,$7B,$2B,$5B  ; $1C
        .byte   $FC,$FE,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF  ; $1D
        .byte   $FC,$01,$7B,$7B,$03,$B7,$B7,$B7,$87,$CF  ; $1E
        .byte   $EE,$F5,$FB,$FB,$FB,$FB,$FB,$FB,$FB,$FB  ; $1F
        .byte   $F8,$F9,$FB,$FA,$FD,$FE,$FF,$FF,$FF,$FF  ; $20  INUTILISABLE : delimiteur de zone
        .byte   $00,$55,$FF,$AA,$55,$AA,$55,$FF,$AA,$D5  ; $21
        .byte   $00,$55,$FF,$AA,$55,$AA,$55,$FF,$AA,$55  ; $22
        .byte   $03,$53,$FB,$AB,$57,$AF,$5F,$FF,$BF,$7F  ; $23
        .byte   $E1,$F9,$FE,$FF,$FF,$FF,$FF,$FF,$FF,$FF  ; $24
        .byte   $7F,$7F,$7F,$0F,$C3,$F8,$FE,$FE,$FF,$FF  ; $25
        .byte   $1F,$5F,$DF,$BF,$BF,$7F,$7F,$7F,$7F,$9F  ; $26
        .byte   $D7,$D7,$EF,$EF,$EF,$EF,$EF,$EF,$EE,$EE  ; $27
        .byte   $F0,$E6,$EE,$CC,$98,$91,$27,$6F,$4F,$9F  ; $28
        .byte   $C0,$40,$DF,$DF,$D5,$EB,$E5,$EF,$EA,$F5  ; $29
        .byte   $00,$00,$BF,$BF,$15,$AA,$D5,$DF,$8A,$D5  ; $2A
        .byte   $00,$00,$BF,$BF,$95,$AA,$95,$BF,$AA,$95  ; $2B
        .byte   $1F,$5F,$DF,$BF,$BF,$7F,$7F,$7F,$7F,$FF  ; $2C
        .byte   $F0,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF  ; $2D
        .byte   $77,$00,$3F,$3F,$9F,$C0,$C0,$E3,$EB,$F9  ; $2E
        .byte   $BD,$00,$FF,$FF,$FF,$00,$00,$FF,$FF,$FE  ; $2F
        .byte   $D8,$09,$F3,$F3,$E7,$0F,$0F,$1F,$5F,$7F  ; $30
        .byte   $8F,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF  ; $31
        .byte   $BA,$93,$DB,$CA,$D9,$C0,$DD,$DD,$E0,$ED  ; $32
        .byte   $1F,$7F,$7F,$7F,$7F,$7F,$7F,$7F,$7F,$7F  ; $33
        .byte   $C0,$85,$F5,$F5,$F5,$F2,$F2,$F0,$F1,$F1  ; $34
        .byte   $00,$55,$55,$55,$55,$AA,$AA,$00,$55,$55  ; $35
        .byte   $4A,$4B,$63,$23,$51,$A8,$A4,$07,$53,$51  ; $36
        .byte   $61,$24,$26,$A6,$87,$C7,$40,$1B,$5B,$C0  ; $37
        .byte   $C3,$C9,$CD,$4C,$0E,$8F,$00,$77,$77,$00  ; $38
        .byte   $E0,$E6,$EF,$4F,$1F,$BF,$00,$EF,$EF,$00  ; $39
        .byte   $F0,$64,$6E,$0E,$8F,$9F,$00,$F7,$F7,$00  ; $3A
        .byte   $4C,$47,$57,$50,$5B,$5A,$DA,$DE,$D6,$5D  ; $3B
        .byte   $6C,$D7,$FF,$38,$BD,$BD,$BD,$FF,$C3,$7E  ; $3C
        .byte   $1B,$F5,$FF,$0E,$DF,$5F,$5F,$7F,$60,$BF  ; $3D
        .byte   $00,$FF,$FF,$0C,$31,$42,$CC,$9D,$51,$66  ; $3E
        .byte   $41,$48,$5E,$5E,$5E,$5E,$5E,$5F,$5F,$5F  ; $3F
        .byte   $F8,$7C,$7E,$3E,$0F,$A0,$31,$F1,$F4,$F4  ; $40
        .byte   $F0,$78,$7E,$BE,$8F,$00,$FF,$FF,$00,$F7  ; $41
        .byte   $F8,$7C,$7E,$BE,$9F,$00,$FF,$FF,$00,$BD  ; $42
        .byte   $7C,$78,$78,$78,$39,$00,$FF,$FF,$00,$DC  ; $43
        .byte   $1F,$3F,$FF,$FF,$FC,$01,$87,$8F,$2F,$2F  ; $44
        .byte   $F9,$F3,$23,$0C,$1F,$FF,$FF,$FF,$FF,$FF  ; $45
        .byte   $3F,$BF,$BF,$3F,$FF,$FF,$FF,$FF,$FF,$FF  ; $46
        .byte   $2A,$B5,$DF,$CA,$E5,$F2,$F9,$FD,$FC,$FE  ; $47
        .byte   $AA,$55,$FF,$AA,$55,$AA,$55,$55,$55,$55  ; $48
        .byte   $AA,$55,$FF,$AA,$54,$A9,$53,$57,$47,$4F  ; $49
        .byte   $96,$B6,$76,$60,$E7,$EB,$E5,$E5,$E5,$CD  ; $4A
        .byte   $EE,$EE,$EE,$10,$D7,$BA,$7D,$7D,$45,$55  ; $4B
        .byte   $D0,$E0,$E0,$4A,$4A,$CA,$CA,$C8,$4A,$4A  ; $4C
        .byte   $00,$00,$00,$D5,$DD,$DD,$10,$E3,$E3,$E1  ; $4D
        .byte   $00,$00,$00,$2A,$EF,$EF,$00,$CF,$CF,$C7  ; $4E
        .byte   $40,$40,$40,$52,$DF,$DF,$10,$E7,$E7,$E3  ; $4F
        .byte   $00,$00,$00,$36,$F7,$F7,$00,$F9,$F9,$F1  ; $50
        .byte   $AD,$DA,$FB,$73,$4B,$FB,$6B,$EB,$EB,$69  ; $51
        .byte   $BB,$C6,$FF,$7D,$83,$BB,$AB,$AB,$AB,$29  ; $52
        .byte   $6E,$A9,$EF,$EF,$E0,$EE,$EA,$EA,$EA,$CA  ; $53
        .byte   $CB,$AC,$FF,$77,$F0,$F7,$F5,$F5,$F5,$65  ; $54
        .byte   $5C,$BC,$BC,$BC,$5E,$5F,$5F,$5F,$4F,$47  ; $55
        .byte   $1F,$1F,$1F,$1F,$0F,$07,$03,$43,$51,$30  ; $56
        .byte   $80,$81,$81,$81,$81,$81,$C1,$C1,$C1,$E1  ; $57
        .byte   $FF,$FE,$FE,$FC,$F8,$F8,$F8,$F8,$F8,$F8  ; $58
        .byte   $00,$03,$07,$07,$0F,$1F,$3F,$7F,$7F,$7E  ; $59
        .byte   $FF,$FE,$FE,$F8,$F0,$C0,$80,$83,$0B,$0F  ; $5A
        .byte   $81,$83,$07,$07,$0F,$3F,$FE,$FE,$FC,$F8  ; $5B
        .byte   $CF,$CF,$DF,$9F,$07,$17,$47,$FF,$FF,$FF  ; $5C
        .byte   $3E,$1F,$DF,$C7,$E3,$00,$55,$55,$55,$55  ; $5D
        .byte   $07,$83,$E3,$E9,$F9,$00,$55,$55,$55,$55  ; $5E
        .byte   $F0,$F8,$FC,$FC,$FC,$00,$55,$55,$55,$55  ; $5F
        .byte   $FC,$FC,$FC,$FC,$FC,$00,$53,$57,$44,$4E  ; $60
        .byte   $8C,$98,$3D,$7D,$40,$FD,$05,$00,$55,$DD  ; $61
        .byte   $00,$00,$EE,$EE,$00,$EE,$08,$00,$00,$EE  ; $62
        .byte   $DF,$40,$DF,$DF,$40,$CA,$55,$55,$50,$DF  ; $63
        .byte   $3C,$78,$7F,$77,$60,$CA,$55,$15,$00,$FF  ; $64
        .byte   $FF,$00,$FF,$FF,$00,$AA,$55,$55,$00,$FF  ; $65
        .byte   $A2,$A2,$FF,$FF,$80,$B7,$B5,$B5,$B5,$B5  ; $66
        .byte   $08,$08,$FF,$FF,$00,$7D,$7D,$7D,$7D,$7D  ; $67
        .byte   $10,$00,$FF,$FF,$00,$77,$57,$57,$57,$57  ; $68
        .byte   $A3,$A7,$EF,$EF,$1F,$9E,$9C,$9C,$9C,$9C  ; $69
        .byte   $E0,$E0,$C1,$81,$03,$03,$07,$07,$07,$0F  ; $6A
        .byte   $3F,$FF,$FF,$FE,$F8,$F0,$E0,$E0,$C0,$80  ; $6B
        .byte   $C0,$41,$03,$03,$07,$0F,$1F,$3F,$3F,$7F  ; $6C
        .byte   $7F,$FF,$FF,$FF,$FC,$F0,$E0,$E0,$C0,$80  ; $6D
        .byte   $7C,$FC,$FC,$FC,$FC,$F8,$F8,$F8,$F0,$E1  ; $6E
        .byte   $0B,$0B,$83,$85,$85,$C5,$C5,$C5,$C5,$C1  ; $6F
        .byte   $FE,$FC,$FC,$FC,$FC,$FC,$FC,$FC,$FC,$FE  ; $70
        .byte   $07,$07,$07,$03,$81,$C0,$E0,$F0,$F4,$FC  ; $71
        .byte   $03,$03,$F9,$F8,$FC,$FE,$BF,$3F,$0F,$07  ; $72
        .byte   $7F,$3F,$3F,$1F,$0F,$07,$03,$83,$81,$E0  ; $73
        .byte   $03,$81,$C1,$E0,$E0,$F0,$F8,$FC,$FC,$FC  ; $74
        .byte   $E7,$E3,$E3,$E2,$E2,$E2,$E2,$E3,$E7,$C4  ; $75
        .byte   $B9,$1D,$5E,$4E,$47,$43,$01,$FF,$FF,$00  ; $76
        .byte   $3B,$71,$F5,$E4,$C4,$84,$00,$FF,$FF,$00  ; $77
        .byte   $AF,$CF,$EF,$EF,$6F,$2F,$0F,$DF,$DF,$3E  ; $78
        .byte   $AA,$55,$55,$00,$FF,$00,$08,$AA,$AA,$08  ; $79
        .byte   $19,$B3,$FF,$4E,$1F,$D0,$58,$CA,$CA,$48  ; $7A
        .byte   $AB,$57,$57,$01,$FF,$01,$09,$AB,$AA,$08  ; $7B
        .byte   $67,$2A,$2A,$2A,$2A,$2A,$2A,$AA,$AA,$FF  ; $7C
        .byte   $5C,$46,$4F,$4B,$48,$48,$48,$48,$48,$FF  ; $7D
        .byte   $97,$94,$14,$14,$14,$14,$14,$14,$14,$FF  ; $7E
        .byte   $8F,$9F,$9F,$9F,$9E,$9C,$94,$90,$90,$E1  ; $7F

BAGC3_DATA:
        .byte   $F1,$E3,$E7,$87,$0F,$1F,$7F,$FF,$FE,$F8  ; $00
        .byte   $FF,$FE,$FE,$FC,$F8,$E0,$83,$87,$17,$1F  ; $01
        .byte   $07,$0F,$1F,$5F,$7F,$FF,$FF,$FF,$FC,$F0  ; $02
        .byte   $FC,$F8,$F8,$F0,$E1,$83,$07,$1F,$1F,$3F  ; $03
        .byte   $FF,$FF,$FF,$FF,$FF,$FF,$FF,$FE,$FE,$F8  ; $04
        .byte   $03,$07,$07,$36,$32,$38,$3C,$3C,$3C,$7C  ; $05
        .byte   $FF,$FF,$7F,$BF,$BF,$3F,$FF,$FF,$7F,$07  ; $06
        .byte   $FF,$FC,$FC,$F8,$E1,$C3,$87,$8F,$0F,$1F  ; $07
        .byte   $00,$00,$F9,$F9,$E3,$C7,$87,$87,$87,$07  ; $08
        .byte   $00,$00,$FB,$FB,$F3,$E3,$C3,$C3,$C1,$C0  ; $09
        .byte   $8C,$C8,$E8,$E8,$70,$20,$1F,$9F,$8C,$C5  ; $0A
        .byte   $36,$63,$63,$EB,$FF,$00,$FF,$FF,$E0,$F1  ; $0B
        .byte   $18,$0E,$0F,$89,$80,$00,$FF,$FF,$0E,$1F  ; $0C
        .byte   $C0,$61,$F9,$9A,$C6,$31,$FC,$FE,$06,$27  ; $0D
        .byte   $00,$FB,$FF,$F7,$36,$07,$C3,$F3,$30,$88  ; $0E
        .byte   $00,$FF,$FF,$7E,$7C,$78,$61,$67,$06,$FC  ; $0F
        .byte   $00,$C3,$CF,$8C,$19,$62,$CD,$DF,$1A,$75  ; $10
        .byte   $8B,$3A,$7A,$6A,$DA,$AA,$5A,$FA,$AA,$5F  ; $11
        .byte   $B1,$EC,$FE,$B2,$DD,$C6,$D3,$FB,$A8,$29  ; $12
        .byte   $80,$7F,$7F,$9F,$87,$63,$90,$FC,$ED,$33  ; $13
        .byte   $00,$DF,$FF,$AF,$77,$FE,$F8,$F9,$21,$06  ; $14
        .byte   $18,$F1,$F7,$C6,$19,$23,$CD,$FF,$3A,$6D  ; $15
        .byte   $FE,$FD,$FB,$FB,$F8,$F8,$FB,$FB,$FB,$F8  ; $16
        .byte   $AA,$65,$EF,$AA,$00,$00,$DF,$DF,$DF,$00  ; $17
        .byte   $AA,$B5,$BF,$AA,$00,$00,$7E,$7E,$7E,$00  ; $18
        .byte   $AA,$B5,$BF,$AA,$00,$00,$FD,$FD,$FD,$00  ; $19
        .byte   $AA,$B5,$BF,$AA,$00,$00,$F7,$F7,$F7,$00  ; $1A
        .byte   $49,$51,$59,$49,$00,$00,$76,$76,$76,$00  ; $1B
        .byte   $FF,$FF,$FF,$BF,$BF,$3F,$FF,$FF,$FF,$03  ; $1C
        .byte   $00,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF  ; $1D
        .byte   $00,$FF,$FF,$80,$80,$96,$96,$96,$90,$9F  ; $1E
        .byte   $00,$FF,$FF,$80,$00,$EF,$EF,$EF,$00,$FF  ; $1F
        .byte   $00,$FF,$FF,$80,$00,$BB,$BB,$BB,$00,$FF  ; $20  INUTILISABLE : delimiteur de zone
        .byte   $00,$FF,$FF,$88,$04,$42,$42,$4F,$4F,$CF  ; $21
        .byte   $00,$FF,$FF,$E3,$63,$77,$3E,$3E,$1E,$1C  ; $22
        .byte   $00,$FF,$FF,$18,$86,$63,$18,$DC,$CD,$33  ; $23
        .byte   $00,$FF,$FF,$FF,$3F,$0F,$C3,$F3,$30,$1F  ; $24
        .byte   $00,$FF,$FF,$77,$77,$77,$77,$77,$00,$FF  ; $25
        .byte   $00,$FF,$FF,$FE,$FE,$FE,$FE,$FE,$00,$FF  ; $26
        .byte   $00,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$00,$FF  ; $27
        .byte   $00,$FF,$FF,$7F,$7F,$7F,$7F,$7F,$01,$FE  ; $28
        .byte   $00,$FF,$FF,$BE,$BC,$B9,$E6,$EF,$89,$37  ; $29
        .byte   $00,$FF,$FF,$33,$CF,$3A,$75,$FF,$CA,$C5  ; $2A
        .byte   $00,$FF,$FF,$AA,$95,$AA,$95,$BF,$AA,$95  ; $2B
        .byte   $F0,$FC,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF  ; $2C
        .byte   $00,$03,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF  ; $2D
        .byte   $FC,$FC,$FC,$FF,$FF,$FF,$FF,$FF,$FF,$FF  ; $2E
        .byte   $00,$00,$00,$FF,$FF,$FF,$FF,$FF,$FF,$FF  ; $2F  (recoit aussi les cellules de $3B)
        .byte   $7F,$7F,$7F,$FF,$FF,$FF,$FF,$FF,$FF,$FF  ; $30
        .byte   $03,$03,$03,$FF,$FF,$FF,$FF,$FF,$FF,$FF  ; $31
        .byte   $F0,$F8,$FC,$FF,$FF,$FF,$FF,$FF,$FF,$FF  ; $32
        .byte   $00,$01,$07,$FF,$FF,$FF,$FF,$FF,$FF,$FF  ; $33
        .byte   $7F,$FE,$FE,$FF,$FF,$FF,$FF,$FF,$FF,$FF  ; $34
        .byte   $07,$03,$03,$FF,$FF,$FF,$FF,$FF,$FF,$FF  ; $35
        .byte   $E0,$E0,$E0,$FF,$FF,$FF,$FF,$FF,$FF,$FF  ; $36
        .byte   $30,$30,$30,$FF,$FF,$FF,$FF,$FF,$FF,$FF  ; $37
        .byte   $03,$0F,$1F,$FF,$FF,$FF,$FF,$FF,$FF,$FF  ; $38
        .byte   $FF,$FE,$FE,$FF,$FF,$FF,$FF,$FF,$FF,$FF  ; $39
        .byte   $FC,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF  ; $3A
        .byte   $00,$FF,$FF,$80,$00,$BB,$BB,$BB,$00,$FF  ; $3B  ancien $20, deplace ici
        .byte   $00,$00,$01,$FF,$FF,$FF,$FF,$FF,$FF,$FF  ; $3C
        .byte   $83,$83,$81,$81,$81,$80,$80,$C0,$C0,$E0  ; $3D
        .byte   $FF,$FF,$FF,$FF,$FE,$FC,$00,$00,$00,$00  ; $3E
        .byte   $9F,$BF,$3F,$3F,$3F,$3F,$3F,$7F,$7F,$7E  ; $3F
        .byte   $FC,$FC,$F8,$F8,$F8,$F0,$E0,$C0,$C0,$00  ; $40
        .byte   $00,$03,$07,$07,$0F,$1F,$3F,$7F,$7F,$7F  ; $41
        .byte   $1F,$8F,$87,$C7,$C3,$E3,$F1,$F1,$F8,$F8  ; $42
        .byte   $FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$7F,$3F  ; $43
        .byte   $C1,$C1,$C1,$C1,$C0,$C0,$C0,$C0,$C0,$E0  ; $44
        .byte   $FF,$FF,$FF,$FF,$FF,$FF,$1C,$00,$00,$00  ; $45
        .byte   $FF,$9F,$9F,$9F,$1F,$3F,$3F,$3F,$3F,$3F  ; $46
        .byte   $E0,$E0,$E0,$E0,$E0,$E0,$E0,$E0,$E0,$E0  ; $47
        .byte   $3F,$3F,$3F,$3F,$3F,$3F,$3F,$3F,$3F,$3F  ; $48
        .byte   $FF,$FF,$FF,$F3,$E1,$E1,$E1,$E1,$E1,$E0  ; $49
        .byte   $FE,$FE,$FE,$FE,$FE,$FE,$FE,$FE,$FE,$00  ; $4A
        .byte   $03,$03,$03,$03,$03,$03,$03,$03,$03,$00  ; $4B
        .byte   $FF,$FF,$FF,$FE,$FC,$FC,$FC,$FC,$FC,$00  ; $4C
        .byte   $FF,$FF,$FF,$7F,$3F,$3F,$3F,$3F,$3F,$3E  ; $4D
        .byte   $01,$01,$01,$01,$01,$01,$01,$01,$01,$00  ; $4E
        .byte   $81,$81,$81,$81,$81,$01,$01,$01,$01,$03  ; $4F
        .byte   $E0,$E0,$E0,$E0,$E0,$E0,$F0,$F8,$F8,$F8  ; $50
        .byte   $7F,$7F,$7F,$FF,$FF,$7F,$7F,$7F,$3F,$1F  ; $51
        .byte   $FF,$FF,$FF,$FC,$FC,$FC,$FC,$FC,$F8,$F0  ; $52
        .byte   $00,$80,$80,$E0,$FC,$F8,$F1,$E1,$C1,$C3  ; $53
        .byte   $03,$03,$03,$03,$0F,$7F,$FF,$FF,$FF,$FF  ; $54
        .byte   $FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FE,$FE  ; $55
        .byte   $C0,$C0,$C0,$C0,$80,$80,$00,$00,$00,$00  ; $56
        .byte   $3F,$3F,$3F,$7F,$FF,$FF,$7F,$3F,$3F,$3F  ; $57
        .byte   $00,$80,$80,$E0,$FC,$F8,$F1,$E1,$C1,$C1  ; $58
        .byte   $01,$01,$01,$03,$03,$3F,$FF,$FF,$FF,$FF  ; $59
        .byte   $FE,$FE,$FE,$FE,$FE,$FE,$FE,$FE,$FE,$FE  ; $5A
        .byte   $03,$03,$03,$03,$03,$03,$03,$03,$03,$03  ; $5B
        .byte   $01,$01,$01,$01,$01,$01,$01,$01,$01,$01  ; $5C
        .byte   $C0,$C0,$80,$80,$C0,$F8,$FE,$FE,$FF,$FF  ; $5D
        .byte   $3F,$7F,$7F,$FF,$7F,$3F,$0F,$0F,$07,$03  ; $5E
        .byte   $FF,$FE,$FC,$FC,$F8,$F8,$F0,$F0,$E0,$E0  ; $5F
        .byte   $C0,$00,$00,$00,$00,$00,$00,$03,$1F,$3F  ; $60
        .byte   $00,$00,$00,$00,$01,$03,$1F,$FF,$FF,$FF  ; $61
        .byte   $3F,$3F,$7F,$FF,$FF,$FF,$FF,$FF,$FF,$FF  ; $62
        .byte   $FF,$FF,$FE,$FE,$FE,$FE,$FE,$FE,$FE,$FF  ; $63
        .byte   $07,$07,$07,$07,$07,$03,$03,$03,$01,$00  ; $64
        .byte   $F1,$F8,$F8,$FC,$FC,$FE,$FF,$FF,$FF,$FF  ; $65
        .byte   $FF,$FE,$7C,$7C,$3C,$38,$18,$18,$80,$C0  ; $66
        .byte   $01,$01,$03,$03,$07,$07,$0F,$0F,$1F,$1F  ; $67
        .byte   $FF,$FF,$FE,$FE,$FE,$FE,$FE,$FE,$FE,$FE  ; $68
        .byte   $83,$03,$07,$07,$07,$07,$03,$03,$01,$00  ; $69
        .byte   $C7,$E7,$F7,$FF,$FF,$FF,$FF,$FF,$FF,$FF  ; $6A
        .byte   $FE,$FE,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF  ; $6B
        .byte   $7F,$7F,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF  ; $6C
        .byte   $E7,$E7,$E7,$E7,$E7,$FF,$FF,$FF,$FF,$FF  ; $6D
        .byte   $FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FE  ; $6E
        .byte   $F0,$F0,$F8,$F8,$F8,$F0,$F0,$F0,$C0,$00  ; $6F
        .byte   $3F,$3F,$3F,$3F,$1F,$1F,$1F,$1F,$3F,$3F  ; $70
        .byte   $FF,$FF,$FE,$F8,$F0,$C0,$80,$83,$03,$07  ; $71
        .byte   $FF,$FF,$00,$00,$00,$FE,$FF,$FF,$FF,$FF  ; $72
        .byte   $FF,$FF,$1C,$1C,$1C,$1F,$0F,$8F,$8F,$8F  ; $73
        .byte   $FF,$FF,$1F,$0F,$0F,$07,$87,$C3,$E1,$E1  ; $74
        .byte   $FF,$FF,$E0,$E0,$C0,$C0,$80,$80,$00,$01  ; $75
        .byte   $FF,$FF,$0F,$0F,$0F,$3F,$7F,$FF,$FF,$FF  ; $76
        .byte   $FF,$FF,$FF,$FE,$FC,$F8,$F0,$E1,$C3,$83  ; $77
        .byte   $FF,$FF,$3F,$1F,$0F,$0F,$0F,$87,$87,$C7  ; $78
        .byte   $FF,$FF,$80,$00,$C0,$E0,$E0,$E0,$E0,$E0  ; $79
        .byte   $FF,$FF,$00,$00,$00,$00,$3F,$3F,$3F,$3F  ; $7A
        .byte   $FF,$FF,$01,$00,$00,$00,$FC,$FC,$FC,$FE  ; $7B
        .byte   $FF,$FF,$FF,$FF,$FF,$FF,$7F,$7F,$7F,$7F  ; $7C
        .byte   $FF,$FF,$F8,$F0,$F0,$FE,$FE,$FE,$FE,$FE  ; $7D
        .byte   $FF,$FF,$00,$00,$00,$03,$03,$03,$03,$03  ; $7E
        .byte   $FF,$FF,$FF,$7F,$7F,$FF,$FF,$FF,$FF,$FF  ; $7F

SCREEN_DATA:
; Row 0
        .byte   $09,$00,$09,$00,$09,$00,$09,$00,$09,$00,$09,$00,$09,$00,$09,$00
        .byte   $09,$00,$09,$00,$09,$00,$09,$00,$09,$00,$09,$00,$09,$00,$09,$00
        .byte   $09,$00,$09,$00,$09,$00,$09,$00,$09,$00,$09,$00,$09,$00,$09,$02
        .byte   $09,$00,$09,$00,$09,$00,$09,$00,$09,$00,$09,$00,$09,$00,$09,$00
        .byte   $09,$00,$09,$00,$09,$00,$09,$00,$09,$00,$09,$00,$09,$00,$09,$00
; Row 1
        .byte   $09,$00,$09,$00,$09,$00,$09,$00,$09,$00,$09,$00,$09,$00,$09,$00
        .byte   $09,$00,$09,$00,$09,$00,$09,$00,$09,$00,$09,$00,$09,$00,$09,$00
        .byte   $09,$00,$09,$00,$09,$00,$09,$00,$09,$00,$09,$00,$09,$03,$09,$04
        .byte   $09,$00,$09,$00,$09,$00,$09,$00,$09,$00,$09,$00,$09,$00,$09,$00
        .byte   $09,$00,$09,$00,$09,$00,$09,$00,$09,$00,$09,$00,$09,$00,$09,$00
; Row 2
        .byte   $09,$00,$09,$00,$09,$00,$09,$00,$09,$00,$09,$00,$09,$00,$09,$00
        .byte   $09,$00,$09,$00,$09,$00,$09,$00,$09,$00,$09,$00,$09,$00,$09,$00
        .byte   $09,$00,$09,$00,$09,$00,$09,$00,$09,$00,$09,$00,$09,$05,$09,$06
        .byte   $09,$00,$09,$00,$09,$00,$09,$00,$09,$00,$09,$00,$09,$00,$09,$00
        .byte   $09,$00,$09,$00,$09,$00,$09,$00,$09,$00,$09,$00,$09,$00,$09,$00
; Row 3
        .byte   $09,$00,$09,$00,$09,$00,$09,$00,$09,$00,$09,$00,$09,$00,$09,$00
        .byte   $09,$00,$09,$00,$09,$00,$09,$00,$09,$00,$09,$00,$09,$00,$09,$00
        .byte   $09,$00,$09,$00,$09,$00,$09,$08,$09,$00,$09,$00,$09,$09,$09,$0A
        .byte   $09,$0B,$09,$00,$09,$00,$09,$00,$09,$0C,$09,$00,$09,$00,$09,$00
        .byte   $09,$00,$09,$00,$09,$00,$09,$00,$09,$00,$09,$00,$09,$00,$09,$00
; Row 4
        .byte   $09,$00,$09,$00,$09,$00,$09,$00,$09,$00,$09,$00,$09,$00,$09,$00
        .byte   $09,$00,$09,$00,$09,$00,$09,$00,$09,$00,$09,$00,$09,$0D,$09,$00
        .byte   $09,$00,$09,$00,$09,$00,$09,$0E,$09,$00,$09,$0F,$09,$10,$09,$11
        .byte   $09,$12,$09,$00,$09,$00,$09,$00,$09,$08,$09,$00,$09,$00,$09,$00
        .byte   $09,$00,$09,$00,$09,$00,$09,$00,$09,$00,$09,$00,$09,$00,$09,$00
; Row 5
        .byte   $09,$00,$09,$00,$09,$00,$09,$00,$09,$00,$09,$00,$09,$00,$09,$00
        .byte   $09,$00,$09,$00,$09,$13,$09,$00,$09,$00,$09,$14,$09,$15,$09,$00
        .byte   $09,$00,$09,$00,$09,$16,$09,$17,$09,$18,$09,$19,$09,$1A,$09,$1B
        .byte   $09,$1C,$09,$00,$09,$00,$09,$1D,$09,$1E,$09,$00,$09,$00,$09,$00
        .byte   $09,$00,$09,$00,$09,$00,$09,$00,$09,$00,$09,$00,$09,$00,$09,$00
; Row 6
        .byte   $09,$00,$09,$00,$09,$00,$09,$00,$09,$00,$09,$00,$09,$00,$09,$00
        .byte   $09,$00,$09,$00,$09,$1F,$09,$00,$09,$01,$09,$21,$09,$22,$09,$23
        .byte   $09,$24,$09,$25,$09,$26,$09,$27,$09,$28,$09,$29,$09,$2A,$09,$2B
        .byte   $09,$2B,$09,$2C,$09,$2D,$09,$2E,$09,$2F,$09,$30,$09,$31,$09,$00
        .byte   $09,$00,$09,$00,$09,$00,$09,$00,$09,$00,$09,$00,$09,$00,$09,$00
; Row 7
        .byte   $09,$00,$09,$00,$09,$00,$09,$00,$09,$00,$09,$00,$09,$00,$09,$00
        .byte   $09,$00,$09,$00,$09,$32,$09,$33,$09,$34,$09,$35,$09,$35,$09,$36
        .byte   $09,$37,$09,$38,$09,$39,$09,$39,$09,$3A,$09,$3B,$09,$3C,$09,$3D
        .byte   $09,$3E,$09,$3F,$09,$40,$09,$41,$09,$42,$09,$43,$09,$44,$09,$45
        .byte   $09,$46,$09,$00,$09,$00,$09,$00,$09,$00,$09,$00,$09,$00,$09,$00
; Row 8
        .byte   $09,$00,$09,$00,$09,$00,$09,$00,$09,$00,$09,$00,$09,$00,$09,$00
        .byte   $09,$00,$09,$47,$09,$48,$09,$49,$09,$4A,$09,$4B,$09,$4B,$09,$4C
        .byte   $09,$4D,$09,$4E,$09,$4F,$09,$50,$09,$50,$09,$51,$09,$52,$09,$53
        .byte   $09,$54,$09,$55,$09,$56,$09,$57,$09,$58,$09,$59,$09,$5A,$09,$5B
        .byte   $09,$5C,$09,$00,$09,$00,$09,$00,$09,$00,$09,$00,$09,$00,$09,$00
; Row 9
        .byte   $09,$00,$09,$00,$09,$00,$09,$00,$09,$00,$09,$00,$09,$00,$09,$00
        .byte   $09,$47,$09,$5D,$09,$5E,$09,$5F,$09,$60,$09,$61,$09,$62,$09,$63
        .byte   $09,$64,$09,$65,$09,$63,$09,$65,$09,$65,$09,$66,$09,$67,$09,$67
        .byte   $09,$68,$09,$69,$09,$6A,$09,$6B,$09,$6C,$09,$6D,$09,$6A,$09,$6E
        .byte   $09,$6F,$09,$00,$09,$00,$09,$00,$09,$00,$09,$00,$09,$00,$09,$00
; Row 10
        .byte   $09,$00,$09,$00,$09,$00,$09,$00,$09,$00,$09,$00,$09,$00,$09,$70
        .byte   $09,$56,$09,$71,$09,$72,$09,$73,$09,$74,$09,$75,$09,$76,$09,$77
        .byte   $09,$78,$09,$79,$09,$7A,$09,$79,$09,$7B,$09,$7C,$09,$7D,$09,$08
        .byte   $09,$7E,$09,$7F,$19,$00,$19,$01,$19,$02,$19,$03,$19,$04,$19,$05
        .byte   $19,$06,$09,$00,$09,$00,$09,$00,$09,$00,$09,$00,$09,$00,$09,$00
; Row 11
        .byte   $09,$00,$09,$00,$09,$00,$09,$00,$09,$00,$09,$00,$09,$00,$09,$00
        .byte   $19,$07,$19,$08,$19,$09,$09,$74,$09,$72,$19,$0A,$19,$0B,$19,$0C
        .byte   $19,$0D,$19,$0E,$19,$0F,$19,$10,$19,$11,$19,$12,$19,$13,$19,$14
        .byte   $19,$15,$19,$16,$19,$17,$19,$18,$19,$19,$19,$1A,$19,$1B,$19,$1C
        .byte   $09,$00,$09,$00,$09,$00,$09,$00,$09,$00,$09,$00,$09,$00,$09,$00
; Row 12
        .byte   $19,$1D,$19,$1D,$19,$1D,$19,$1D,$19,$1D,$19,$1D,$19,$1D,$19,$1D
        .byte   $19,$1D,$19,$1E,$19,$1F,$19,$3B,$19,$21,$19,$22,$19,$22,$19,$23
        .byte   $19,$24,$19,$25,$19,$25,$19,$0F,$09,$3E,$19,$26,$19,$26,$19,$27
        .byte   $19,$28,$19,$29,$19,$2A,$19,$2B,$19,$2B,$19,$2B,$19,$21,$19,$1D
        .byte   $19,$1D,$19,$1D,$19,$1D,$19,$1D,$19,$1D,$19,$1D,$19,$1D,$19,$1D
; Row 13
        .byte   $09,$00,$09,$00,$09,$00,$09,$00,$09,$00,$09,$00,$09,$00,$09,$00
        .byte   $09,$00,$09,$00,$09,$00,$09,$00,$09,$00,$09,$00,$09,$00,$09,$00
        .byte   $09,$00,$09,$00,$09,$00,$09,$00,$09,$00,$09,$00,$09,$00,$09,$00
        .byte   $09,$00,$09,$00,$09,$00,$09,$00,$09,$00,$09,$00,$09,$00,$09,$00
        .byte   $09,$00,$09,$00,$09,$00,$09,$00,$09,$00,$09,$00,$09,$00,$09,$00
; Row 14
        .byte   $09,$00,$09,$00,$09,$00,$09,$00,$09,$00,$09,$00,$09,$00,$09,$00
        .byte   $09,$00,$09,$00,$09,$00,$09,$00,$09,$00,$09,$00,$09,$00,$09,$00
        .byte   $09,$00,$09,$00,$09,$00,$09,$00,$09,$00,$09,$00,$09,$00,$09,$00
        .byte   $09,$00,$09,$00,$09,$00,$09,$00,$09,$00,$09,$00,$09,$00,$09,$00
        .byte   $09,$00,$09,$00,$09,$00,$09,$00,$09,$00,$09,$00,$09,$00,$09,$00
; Row 15
        .byte   $09,$00,$09,$00,$09,$00,$09,$00,$09,$00,$09,$00,$09,$00,$09,$00
        .byte   $09,$00,$09,$00,$09,$00,$09,$00,$09,$00,$09,$00,$09,$00,$09,$00
        .byte   $09,$00,$09,$00,$09,$00,$09,$00,$09,$00,$09,$00,$09,$00,$09,$00
        .byte   $09,$00,$09,$00,$09,$00,$09,$00,$09,$00,$09,$00,$09,$00,$09,$00
        .byte   $09,$00,$09,$00,$09,$00,$09,$00,$09,$00,$09,$00,$09,$00,$09,$00
; Row 16
        .byte   $09,$00,$09,$00,$09,$00,$09,$00,$09,$00,$09,$00,$19,$2C,$19,$2D
        .byte   $19,$2E,$19,$2F,$19,$30,$19,$2E,$19,$31,$19,$32,$19,$33,$19,$34
        .byte   $19,$2F,$19,$35,$09,$00,$19,$36,$19,$2F,$19,$2F,$19,$2F,$19,$37
        .byte   $19,$2F,$19,$2F,$19,$38,$19,$39,$19,$2F,$19,$35,$19,$3A,$19,$2F
        .byte   $19,$3C,$09,$00,$09,$00,$09,$00,$09,$00,$09,$00,$09,$00,$09,$00
; Row 17
        .byte   $09,$00,$09,$00,$09,$00,$09,$00,$09,$00,$09,$00,$19,$3D,$19,$3E
        .byte   $19,$3F,$19,$40,$19,$41,$19,$42,$19,$43,$19,$44,$19,$45,$19,$46
        .byte   $19,$47,$19,$48,$09,$00,$19,$49,$19,$4A,$19,$4B,$19,$4C,$19,$4D
        .byte   $19,$4E,$19,$04,$19,$4F,$09,$00,$19,$47,$19,$48,$19,$50,$19,$51
        .byte   $19,$52,$09,$00,$09,$00,$09,$00,$09,$00,$09,$00,$09,$00,$09,$00
; Row 18
        .byte   $09,$00,$09,$00,$09,$00,$09,$00,$09,$00,$09,$00,$19,$53,$19,$54
        .byte   $09,$00,$19,$55,$19,$56,$19,$57,$09,$00,$19,$58,$19,$59,$09,$00
        .byte   $19,$47,$19,$48,$09,$00,$09,$00,$19,$5A,$19,$5B,$09,$00,$09,$00
        .byte   $19,$5C,$19,$5D,$19,$5E,$09,$00,$19,$47,$19,$48,$19,$5F,$19,$60
        .byte   $19,$61,$19,$62,$09,$00,$09,$00,$09,$00,$09,$00,$09,$00,$09,$00
; Row 19
        .byte   $09,$00,$09,$00,$09,$00,$09,$00,$09,$00,$19,$63,$19,$64,$09,$00
        .byte   $09,$31,$19,$65,$19,$66,$19,$67,$19,$68,$19,$69,$0E,$00,$19,$6A
        .byte   $19,$47,$19,$48,$19,$6B,$19,$6C,$19,$5A,$19,$5B,$09,$00,$09,$00
        .byte   $19,$5C,$19,$5F,$19,$67,$09,$00,$19,$47,$19,$48,$19,$6D,$19,$6E
        .byte   $19,$6F,$19,$70,$09,$00,$09,$00,$09,$00,$09,$00,$09,$00,$09,$00
; Row 20
        .byte   $09,$00,$09,$00,$09,$00,$09,$00,$09,$00,$09,$00,$19,$71,$19,$72
        .byte   $19,$73,$19,$74,$09,$00,$19,$75,$19,$76,$19,$77,$19,$72,$19,$78
        .byte   $19,$79,$19,$7A,$19,$7B,$19,$7C,$19,$7D,$19,$7E,$19,$7F,$19,$7D
        .byte   $19,$7E,$19,$7F,$19,$75,$19,$76,$19,$79,$19,$46,$19,$49,$19,$72
        .byte   $19,$74,$09,$00,$09,$00,$09,$00,$09,$00,$09,$00,$09,$00,$09,$00
; Row 21
        .byte   $09,$00,$09,$00,$09,$00,$09,$00,$09,$00,$09,$00,$09,$00,$09,$00
        .byte   $09,$00,$09,$00,$09,$00,$09,$00,$09,$00,$09,$00,$09,$00,$09,$00
        .byte   $09,$00,$09,$00,$09,$00,$09,$00,$09,$00,$09,$00,$09,$00,$09,$00
        .byte   $09,$00,$09,$00,$09,$00,$09,$00,$09,$00,$09,$00,$09,$00,$09,$00
        .byte   $09,$00,$09,$00,$09,$00,$09,$00,$09,$00,$09,$00,$09,$00,$09,$00
; Row 22
        .byte   $09,$00,$09,$00,$09,$00,$09,$00,$09,$00,$09,$00,$09,$00,$09,$00
        .byte   $09,$00,$09,$00,$09,$00,$09,$00,$09,$00,$09,$00,$09,$00,$09,$00
        .byte   $09,$00,$09,$00,$09,$00,$09,$00,$09,$00,$09,$00,$09,$00,$09,$00
        .byte   $09,$00,$09,$00,$09,$00,$09,$00,$09,$00,$09,$00,$09,$00,$09,$00
        .byte   $09,$00,$09,$00,$09,$00,$09,$00,$09,$00,$09,$00,$09,$00,$09,$00
; Row 23
        .byte   $09,$00,$09,$00,$09,$00,$09,$00,$09,$00,$09,$00,$09,$00,$09,$00
        .byte   $09,$00,$09,$00,$09,$00,$09,$00,$09,$00,$09,$00,$09,$00,$09,$00
        .byte   $09,$00,$09,$00,$09,$00,$09,$00,$09,$00,$09,$00,$09,$00,$09,$00
        .byte   $09,$00,$09,$00,$09,$00,$09,$00,$09,$00,$09,$00,$09,$00,$09,$00
        .byte   $09,$00,$09,$00,$09,$00,$09,$00,$09,$00,$09,$00,$09,$00,$09,$00
; Row 24
        .byte   $09,$00,$09,$00,$09,$00,$09,$00,$09,$00,$09,$00,$09,$00,$09,$00
        .byte   $09,$00,$09,$00,$09,$00,$09,$00,$09,$00,$09,$00,$09,$00,$09,$00
        .byte   $09,$00,$09,$00,$09,$00,$09,$00,$09,$00,$09,$00,$09,$00,$09,$00
        .byte   $09,$00,$09,$00,$09,$00,$09,$00,$09,$00,$09,$00,$09,$00,$09,$00
        .byte   $09,$00,$09,$00,$09,$00,$09,$00,$09,$00,$09,$00,$09,$00,$09,$00

; ============================================================================
; SELECTION DES FONCTIONS DE L'API (pseudo-editeur de liens de mixt_api.asm)
; Ce bloc doit rester juste avant le #include final.
; ============================================================================
#DEFINE Finit_vdp
#DEFINE Finit_textapi
#DEFINE Fset_25LINE
#DEFINE Fset_vidbuf
#DEFINE Fset_screen_adr
#DEFINE Fset_MIXTMODE
#DEFINE Fset_window
#DEFINE Fcls
#DEFINE Flocate
#DEFINE Fput_char
#DEFINE Fput_text
#DEFINE Fset_acmpxy
#DEFINE Fcalcul_pointer

#include "mixt_api.asm"
#include "INTmusic.asm"
        .end
