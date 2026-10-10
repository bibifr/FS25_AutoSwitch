# Changelog

| Version | Changements |
| --- | --- |
| 1.0.0.29 | Mud System Physics 1.3.6 et Tractor Terrain Dynamics 1.0.3.7 (bêta). Pont MSP → TTD : au champ, TTD reçoit l'humidité locale de MSP, et le frein de boue, la perte d'adhérence et la charge moteur de MSP sont coupés quand TTD gère le véhicule (plus de résistance en double). Chemins mouillés : pénalité du préréglage « Difficile » de TTD retirée. Calibrateur de TTD bloqué (Ctrl+C et clic molette prenaient les commandes). Contrôle des versions : si un mod requis est plus ancien que la version minimale, AutoSwitch ne démarre pas et l'indique en jeu et dans log.txt |
| 1.0.0.25 | Menu : ligne « Différentiels : déblocage en virage » retirée. La coupure des blocages selon le braquage et le refus roues braquées sont toujours actifs |
| 1.0.0.24 | Nouvelle icône du mod : pneu de tracteur avec « AS » au centre, aux couleurs vert / jaune |
| 1.0.0.23 | Adhérence : le bonus de Variable Tire Pressure en champ (x2,5 par défaut, jusqu'à x5 en jumelées) est ramené à +15 % (+20 % en jumelées), VTP reste actif. Une roue dont le jeu ne donne pas le type de sol (vu sur les roues arrière d'un Fendt 942) a maintenant aussi sa perte en sol humide. Relevé de la 1.0.0.22 retiré du log |
| 1.0.0.22 | Version de test : relevé d'adhérence dans log.txt toutes les 5 s pour le véhicule conduit (humidité sous chaque roue, facteur AutoSwitch, bonus Variable Tire Pressure, jumelées, patinage) |
| 1.0.0.21 | Différentiels séparés : l'arrière se bloque à 15 % de patinage, l'avant à 30 % (deux réglages dans le menu), chacun se débloque à la moitié de son seuil. Bonus des blocages fixe, +4 % roues AR et +3 % roues AV (case du menu retirée). Adhérence en sol humide sur 5 niveaux : Débutant, Facile, Normal (ancienne « Très forte », par défaut), Dur, Extrême |
| 1.0.0.20 | Les blocages ne brident plus le braquage : ils se coupent au-delà de 50 % du braquage (arrière seul), 20 % (avant seul) ou 10 % (les deux), y compris posés à la main, et AutoSwitch ne les remet qu'une fois les roues revenues sous ce seuil. Blocage demandé roues braquées refusé, avec icône rouge clignotante et « Redressez les roues ». Seule la transmission limite le braquage (4x4 90 %) |
| 1.0.0.19 | Braquage en 4x4 à 90 % (au lieu de 80 %). Les blocages posés par AutoSwitch ne se remettent qu'une fois les roues revenues dans l'angle permis avec les blocages (10 % pour les deux diffs) |
| 1.0.0.18 | Braquage limité selon la transmission et les blocages (Enhanced Vehicle) : 4x2 complet, 4x4 80 %, blocage AR seul 50 %, AV seul 20 %, les deux 10 %. Volant en butée sur cette limite = virage : les blocages posés par AutoSwitch sautent comme au-delà de 15° |
| 1.0.0.17 | Pneus : au moins 1 h de route pour qu'ils se nettoient (1 h à 2 h 10 selon la vitesse) |
| 1.0.0.16 | Pneus : environ 1 h de route pour qu'ils se nettoient (35 à 70 minutes selon la vitesse) |
| 1.0.0.15 | Pneus : nettoyage en roulant encore 4 fois plus long (40 fois moins vite que Mud System Physics d'origine, 8 à 17 minutes de route) |
| 1.0.0.14 | Pneus : la saleté part 10 fois moins vite en roulant. Mud System Physics nettoyait un pneu en 12 à 26 s dès qu'il quittait la boue (pneus à 10-30 % dans la sauvegarde pour une carrosserie à 100 %) ; il faut maintenant 2 à 4 minutes. L'eau, la pluie et le lavage nettoient normalement |
| 1.0.0.13 | Vitesse AutoDrive réglable par tranches de 2 km/h (champ 4 à 30, chemins 10 à 50, route sans limite ou 20 à 80) |
| 1.0.0.12 | Traces de pneus : 60 000 points gardés au lieu de 20 000 ; sauvegarde des ornières DynamicDrivePro retirée (DDP ne creuse jamais le sol, le relief des traces vient du jeu et ne peut pas être gardé) |
| 1.0.0.11 | Pneus de nouveau salis par la boue : les réglages Mud System Physics imposés à chaque chargement reprennent ceux de la partie avant la 1.0.0.01 (humidité locale des champs réactivée, saleté des profils de sol, difficulté 2, etc.) |
| 1.0.0.10 | Arbitrage : le mod d'un crochet est reconnu dans le même ordre que ModMixer (mod en cours de chargement d'abord) ; liste des crochets bloqués écrite dans le log |
| 1.0.0.09 | Correctif : outils stables (1.0.0.04), boue sur roues sans frein (1.0.0.06) et ornières (1.0.0.08) ne trouvaient pas Mud System Physics ni DynamicDrivePro (lecture dans le mauvais environnement Lua) et restaient inactifs |
| 1.0.0.08 | Ornières de DynamicDrivePro gardées : AutoSwitch fait écrire savegameX/reaTerrainDepth.xml à chaque sauvegarde (DDP ne l'écrivait jamais), DDP recreuse le terrain au chargement |
| 1.0.0.07 | Arbitrage des mods repris de ModMixer : MoreRealistic bloqué sur updateWheelsPhysics, updateTireFriction et serverUpdate, Use Your Tyres sur updateTireFriction, DynamicDrivePro sur serverUpdate, Highlands Fishing Pack sur updateVehiclePhysics ; pédales Recovery Winch sous Enhanced Vehicle ; garde-fou remorque sans côté de bennage. Inactif tant que ModMixer est installé |
| 1.0.0.06 | Boue : la résistance de Mud System Physics s'applique aussi aux roues sans frein (remorques, outils) avec MoreRealistic, qui l'ignorait ; le frein du tracteur n'y est jamais transmis |
| 1.0.0.05 | Adhérence : AutoSwitch respecte les blocages ModMixer (MoreRealistic, Use Your Tyres) sur WheelPhysics.updateTireFriction ; facteur sol humide et usure appliqués sec ou humide, sans saut ; crevaison et pression Mud System Physics conservées |
| 1.0.0.04 | Outils stables à l'arrêt : rayon des roues figé (dételés, ou attelage arrêté sans conducteur), plus de sautillement Mud System Physics + MoreRealistic |
| 1.0.0.03 | Traces de pneus gardées avec la sauvegarde (savegameX/autoSwitchTireTracks.xml) et redessinées au chargement |
| 1.0.0.02 | Réglages Mud System Physics repris de la dernière sauvegarde (effacement des cultures et crevaisons activés, pression des pneus MSP désactivée) |
| 1.0.0.01 | Vitesse AutoDrive selon le terrain (champ / chemin / route), réglable par tranches de 5 km/h ; réglages Mud System Physics appliqués à chaque chargement et retirés du menu ; ressemis direct permanent ; réglages de position et de maxi de la plage de vitesse retirés du menu |
| 1.0.0.0 | Première version publique (KingMods) |
| 3.5.0 | Regonflage automatique de VTP à 30 km/h désactivé (les pneus restent dégonflés au champ) |
| 3.4.0 | Marqueur jaune du jeu (icône atelier) à la place du poteau sur le repère joueur |
| 3.3.1 | Minuteur plus petit ; jumelées cachées dès leur création ; fin de démontage synchronisée avec la palette |
| 3.3 | Une seule zone et un seul repère pour des palettes côte à côte ; minuteur à droite de l'écran ; contour de zone épaissi |
| 3.2.1 | Repère « Placez-vous ici » ; ordre des pneus corrigé (avant d'abord) |
| 3.2 | Fenêtres à valider avec explications quand le changement est impossible |
| 3.1 | Zone de montage au sol (rouge / vert), visible à pied et au volant |
| 3.0 | Jumelées qui apparaissent / disparaissent pneu par pneu sur le tracteur ; tracteur verrouillé pendant le chantier |
| 2.9 | Fenêtre de confirmation ; jumelées obligatoirement dans la marque des pneus actuels |
| 2.8 | Palettes au menu construction ; 15 min de jeu par pneu |
| 2.7 | Palettes AR (650/65R42) et AV (540/65R30) BKT ; jumelées reconnues aussi par le nom de configuration |
| 2.4 – 2.6 | Première palette de jumelées (Ctrl droit + I à pied), mémoire des pneus d'origine, montage en temps de jeu, sauvegarde avec la partie |
| 2.2 – 2.3 | Largeur réelle des jumelées pour Mud System Physics, adhérence humide en jumelées, correctif VTP pour les pneus à variantes de marques |
| 2.1 | Différentiels remis débloqués au chargement de la partie |
| 2.0 | Mod renommé FS25_AutoSwitch, code découpé en modules |
| 1.x | Pneus et différentiels automatiques, alerte de patinage, plage de vitesse conseillée, protection du semis, adhérence en sol humide, bonus de traction, usure Use Your Tyres, ressemis direct, paramètres de boue conseillés |
