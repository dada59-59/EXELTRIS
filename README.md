04/09/2026
-----------------------------------------
EXELTRIS : Jeux de type puzzle en mouvement pour Exelvision : EXL100 / EXELTEL

Développé en assembleur par IA, fonctionnel sur EXL100 et EXELTEL ainsi que dans les émulateurs 

- exeltris.asm => fichier source
- exeltris.rom => rom utilisable dans l'émulateur ou à charger en cartouche
- exeltris.cram => fichier EXELMEMOIRE à charger dans l'emulateur
- exeltris.k7 => fichier K7 pour émulateur, à charger à partir de l'exelmémoire : BKP => (1) TAPE -> CRAM, CRAM NAME=TRIS, lancement sous basic par CALL EXEC(32772)
- exeltris.waw => fichier waw pour chargement par lecteur cassette, à charger à partir de l'exelmémoire : BKP => (1) TAPE -> CRAM, CRAM NAME=TRIS, lancement sous basic par CALL EXEC(32772)
- exeltris.fd => fichier image disquette pour émulateur, le fichier tools-exeltris.fd contient les outils l'outils EXEC pour lancer le jeu par EXEC TRIS

-----------------------------------------
Crédits : Merci aux valeureux partisans des systèmes obscures : 
Jester pour le dev kit et les outils : http://dcexel.free.fr/outils/index.html 
Les superbes sites http://dcexel.free.fr/ avec l'emulateur Exl100/Exeltel 
et https://www.ti99.com/exelvision/website/ 
les membres actifs du forum : https://forum.system-cfg.com/ 
Brett Hallen pour les pcb de cartouche : https://github.com/BrettHallen/Exelvision/tree/main

