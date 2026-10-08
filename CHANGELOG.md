# Changelog

| Version | Changements |
| --- | --- |
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
