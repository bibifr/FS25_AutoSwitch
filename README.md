###Last version https://github.com/bibifr/FS25_AutoSwitch/releases/latest/download/FS25_AutoSwitch.zip

# FS25 AutoSwitch

**Version 1.0.0.07** · Farming Simulator 25 · Auteur : Fabien · FR / EN / DE

## French

Mod compagnon qui automatise **la pression des pneus et les différentiels** et rend **la traction réaliste**, en faisant travailler ensemble Variable Tire Pressure, Enhanced Vehicle, MoreRealistic, Mud System Physics et Tractor Terrain Dynamics, sans modifier ces mods. Il ajoute aussi une palette de pneu pour changement de pneu.
Objectif: Rendre le jeux plus realiste et performant

> 🇬🇧 [English version below](#english)

## Fonctionnalités

| Domaine | Ce que fait AutoSwitch |
| --- | --- |
| Pression des pneus | Avec AutoDrive / Courseplay : dégonflage au champ, gonflage sur route. En conduite manuelle : Automatique ou Manuel. Le regonflage automatique de VTP à 30 km/h est désactivé. |
| Différentiels (Enhanced Vehicle) | Blocage AV + AR quand le patinage dépasse un seuil réglable, déblocage à la moitié du seuil, 4x4 au champ / 4x2 sur route, déblocage en virage, remise à zéro au chargement. |
| Adhérence (MoreRealistic) | Perte d'adhérence en sol humide (5 niveaux), bonus quand les différentiels sont bloqués, usure Use Your Tyres prise en compte. |
| Roues jumelées | Largeur réelle prise en compte par Mud System Physics, meilleure adhérence en sol humide, correctif VTP pour les pneus à variantes de marques. |
| Palettes de jumelées | Palettes AR (BKT 650/65R42, 4 500 €) et AV (BKT 540/65R30, 3 500 €) en boutique et au menu construction. Montage / démontage pneu par pneu (15 min de jeu par pneu), zone de stationnement au sol, repère joueur, minuteur, tracteur verrouillé pendant le chantier. |
| Affichage | Plage de vitesse conseillée (déplaçable à la souris) et pourcentage de patinage près du compteur, alerte de patinage. |
| Semis | Protection du semis, remplissage du semoir couvercle fermé, ressemis direct sur bandes écrasées. |
| Vitesse AutoDrive | Vitesse imposée selon le terrain : 20 km/h au champ, 30 km/h sur les chemins, sans limite sur la route. Réglable par tranches de 5 km/h dans les paramètres. |
| Boue | Réglages Mud System Physics du mod (profils de sol compris) + TTD en « Difficile », appliqués automatiquement à chaque chargement. |
| Traces de pneus | Gardées avec la sauvegarde et redessinées au chargement (20 000 points les plus récents, solo ou hôte). |
| Outils stables | Rayon des roues figé sur les outils à l'arrêt : plus de sautillement dû à Mud System Physics + MoreRealistic. |
| Boue sur roues sans frein | La résistance de boue de Mud System Physics freine aussi les roues sans frein (remorques, outils) avec MoreRealistic. |
| Arbitrage des mods | AutoSwitch bloque ou ordonne lui-même les crochets en conflit (MoreRealistic, Use Your Tyres, DynamicDrivePro, Enhanced Vehicle, Recovery Winch), sans désactiver aucun mod. ModMixer n'est plus nécessaire. |

## Utiliser les palettes de jumelées

1. Poser la palette AR (et AV pour l'avant) côte à côte.
2. Garer le tracteur dans le rectangle au sol (rouge, puis vert quand il est bien placé).
3. À pied, se placer sur le marqueur jaune et appuyer sur **Ctrl droit + I**, puis confirmer.
4. Démontage : même chose avec des palettes **vides** ; les pneus d'origine sont remis.

Les jumelées doivent exister dans la **même marque de pneus** que ceux du tracteur. Changement de roues : **solo uniquement**.

## Mods requis

FS25_VariableTirePressure, FS25_EnhancedVehicle, FS25_AutoDrive, FS25_Courseplay, MoreRealistic, moreRealisticXmlDatabank, FS25_MudSystemPhysics, FS25_TractorTerrainDynamics, FS25_DynamicDrivePro, FS25_useYourTyres, FS25_RealisticHarvesting, FS25_CropDestructionOverhaul, FS25_MoistureSystem.

AutoSwitch fait partie d'un ensemble réaliste global : tous ces mods sont obligatoires.

## Installation

1. Télécharger `FS25_AutoSwitch.zip` dans la section **Releases**.
2. Le copier **sans le dézipper** dans `Documents/My Games/FarmingSimulator2025/mods`.
3. L'activer avec ses dépendances. Réglages : **Paramètres > Général > AutoSwitch**.

## Limites connues

- Changement de roues en solo uniquement ; petit gel pendant le rechargement du tracteur (plus long avec des outils attelés).
- Un tracteur sans configuration jumelées dans son fichier ne peut pas en recevoir.

---

## English

**Version 1.0.0.07** · Farming Simulator 25 · Author: Fabien · FR / EN / DE

Companion mod that automates **tire pressure and differential locks** and makes **traction realistic** by making Variable Tire Pressure, Enhanced Vehicle, MoreRealistic, Mud System Physics and Tractor Terrain Dynamics work together, without modifying any of them. It also adds **dual-wheel racks** mounted tire by tire.
Objective: Make game more realistic 

### Features

| Area | What AutoSwitch does |
| --- | --- |
| Tire pressure | With AutoDrive / Courseplay: deflate in the field, inflate on the road. Manual driving: Automatic or Manual mode. VTP's automatic re-inflation at 30 km/h is disabled. |
| Differentials (Enhanced Vehicle) | Front + rear lock when wheel slip exceeds an adjustable threshold, unlock at half the threshold, 4WD in the field / 2WD on the road, unlock when turning, reset on game load. |
| Grip (MoreRealistic) | Grip loss on wet ground (5 levels), bonus when differentials are locked, Use Your Tyres wear taken into account. |
| Dual wheels | Real width used by Mud System Physics, better grip on wet ground, VTP fix for tires with brand variants. |
| Dual-wheel racks | Rear (BKT 650/65R42, €4,500) and front (BKT 540/65R30, €3,500) racks in the shop and the construction menu. Mounting / unmounting tire by tire (15 in-game minutes per tire), parking area on the ground, player marker, timer, tractor locked during the job. |
| Display | Recommended speed range (movable with the mouse) and slip percentage next to the speedometer, slip warning. |
| Sowing | Seeding protection, seeder filling with the lid closed, direct re-sowing on crushed strips. |
| AutoDrive speed | Speed set by the ground: 20 km/h in fields, 30 km/h on tracks, no limit on roads. Adjustable in 5 km/h steps in the settings. |
| Mud | The mod's Mud System Physics settings (ground profiles included) + TTD on "Hard", applied automatically on every load. |
| Tire tracks | Kept with the savegame and redrawn on load (latest 20,000 points, single-player or host). |
| Stable implements | Wheel radius frozen on stopped implements: no more bouncing caused by Mud System Physics + MoreRealistic. |
| Mud on unbraked wheels | Mud System Physics mud drag also slows unbraked wheels (trailers, implements) with MoreRealistic. |
| Mod arbitration | AutoSwitch blocks or orders the conflicting hooks itself (MoreRealistic, Use Your Tyres, DynamicDrivePro, Enhanced Vehicle, Recovery Winch), without disabling any mod. ModMixer is no longer needed. |

### Using the dual-wheel racks

1. Place the rear rack (and the front rack for the front axle) side by side.
2. Park the tractor in the ground rectangle (red, then green once correctly positioned).
3. On foot, stand on the yellow marker and press **Right Ctrl + I**, then confirm.
4. Unmounting: same procedure with **empty** racks; the original tires are put back.

Dual wheels must exist in the **same tire brand** as the tractor's tires. Wheel change: **single-player only**.

### Required mods

FS25_VariableTirePressure, FS25_EnhancedVehicle, FS25_AutoDrive, FS25_Courseplay, MoreRealistic, moreRealisticXmlDatabank, FS25_MudSystemPhysics, FS25_TractorTerrainDynamics, FS25_DynamicDrivePro, FS25_useYourTyres, FS25_RealisticHarvesting, FS25_CropDestructionOverhaul, FS25_MoistureSystem.

AutoSwitch is part of a global realistic pack: all these mods are required.

### Installation

1. Download `FS25_AutoSwitch.zip` from the **Releases** section.
2. Copy it **without unzipping** into `Documents/My Games/FarmingSimulator2025/mods`.
3. Enable it together with its dependencies. Settings: **Settings > General > AutoSwitch**.

### Known limitations

- Wheel change is single-player only; short freeze while the tractor reloads (longer with attached implements).
- A tractor without a dual-wheel configuration in its file cannot receive dual wheels.

---

## Licence / License

[CC BY-NC-SA 4.0](https://creativecommons.org/licenses/by-nc-sa/4.0/)

- 🇫🇷 Partage et modification autorisés en citant l'auteur, pas d'usage commercial, mêmes conditions pour les dérivés.
- 🇬🇧 Sharing and modification allowed with credit to the author, no commercial use, derivatives under the same terms.

