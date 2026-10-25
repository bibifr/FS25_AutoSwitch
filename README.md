<img width="2056" height="765" alt="ChatGPT Image 22 oct  2026, 17_12_23" src="https://github.com/user-attachments/assets/bc467ab8-f289-47a8-91c0-67e536e2cdfd" />


### Discord https://discord.gg/S7gGzqnSEp
## LAST VERSION AUTOSWITCH https://github.com/bibifr/FS25_AutoSwitch/releases/latest/download/FS25_AutoSwitch.zip
## ADDON Autodrive for some Forget function https://github.com/bibifr/FS25_AutoDriveAddon/releases

# FS25 AutoSwitch

**Version 1.0.2.0** · Farming Simulator 25 · Auteur : Fabien · FR / EN / DE

## French

Mod compagnon qui automatise **la pression des pneus et les différentiels** et rend **la traction réaliste**, en faisant travailler ensemble Variable Tire Pressure, Enhanced Vehicle, MoreRealistic, Mud System Physics et Tractor Terrain Dynamics, sans modifier ces mods. Il ajoute aussi une palette de pneu pour changement de pneu.
Objectif: Rendre le jeux plus realiste et performant

> 🇬🇧 [English version below](#english)

## Fonctionnalités

| Domaine | Ce que fait AutoSwitch |
| --- | --- |
| Pression des pneus | Avec AutoDrive / Courseplay : dégonflage au champ, gonflage sur route. En conduite manuelle : Automatique ou Manuel. Le regonflage automatique de VTP à 30 km/h est désactivé. |
| Différentiels (Enhanced Vehicle) | Blocage AR puis AV selon le patinage (seuils réglables, 15 % et 30 % par défaut), déblocage à la moitié du seuil, 4x2 sur goudron et béton seulement, 4x4 partout ailleurs (champs, chemins), braquage 90 % en 4x4, blocages coupés au-delà de 50 % du braquage (AR seul), 20 % (AV seul) ou 10 % (les deux) et refusés roues braquées, remise à zéro au chargement. Touche Ctrl droit + Flèche haut : mode AUTO / MANUEL (affiché au-dessus du tracteur) ; en MANUEL, vous gérez différentiels et 4x2 / 4x4, un blocage engagé ne se coupe plus et le tracteur ne tourne qu'à son seuil (roues braquées à fond, il ripe) ; retour en AUTO quand AutoDrive ou Courseplay prend la main (désactivable). Transmission réelle de chaque machine lue (après MoreRealistic) et notée dans modSettings/FS25_AutoSwitch/transmissions.xml (corrigeable à la main). Machines sans 4x4 (moissonneuses, ensileuses, 4x2) : braquage complet, pas de 4x2 / 4x4, seul le pont moteur se bloque, icône moissonneuse sur le HUD. |
| Adhérence (MoreRealistic) | Perte d'adhérence en sol humide (Débutant, Facile, Normal, Dur, Extrême), bonus Variable Tire Pressure en champ ramené à +15 % (+20 % en jumelées), bonus fixe quand les différentiels sont bloqués (+4 % roues AR, +3 % roues AV), usure de Real Physics - Tire Wear appliquée par-dessus l'adhérence du sol, un pneu usé accroche mieux sur route (effet slick). |
| Roues jumelées | Largeur réelle prise en compte par Mud System Physics, meilleure adhérence en sol humide, correctif VTP pour les pneus à variantes de marques. |
| Palettes de jumelées | Palettes AR (BKT 650/65R42, 4 500 €) et AV (BKT 540/65R30, 3 500 €) en boutique et au menu construction. Montage / démontage pneu par pneu (15 min de jeu par pneu), zone de stationnement au sol, repère joueur, minuteur, tracteur verrouillé pendant le chantier. |
| Affichage | Plage de vitesse conseillée (déplaçable à la souris) et tracteur vu de dessus près du compteur (ponts bloqués, 4x4, patinage de chaque roue ou par pont bloqué), alerte de patinage. |
| Semis | Protection du semis, remplissage du semoir couvercle fermé, ressemis direct sur bandes écrasées. |
| Vitesse AutoDrive | Vitesse imposée selon le terrain : 20 km/h au champ, 30 km/h sur les chemins, sans limite sur la route. Réglable par tranches de 2 km/h dans les paramètres. |
| Boue | Réglages Mud System Physics du mod (profils de sol compris) + TTD en « Difficile », appliqués automatiquement à chaque chargement. Pont MSP → TTD : au champ, TTD reçoit l'humidité locale de Mud System Physics et la résistance n'est pas appliquée deux fois. Chemins mouillés : la pénalité « Difficile » de TTD est retirée (chemins à nouveau praticables). Calibrateur de TTD bloqué (Ctrl+C et clic molette). |
| Traces de pneus | Gardées avec la sauvegarde et redessinées au chargement (60 000 points les plus récents, solo ou hôte). |
| Saleté des pneus | Les pneus salis par la boue mettent au moins 1 h de route à se nettoyer (1 h à 2 h 10 selon la vitesse) ; l'eau, la pluie et le lavage les nettoient normalement. |
| Outils stables | Rayon des roues figé sur les outils à l'arrêt : plus de sautillement dû à Mud System Physics + MoreRealistic. |
| Boue sur roues sans frein | La résistance de boue de Mud System Physics freine aussi les roues sans frein (remorques, outils) avec MoreRealistic. |
| Arbitrage des mods | AutoSwitch bloque ou ordonne lui-même les crochets en conflit (MoreRealistic, DynamicDrivePro, Enhanced Vehicle, Recovery Winch), sans désactiver aucun mod. ModMixer n'est plus nécessaire. |
| Dormir | Deux curseurs dans la fenêtre Dormir : temps en heures (+0 à +23 h) et temps en jours (+0 à +7), cumulés. Plus de limite de 24 h ; avec des jours, réveil à 8 h. Les jours passent normalement (cultures, ventes, salaires). |

## Utiliser les palettes de jumelées

1. Poser la palette AR (et AV pour l'avant) côte à côte.
2. Garer le tracteur dans le rectangle au sol (rouge, puis vert quand il est bien placé).
3. À pied, se placer sur le marqueur jaune et appuyer sur **Ctrl droit + I**, puis confirmer.
4. Démontage : même chose avec des palettes **vides** ; les pneus d'origine sont remis.

Les jumelées doivent exister dans la **même marque de pneus** que ceux du tracteur. Changement de roues : **solo uniquement**.

## Mods requis

- [Variable Tire Pressure](https://www.farming-simulator.com/mod.php?mod_id=347991&title=fs2025) : version 1.0.0.13 minimum
- [Enhanced Vehicle](https://github.com/ZhooL/FS25_EnhancedVehicle/releases) : version 1.1.7.1 minimum
- [AutoDrive](https://github.com/Stephan-S/FS25_AutoDrive/releases) : version 3.0.1.4 minimum
- [Courseplay](https://github.com/Courseplay/Courseplay_FS25/releases) : version 8.1.0.3 minimum
- [MoreRealistic](https://github.com/quadural/MoreRealistic_FS25/blob/main/MoreRealistic.zip) : version 0.26.09.13 minimum
- [MoreRealistic XML Databank](https://github.com/quadural/MoreRealistic_FS25/blob/main/moreRealisticXmlDatabank.zip) : version 1.0.0.1 minimum
- [Mud System Physics](https://www.kingmods.net/en/fs25/mods/73208/mud-system-physics) : version 1.3.6.0 minimum
- [Tractor Terrain Dynamics](https://www.kingmods.net/en/fs25/mods/78890/tractor-terrain-dynamics) : version 1.0.3.7 minimum (bêta). Le zip peut garder son nom KingMods (FS25_TTD_v3_7_BETA.zip) ; n'installer qu'un seul TTD.
- [DynamicDrive Pro](https://www.farming-simulator.com/mod.php?mod_id=352451&title=fs2025) : version 1.0.1.0 minimum 
- [Realistic Harvesting](https://github.com/exekx/FS25_RealisticHarvesting/releases) : version 1.6.0.0 minimum
- [Moisture System](https://www.farming-simulator.com/mod.php?mod_id=354130&title=fs2025) : version 2.0.0.8 minimum

AutoSwitch fait partie d'un ensemble réaliste global : ces mods sont prévus, au moins dans la version indiquée. S'il en manque un (absent, pas activé ou plus ancien), AutoSwitch démarre quand même, sans les fonctions qui dépendent de ce mod, et un cadre en bas à gauche de l'écran liste les mods manquants.

## Installation

1. Télécharger `FS25_AutoSwitch.zip` dans la section **Releases**.
2. Le copier **sans le dézipper** dans `Documents/My Games/FarmingSimulator2025/mods`.
3. L'activer avec les mods requis. Réglages : **Paramètres > Général > AutoSwitch**.

## Limites connues

- Changement de roues en solo uniquement ; petit gel pendant le rechargement du tracteur (plus long avec des outils attelés).
- Un tracteur sans configuration jumelées dans son fichier ne peut pas en recevoir.

---

## English

**Version 1.0.0.57** · Farming Simulator 25 · Author: Fabien · FR / EN / DE

Companion mod that automates **tire pressure and differential locks** and makes **traction realistic** by making Variable Tire Pressure, Enhanced Vehicle, MoreRealistic, Mud System Physics and Tractor Terrain Dynamics work together, without modifying any of them. It also adds **dual-wheel racks** mounted tire by tire.
Objective: Make game more realistic 

### Features

| Area | What AutoSwitch does |
| --- | --- |
| Tire pressure | With AutoDrive / Courseplay: deflate in the field, inflate on the road. Manual driving: Automatic or Manual mode. VTP's automatic re-inflation at 30 km/h is disabled. |
| Differentials (Enhanced Vehicle) | Rear then front lock depending on wheel slip (adjustable thresholds, 15 % and 30 % by default), unlock at half the threshold, 2WD on asphalt and concrete only, 4WD everywhere else (fields, tracks), 90 % steering in 4WD, locks released beyond 50 % of full steering (rear only), 20 % (front only) or 10 % (both) and refused with the wheels turned, reset on game load. Right Ctrl + Up arrow: AUTO / MANUAL mode (shown above the tractor); in MANUAL you handle the differentials and 2WD / 4WD, an engaged lock is never released and the tractor only turns up to its limit (wheels turned fully, it slides); back to AUTO when AutoDrive or Courseplay takes over (can be turned off). Actual drivetrain of each machine read (after MoreRealistic) and listed in modSettings/FS25_AutoSwitch/transmissions.xml (can be corrected by hand). Machines without 4WD (combines, forage harvesters, 2WD): full steering, no 2WD / 4WD, only the driven axle locks, combine icon on the HUD. |
| Grip (MoreRealistic) | Grip loss on wet ground (Beginner, Easy, Normal, Hard, Extreme), Variable Tire Pressure field bonus capped at +15 % (+20 % with dual wheels), fixed bonus when differentials are locked (+4 % rear wheels, +3 % front wheels), tire wear from Real Physics - Tire Wear applied on top of the ground grip, worn tires grip better on road (slick effect). |
| Dual wheels | Real width used by Mud System Physics, better grip on wet ground, VTP fix for tires with brand variants. |
| Dual-wheel racks | Rear (BKT 650/65R42, €4,500) and front (BKT 540/65R30, €3,500) racks in the shop and the construction menu. Mounting / unmounting tire by tire (15 in-game minutes per tire), parking area on the ground, player marker, timer, tractor locked during the job. |
| Display | Recommended speed range (movable with the mouse) and top view of the tractor next to the speedometer (locked axles, 4WD, slip of each wheel or per locked axle), slip warning. |
| Sowing | Seeding protection, seeder filling with the lid closed, direct re-sowing on crushed strips. |
| AutoDrive speed | Speed set by the ground: 20 km/h in fields, 30 km/h on tracks, no limit on roads. Adjustable in 2 km/h steps in the settings. |
| Mud | The mod's Mud System Physics settings (ground profiles included) + TTD on "Hard", applied automatically on every load. MSP → TTD bridge: on fields, TTD gets Mud System Physics' local wetness and resistance is not applied twice. Wet paths: TTD's "Hard" penalty is removed (paths are drivable again). TTD calibrator blocked (Ctrl+C and middle click). |
| Tire tracks | Kept with the savegame and redrawn on load (latest 60,000 points, single-player or host). |
| Tire dirt | Muddy tires take at least 1 hour of driving to clean (1 h to 2 h 10 depending on speed); water, rain and washing clean them normally. |
| Stable implements | Wheel radius frozen on stopped implements: no more bouncing caused by Mud System Physics + MoreRealistic. |
| Mud on unbraked wheels | Mud System Physics mud drag also slows unbraked wheels (trailers, implements) with MoreRealistic. |
| Mod arbitration | AutoSwitch blocks or orders the conflicting hooks itself (MoreRealistic, DynamicDrivePro, Enhanced Vehicle, Recovery Winch), without disabling any mod. ModMixer is no longer needed. |
| Sleep | Two sliders in the Sleep dialog: time in hours (+0 to +23 h) and time in days (+0 to +7), added together. No more 24 h limit; with days, wake-up at 8 am. Days pass normally (crops, sales, wages). |

### Using the dual-wheel racks

1. Place the rear rack (and the front rack for the front axle) side by side.
2. Park the tractor in the ground rectangle (red, then green once correctly positioned).
3. On foot, stand on the yellow marker and press **Right Ctrl + I**, then confirm.
4. Unmounting: same procedure with **empty** racks; the original tires are put back.

Dual wheels must exist in the **same tire brand** as the tractor's tires. Wheel change: **single-player only**.

### Required mods

- [Variable Tire Pressure](https://www.farming-simulator.com/mod.php?mod_id=347991&title=fs2025) : version 1.0.0.13 minimum
- [Enhanced Vehicle](https://github.com/ZhooL/FS25_EnhancedVehicle/releases) : version 1.1.7.1 minimum
- [AutoDrive](https://github.com/Stephan-S/FS25_AutoDrive/releases) : version 3.0.1.4 minimum
- [Courseplay](https://github.com/Courseplay/Courseplay_FS25/releases) : version 8.1.0.3 minimum
- [MoreRealistic](https://github.com/quadural/MoreRealistic_FS25/blob/main/MoreRealistic.zip) : version 0.26.09.13 minimum
- [MoreRealistic XML Databank](https://github.com/quadural/MoreRealistic_FS25/blob/main/moreRealisticXmlDatabank.zip) : version 1.0.0.1 minimum
- [Mud System Physics](https://www.kingmods.net/en/fs25/mods/73208/mud-system-physics) : version 1.3.6.0 minimum
- [Tractor Terrain Dynamics](https://www.kingmods.net/en/fs25/mods/78890/tractor-terrain-dynamics) : version 1.0.3.7 minimum (bêta). Le zip peut garder son nom KingMods (FS25_TTD_v3_7_BETA.zip) ; n'installer qu'un seul TTD.
- [DynamicDrive Pro](https://www.farming-simulator.com/mod.php?mod_id=352451&title=fs2025) : version 1.0.1.0 minimum 
- [Realistic Harvesting](https://github.com/exekx/FS25_RealisticHarvesting/releases) : version 1.6.0.0 minimum
- [Moisture System](https://www.farming-simulator.com/mod.php?mod_id=354130&title=fs2025) : version 2.0.0.8 minimum

AutoSwitch is part of a global realistic pack: these mods are expected, at least in the version shown. If one is missing (not installed, not enabled or older), AutoSwitch still starts without the features that depend on it, and a box at the bottom left of the screen lists the missing mods.

### Installation

1. Download `FS25_AutoSwitch.zip` from the **Releases** section.
2. Copy it **without unzipping** into `Documents/My Games/FarmingSimulator2025/mods`.
3. Enable it together with the required mods. Settings: **Settings > General > AutoSwitch**.

### Known limitations

- Wheel change is single-player only; short freeze while the tractor reloads (longer with attached implements).
- A tractor without a dual-wheel configuration in its file cannot receive dual wheels.

---

## Licence / License

[CC BY-NC-SA 4.0](https://creativecommons.org/licenses/by-nc-sa/4.0/)

- 🇫🇷 Partage et modification autorisés en citant l'auteur, pas d'usage commercial, mêmes conditions pour les dérivés.
- 🇬🇧 Sharing and modification allowed with credit to the author, no commercial use, derivatives under the same terms.

