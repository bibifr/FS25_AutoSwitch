<img width="2056" height="765" alt="ChatGPT Image 22 oct  2026, 17_12_23" src="https://github.com/user-attachments/assets/bc467ab8-f289-47a8-91c0-67e536e2cdfd" />


### Discord https://discord.gg/S7gGzqnSEp
## LAST VERSION AUTOSWITCH https://github.com/bibifr/FS25_AutoSwitch/releases/latest/download/FS25_AutoSwitch.zip
## ADDON Autodrive for some Forget function https://github.com/bibifr/FS25_AutoDriveAddon/releases

# FS25 AutoSwitch

**Version 1.0.3.0** · Farming Simulator 25 · Auteur : Fabien · FR / EN / DE

## French

Mod compagnon qui **uniformise les informations de différents mods pour les rendre compatibles entre eux** !

Il intègre également plein de nouvelles fonctionnalités qui favorisent une meilleure expérience de jeu et un rendu plus réaliste.

Objectif de ce mod : rendre le jeu plus facile, plus complet et plus performant !

> 🇬🇧 [English version below](#english)

## Fonctionnalités

| Domaine | Ce que fait AutoSwitch |
| --- | --- |
| Pression des pneus | Avec AutoDrive / Courseplay : dégonflage au champ, gonflage sur route. En conduite manuelle : Automatique ou Manuel. Le regonflage automatique de VTP à 30 km/h est désactivé. |
| Différentiels (Enhanced Vehicle) | Blocage AR puis AV selon le patinage (seuils réglables, 15 % et 30 % par défaut), déblocage à la moitié du seuil, 4x2 sur goudron et béton seulement, 4x4 partout ailleurs (champs, chemins), braquage 90 % en 4x4, blocages coupés au-delà de 50 % du braquage (AR seul), 20 % (AV seul) ou 10 % (les deux) et refusés roues braquées, remise à zéro au chargement. Touche Ctrl droit + Flèche haut : mode AUTO / MANUEL (affiché au-dessus du tracteur) ; en MANUEL, vous gérez différentiels et 4x2 / 4x4, un blocage engagé ne se coupe plus et le tracteur ne tourne qu'à son seuil (roues braquées à fond, il ripe) ; retour en AUTO quand AutoDrive ou Courseplay prend la main (désactivable). Transmission réelle de chaque machine lue (après MoreRealistic) et notée dans modSettings/FS25_AutoSwitch/transmissions.xml (corrigeable à la main). Machines sans 4x4 (moissonneuses, ensileuses, 4x2) : braquage complet, pas de 4x2 / 4x4, seul le pont moteur se bloque, icône moissonneuse sur le HUD. |
| Adhérence (MoreRealistic) | Perte d'adhérence en sol humide (Débutant, Facile, Normal, Dur, Extrême), bonus Variable Tire Pressure en champ ramené à +15 % (+20 % en jumelées), bonus fixe quand les différentiels sont bloqués (+4 % roues AR, +3 % roues AV), usure des pneus appliquée par-dessus l'adhérence du sol, un pneu usé accroche mieux sur route (effet slick). |
| Roues jumelées | Largeur réelle prise en compte par Mud System Physics, meilleure adhérence en sol humide, correctif VTP pour les pneus à variantes de marques. |
| Palettes de jumelées | Palettes AR (BKT 650/65R42, 4 500 €) et AV (BKT 540/65R30, 3 500 €) en boutique et au menu construction. Montage / démontage pneu par pneu (15 min de jeu par pneu), zone de stationnement au sol, repère joueur, minuteur, tracteur verrouillé pendant le chantier. Les jumelées ne se montent qu'avec les palettes (retirées du magasin et de l'atelier, réglable). |
| Usure des pneus | Intégrée à AutoSwitch, aucun mod de pneus nécessaire : chaque pneu et chaque chenille s'use selon la distance, le patinage, la charge, le sol, la pression, la vitesse sur route et la météo. Pneu usé : moins d'adhérence au champ, un peu plus sur route sèche, gomme rabotée à l'écran, crevaisons plus fréquentes (Mud System Physics). Barre et pourcentage par roue sur le HUD, alertes à 75 % et 90 %, bouton « Pneus neufs » à l'atelier. Real Physics - Tire Wear est désactivé et bloqué par AutoSwitch. |
| Affichage | Plage de vitesse conseillée (déplaçable à la souris) et tracteur vu de dessus près du compteur (ponts bloqués, 4x4, patinage de chaque roue ou par pont bloqué), alerte de patinage. Icônes moissonneuse et ensileuse. Affichages en double des autres mods masqués (Enhanced Vehicle). |
| Météo | Mini-météo dans la barre de l'horloge (temps actuel, mini / maxi, prochain changement, vent). Fenêtre Météo (Ctrl droit + M) : 24 prochaines heures, changements à venir avec la pluie attendue, jours suivants. Arbres, cultures et herbe bougent selon la vraie force du vent. |
| Champs | Fenêtre Champs (Ctrl droit + C) : pour chaque champ possédé, culture, stade, dates de semis, d'engrais et d'herbicide, récolte (« Prêt », « Idéal » ou mois estimé), total des hectares possédés. |
| Registre | Fenêtre Registre (Ctrl droit + R) : pesées d'AutoDrive Addon sur pont-bascule et toutes les ventes de la ferme, totaux par mois et par produit, une page par année. |
| Argent | Découvert possible jusqu'à 20 % de la valeur de la ferme (réglable), agios chaque jour. Coopératives payées en fin de mois. |
| Horaires d'ouverture | Magasin ouvert de 8 h à 19 h, points de vente de 6 h à 22 h (réglable, exceptions par point de vente). Un camion AutoDrive attend l'ouverture. |
| Trafic | Les voitures ne doublent plus les tracteurs et ne freinent plus en les croisant. |
| Lumières | Portée et luminosité réglables par type de feu (phares de route, travail avant, travail arrière, gyrophares, signalisation), de x1,1 à x2,5. |
| Courseplay | Les véhicules qui roulaient avec Courseplay à la sauvegarde repartent au chargement de la partie, depuis le point où ils s'étaient arrêtés (désactivable). |
| Ensileuses | Avec AutoDrive, la goulotte remplit la benne de plus loin (5 m de portée en plus). |
| Herbe | L'herbe piétinée par les roues recule d'un stade de pousse (selon la vitesse et l'humidité du sol). |
| Semis | Protection du semis, remplissage du semoir couvercle fermé, ressemis direct sur bandes écrasées. |
| Vitesse AutoDrive | Vitesse imposée selon le terrain : 20 km/h au champ, 30 km/h sur les chemins, sans limite sur la route. Réglable par tranches de 2 km/h dans les paramètres. |
| Boue | Réglages Mud System Physics du mod (profils de sol compris) + TTD en « Difficile », appliqués automatiquement à chaque chargement. Pont MSP → TTD : au champ, TTD reçoit l'humidité locale de Mud System Physics et la résistance n'est pas appliquée deux fois. Chemins mouillés : la pénalité « Difficile » de TTD est retirée (chemins à nouveau praticables). Calibrateur de TTD bloqué (Ctrl+C et clic molette). |
| Traces de pneus | Gardées avec la sauvegarde et redessinées au chargement (60 000 points les plus récents, solo ou hôte). |
| Saleté des pneus | Les pneus salis par la boue mettent au moins 1 h de route à se nettoyer (1 h à 2 h 10 selon la vitesse) ; l'eau, la pluie et le lavage les nettoient normalement. |
| Outils stables | Rayon des roues figé sur les outils à l'arrêt : plus de sautillement dû à Mud System Physics + MoreRealistic. |
| Boue sur roues sans frein | La résistance de boue de Mud System Physics freine aussi les roues sans frein (remorques, outils) avec MoreRealistic. |
| Arbitrage des mods | AutoSwitch bloque ou ordonne lui-même les crochets en conflit (MoreRealistic, DynamicDrivePro, Enhanced Vehicle, Recovery Winch), sans désactiver aucun mod. ModMixer n'est plus nécessaire. |
| Dormir | Deux curseurs dans la fenêtre Dormir : temps en heures (+0 à +23 h) et temps en jours (+0 à +7), cumulés. Plus de limite de 24 h ; avec des jours, réveil à 8 h. Les jours passent normalement (cultures, ventes, salaires). |
| Aide | Catégorie « AutoSwitch » dans Échap > Aide (FR / EN / DE), 12 pages illustrées. |

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

AutoSwitch fait partie d'un ensemble réaliste global : ces mods sont prévus, au moins dans la version indiquée. S'il en manque un (absent, pas activé ou plus ancien), AutoSwitch démarre quand même, sans les fonctions qui dépendent de ce mod, et la liste des mods en bas de l'onglet AUTOSWITCH indique ce qui manque (OK en vert, X en rouge). Aucun mod de pneus n'est nécessaire.

## Installation

1. Télécharger `FS25_AutoSwitch.zip` dans la section **Releases**.
2. Le copier **sans le dézipper** dans `Documents/My Games/FarmingSimulator2025/mods`.
3. L'activer avec les mods requis. Réglages : onglet **AUTOSWITCH** dans les **Paramètres**.

## Limites connues

- Changement de roues en solo uniquement ; petit gel pendant le rechargement du tracteur (plus long avec des outils attelés).
- Un tracteur sans configuration jumelées dans son fichier ne peut pas en recevoir.

---

## English

**Version 1.0.3.0** · Farming Simulator 25 · Author: Fabien · FR / EN / DE

Companion mod that **harmonises the information of different mods to make them compatible with each other**!

It also brings many new features for a better game experience and a more realistic feel.

Goal of this mod: make the game easier, more complete and better performing!

### Features

| Area | What AutoSwitch does |
| --- | --- |
| Tire pressure | With AutoDrive / Courseplay: deflate in the field, inflate on the road. Manual driving: Automatic or Manual mode. VTP's automatic re-inflation at 30 km/h is disabled. |
| Differentials (Enhanced Vehicle) | Rear then front lock depending on wheel slip (adjustable thresholds, 15 % and 30 % by default), unlock at half the threshold, 2WD on asphalt and concrete only, 4WD everywhere else (fields, tracks), 90 % steering in 4WD, locks released beyond 50 % of full steering (rear only), 20 % (front only) or 10 % (both) and refused with the wheels turned, reset on game load. Right Ctrl + Up arrow: AUTO / MANUAL mode (shown above the tractor); in MANUAL you handle the differentials and 2WD / 4WD, an engaged lock is never released and the tractor only turns up to its limit (wheels turned fully, it slides); back to AUTO when AutoDrive or Courseplay takes over (can be turned off). Actual drivetrain of each machine read (after MoreRealistic) and listed in modSettings/FS25_AutoSwitch/transmissions.xml (can be corrected by hand). Machines without 4WD (combines, forage harvesters, 2WD): full steering, no 2WD / 4WD, only the driven axle locks, combine icon on the HUD. |
| Grip (MoreRealistic) | Grip loss on wet ground (Beginner, Easy, Normal, Hard, Extreme), Variable Tire Pressure field bonus capped at +15 % (+20 % with dual wheels), fixed bonus when differentials are locked (+4 % rear wheels, +3 % front wheels), tire wear applied on top of the ground grip, worn tires grip better on road (slick effect). |
| Dual wheels | Real width used by Mud System Physics, better grip on wet ground, VTP fix for tires with brand variants. |
| Dual-wheel racks | Rear (BKT 650/65R42, €4,500) and front (BKT 540/65R30, €3,500) racks in the shop and the construction menu. Mounting / unmounting tire by tire (15 in-game minutes per tire), parking area on the ground, player marker, timer, tractor locked during the job. Dual wheels can only be fitted with the racks (removed from the shop and the workshop, can be changed). |
| Tire wear | Built into AutoSwitch, no tire mod needed: each tire and each track wears with distance, slip, load, ground, pressure, road speed and weather. Worn tire: less grip in the field, a little more on dry road, tread shaved on screen, more punctures (Mud System Physics). Bar and percentage per wheel on the HUD, warnings at 75 % and 90 %, "New tires" button at the workshop. Real Physics - Tire Wear is disabled and blocked by AutoSwitch. |
| Display | Recommended speed range (movable with the mouse) and top view of the tractor next to the speedometer (locked axles, 4WD, slip of each wheel or per locked axle), slip warning. Combine and forage harvester icons. Duplicate displays from other mods hidden (Enhanced Vehicle). |
| Weather | Mini weather in the clock bar (current weather, min / max, next change, wind). Weather window (Right Ctrl + M): next 24 hours, upcoming changes with the expected rain, following days. Trees, crops and grass move with the real wind strength. |
| Fields | Fields window (Right Ctrl + C): for each owned field, crop, growth stage, sowing, fertilizer and herbicide dates, harvest ("Ready", "Ideal" or estimated month), total hectares owned. |
| Register | Register window (Right Ctrl + R): AutoDrive Addon weighbridge weighings and all farm sales, totals per month and per product, one page per year. |
| Money | Overdraft up to 20 % of the farm's value (adjustable), interest every day. Cooperatives paid at the end of the month. |
| Opening hours | Shop open from 8 am to 7 pm, selling points from 6 am to 10 pm (adjustable, exceptions per selling point). An AutoDrive truck waits for the opening. |
| Traffic | Cars no longer overtake tractors and no longer brake when passing them. |
| Lights | Range and brightness adjustable per light type (road lights, front work, rear work, beacons, signals), from x1.1 to x2.5. |
| Courseplay | Vehicles that were driving with Courseplay when the game was saved start again on load, from the point where they stopped (can be turned off). |
| Forage harvesters | With AutoDrive, the spout fills the trailer from further away (5 m more reach). |
| Grass | Grass run over by the wheels goes back one growth stage (depending on speed and ground wetness). |
| Sowing | Seeding protection, seeder filling with the lid closed, direct re-sowing on crushed strips. |
| AutoDrive speed | Speed set by the ground: 20 km/h in fields, 30 km/h on tracks, no limit on roads. Adjustable in 2 km/h steps in the settings. |
| Mud | The mod's Mud System Physics settings (ground profiles included) + TTD on "Hard", applied automatically on every load. MSP → TTD bridge: on fields, TTD gets Mud System Physics' local wetness and resistance is not applied twice. Wet paths: TTD's "Hard" penalty is removed (paths are drivable again). TTD calibrator blocked (Ctrl+C and middle click). |
| Tire tracks | Kept with the savegame and redrawn on load (latest 60,000 points, single-player or host). |
| Tire dirt | Muddy tires take at least 1 hour of driving to clean (1 h to 2 h 10 depending on speed); water, rain and washing clean them normally. |
| Stable implements | Wheel radius frozen on stopped implements: no more bouncing caused by Mud System Physics + MoreRealistic. |
| Mud on unbraked wheels | Mud System Physics mud drag also slows unbraked wheels (trailers, implements) with MoreRealistic. |
| Mod arbitration | AutoSwitch blocks or orders the conflicting hooks itself (MoreRealistic, DynamicDrivePro, Enhanced Vehicle, Recovery Winch), without disabling any mod. ModMixer is no longer needed. |
| Sleep | Two sliders in the Sleep dialog: time in hours (+0 to +23 h) and time in days (+0 to +7), added together. No more 24 h limit; with days, wake-up at 8 am. Days pass normally (crops, sales, wages). |
| Help | "AutoSwitch" category in Esc > Help (FR / EN / DE), 12 illustrated pages. |

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

AutoSwitch is part of a global realistic pack: these mods are expected, at least in the version shown. If one is missing (not installed, not enabled or older), AutoSwitch still starts without the features that depend on it, and the mod list at the bottom of the AUTOSWITCH tab shows what is missing (OK in green, X in red). No tire mod is needed.

### Installation

1. Download `FS25_AutoSwitch.zip` from the **Releases** section.
2. Copy it **without unzipping** into `Documents/My Games/FarmingSimulator2025/mods`.
3. Enable it together with the required mods. Settings: **AUTOSWITCH** tab in the **Settings**.

### Known limitations

- Wheel change is single-player only; short freeze while the tractor reloads (longer with attached implements).
- A tractor without a dual-wheel configuration in its file cannot receive dual wheels.

---

## Licence / License

[CC BY-NC-SA 4.0](https://creativecommons.org/licenses/by-nc-sa/4.0/)

- 🇫🇷 Partage et modification autorisés en citant l'auteur, pas d'usage commercial, mêmes conditions pour les dérivés.
- 🇬🇧 Sharing and modification allowed with credit to the author, no commercial use, derivatives under the same terms.

