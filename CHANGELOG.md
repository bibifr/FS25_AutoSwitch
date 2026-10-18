# Changelog

| Version | Changements |
| --- | --- |
| 1.0.0.61 | Mini-météo à gauche de l'horloge du jeu : temps et température actuels, mini / maxi du jour, prochain changement avec son heure et la pluie attendue. Déplaçable à la souris (curseur visible), position gardée ; un clic ouvre la fenêtre Météo. Option dans le menu AutoSwitch pour l'afficher ou la cacher |
| 1.0.0.60 | Météo : heures arrondies au quart d'heure (13h00 au lieu de 13h01), « Prochain changement » ne chevauche plus sa valeur, jours des changements écrits J+1, J+2..., bouton X en haut à droite pour fermer (le curseur de la souris s'affiche avec la fenêtre) |
| 1.0.0.59 | Fenêtre Météo (Ctrl droit + M, à pied ou en véhicule, modifiable dans les commandes) : temps actuel (température, vent et direction, pluie en cours, humidité du sol, prochain changement), les 24 prochaines heures par tranches de 3 h, les changements à venir avec leur heure, leur durée et la pluie attendue, et les jours suivants (mini / maxi, cumul de pluie). Prévisions réelles du jeu ; les millimètres sont estimés d'après l'intensité |
| 1.0.0.58 | Tractor Terrain Dynamics accepté sous le nom de la bêta KingMods (FS25_TTD_v3_7_BETA.zip) : plus besoin de le renommer. TTD retiré des dépendances du modDesc (le jeu réclamait en plus la version ModHub 1.0.0.0, refusée ensuite par le contrôle de version). Si deux TTD sont installés, le plus récent est utilisé |
| 1.0.0.57 | Icône d'ensileuse sur le HUD (dessin de Fabien), la moissonneuse garde la sienne |
| 1.0.0.56 | Transmission réelle de chaque machine lue dans les différentiels utilisés par le jeu (après MoreRealistic) : 4x4, pont avant seul ou pont arrière seul. Chaque machine est notée dans modSettings/FS25_AutoSwitch/transmissions.xml, l'attribut forced (4x4 / front / rear) corrige une machine à la main. Remplace la règle « moissonneuses en pont avant seul » de la 1.0.0.55 |
| 1.0.0.55 | Moissonneuses et ensileuses toujours gérées en pont avant seul, même si le mod déclare un 4x4 (Lexion 6900 : l'arrière restait à 0 % de patinage en 4x4) |
| 1.0.0.54 | Moissonneuses, ensileuses et machines 4x2 (sans différentiel central) : HUD avec une icône de moissonneuse (dessin de Fabien) ou le tracteur en 4x2, et le patinage des roues motrices, seul le pont moteur se bloque (à la main ou en AUTO), blocage de l'autre pont annulé, pas de 4x2 / 4x4, braquage complet |
| 1.0.0.53 | Différentiels, 4x2 / 4x4, braquage et tracteur du HUD réservés aux vrais 4x4 (différentiel central) : moissonneuses et machines 4x2 laissées telles quelles (avant, AutoSwitch les croyait en 4x4 et réduisait leur braquage) |
| 1.0.0.51 | En MANUEL avec un blocage engagé, les roues braquent à fond à l'écran mais le tracteur ne tourne qu'au seuil du blocage (50 % AR, 20 % AV, 10 % les deux) : il ripe |
| 1.0.0.50 | Touche Ctrl droit + Flèche haut (modifiable dans les commandes) : différentiels et transmission en AUTO ou MANUEL, mode écrit au-dessus du tracteur et enregistré. En MANUEL, AutoSwitch ne touche plus aux différentiels ni au 4x2 / 4x4, un blocage engagé ne se coupe plus en virage, le braquage est réduit à son seuil (50 % AR, 20 % AV, 10 % les deux). Retour en AUTO quand AutoDrive ou Courseplay prend la main (option du menu, activée par défaut) |
| 1.0.0.49 | Contrôle des mods : un mod requis installé mais pas activé dans la partie (case décochée dans la sélection des mods) est signalé en jeu au chargement, avec son nom, et dans log.txt. AutoSwitch démarre quand même |
| 1.0.0.48 | Herbe piétinée plus douce : sur sol sec à partir de 11 km/h, sur sol humide à partir de 7 km/h, un seul stade de pousse en moins |
| 1.0.0.47 | Herbe piétinée corrigée (zone sous la roue), le stade le plus bas est coupé |
| 1.0.0.46 | Herbe détruite au passage des roues : la pousse recule au lieu du fauchage de Mud System Physics (selon la vitesse et l'humidité du sol). Crop Destruction Overhaul n'est plus requis |
| 1.0.0.45 | Usure des pneus : Real Physics - Tire Wear (Reifenverschleiß 1.2.2.67, requis) remplace Use Your Tyres (plus requis). L'adhérence du sol du jeu est gardée et la perte d'usure s'applique par-dessus ; un pneu usé accroche mieux sur route (effet slick) ; la case usure de Tractor Terrain Dynamics suit Reifenverschleiß |
| 1.0.0.44 | Correctif urgent de la 1.0.0.43 : le jeu refusait d'enregistrer les véhicules au chargement (« Failed to register vehicle! »). Ne pas sauvegarder une partie chargée avec la 1.0.0.43 |
| 1.0.0.43 | Palettes de pneus : plus de chute de FPS avec plusieurs palettes côte à côte. La liste des palettes est gardée en mémoire et refaite seulement à l'achat, la pose, la vente ou la suppression d'une palette ; les groupes ne sont recalculés que si une palette a bougé. Pneus des palettes cachés au-delà de 200 m (600 m avant) |
| 1.0.0.42 | Patinage : chaque roue est comparée à sa propre vitesse au sol (en virage, les roues avant et extérieures ne comptent plus comme patinant, jusqu'à 40 % avant), pour l'affichage et le blocage des différentiels ; en 4x2, pas de patinage affiché sur les roues avant libres |
| 1.0.0.41 | Dormir : avec des jours, réveil à 8 h le dernier jour (+ les heures choisies). Joueur bloqué au réveil après plusieurs jours corrigé : la fenêtre « Nouvelles du marché » de Dynamic Market, ouverte au changement de mois pendant le sommeil, restait invisible et gardait les touches ; elle s'affiche maintenant au réveil. Le réveil passe par le jeu lui-même |
| 1.0.0.38 | Lumières : les halos des phares, feux et gyros des autres véhicules sont 2 fois plus lumineux (réglable dans le menu, x1 = jeu de base). Le véhicule conduit et ses outils ne changent pas |
| 1.0.0.37 | Lumières : les phares, feux et gyros des autres véhicules restent visibles 5 fois plus loin (réglable dans le menu, x1 = jeu de base). L'éclairage au sol ne change pas |
| 1.0.0.36 | Affichage : le tracteur et la plage de vitesse sont deux blocs séparés, déplaçables chacun à la souris (position gardée) ; plus de cadre orange quand le curseur est visible |
| 1.0.0.35 | Affichage : l'icône de patinage devient le tracteur vu de dessus (pont AV / AR bloqué en rouge, transmission 4x4 en vert, selon Enhanced Vehicle), avec le patinage de chaque roue ; un pont bloqué n'affiche plus qu'un patinage, centré sur le pont |
| 1.0.0.34 | Transmission : 4x2 seulement sur le dur (route goudronnée, béton), 4x4 sur les chemins de gravier, de terre, l'herbe et le sable comme dans les champs |
| 1.0.0.33 | Menu Dormir en deux curseurs avec leur titre : « Temps en heures » (+0 à +23 h, +0 h par défaut) et « Temps en jours » (+0 à +7, +1 jour par défaut), cumulés. Fenêtre agrandie |
| 1.0.0.32 | Menu Dormir : la liste propose +1 h à +23 h, puis 1 à 7 jours (au lieu d'une heure de réveil, 24 h au plus). Les jours passent normalement pendant le sommeil |
| 1.0.0.31 | Nouvelles icônes du magasin pour les palettes de pneus AR et AV |
| 1.0.0.30 | Contrôle des versions corrigé : la 1.0.0.29 déclarait « introuvables » les mods requis chargés après AutoSwitch (tous sauf AutoDrive) et désactivait AutoSwitch à tort |
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
