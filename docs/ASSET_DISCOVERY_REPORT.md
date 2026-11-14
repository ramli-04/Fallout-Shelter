# ESSAIM asset discovery report

Research date: **11 November 2026**. This is a discovery and selection report. No candidate model, sprite, animation archive or Project Zomboid mod has been imported, converted or installed.

**Recommendation:** retain the existing 3D isometric presentation and evaluate a small, consistent subset of licensed assets. Begin with Kenney's coherent buildings, roads, furniture and vehicle family; evaluate regular-proportioned Quaternius humans separately. The closest PZ community work remains a permission/provenance track. None of the free packs inspected is a finished visual match for Project Zomboid or Fallout 1/2.

Open the [visual gallery](asset_discovery/gallery.html) for publisher previews and filters, or use the [central JSON catalog](asset_discovery/catalog.json) and [CSV catalog](asset_discovery/catalog.csv). All 26 entries include creator, category, source, download route, license evidence, attribution, format, animation availability, import status and expected Godot compatibility. Fourteen have a creator license statement verified; this does not mean their undownloaded archives have been audited. [LICENSES.md](../LICENSES.md) records the licensing decisions.

## What was inspected locally

Graphify was queried before checking the visual implementation. The relevant Godot renderers currently construct agent, building, vehicle and roadblock visuals through reusable code. `world_coordinates.gd` maps authoritative planar positions to the 3D world with a scale of 0.1. The inspected `assets/` directory contains warning audio, not a ready-made visual asset library; no GLB/FBX-loading integration was found in the checked renderers.

This makes a visual-child replacement practical without replacing agents, collisions, shelter IDs S1–S5, road geometry, Moroccan traffic, emergency dispatch, seeded timing, AI or recording. Imported assets must follow the simulation's existing dimensions and records. Asset-pack sample scenes must not take over movement or spawn extra population.

## Best candidates and tradeoffs

These rankings are visual/engineering judgments from publisher stills, not benchmarks or Godot import results. `Axx` IDs resolve to the full catalog and licensing register.

| Priority | Candidate / source and download | Coverage | License | Decision |
| --- | --- | --- | --- | --- |
| Character pilot | A01 [Universal Base Characters](https://quaternius.itch.io/universal-base-characters) | Rigged humans | CC0 | Regular proportions are the strongest human starting point inspected; modern clothing and LOD work remain. |
| Animation pilot | A02 [Universal Animation Library](https://quaternius.itch.io/universal-animation-library) | Humanoid locomotion/actions | CC0 | Review the free Standard tier and exact required clips; use in-place movement. |
| Fleet pilot | A06 [Kenney Car Kit](https://kenney.nl/assets/car-kit) | Civilian cars, police, ambulance, fire truck, cones | CC0 | One consistent fleet; toy proportions need adjustment. Police SUV identity remains unconfirmed. |
| Environment pilot | A08/A09 [Suburban](https://kenney.nl/assets/city-kit-suburban) / [Commercial](https://kenney.nl/assets/city-kit-commercial) | Houses and shops | CC0 | Consistent shells; add restrained weathering and foreground visibility handling. |
| Road dressing pilot | A10 [City Kit Roads](https://kenney.nl/assets/city-kit-roads) | Sidewalks, junction dressing, signs, lights | CC0 | Adapt visuals to actual irregular roads; preserve existing lane/navigation logic. |
| Interior pilot | A12 [Furniture Kit](https://kenney.nl/assets/furniture-kit) | Beds, kitchen, bathroom, household props | CC0 | Good breadth; check exact edition and door/interaction pivots. |
| Prop pilot | A15 [Quaternius Survival Pack](https://quaternius.com/packs/survival.html) | Supplies, radios, tools, first-aid cases | CC0 | More grounded small props; useful for shelter routines. |
| Industrial alternative | A11 [City Kit Industrial](https://kenney.nl/assets/city-kit-industrial) | Warehouses, utility structures | CC0 | Fits the Kenney family; needs disaster treatment. |
| Nature alternatives | A13 [Kenney Nature](https://kenney.nl/assets/nature-kit) / A14 [Quaternius Nature](https://quaternius.com/packs/ultimatestylizednature.html) | Trees, rocks, vegetation | CC0 | Pick one foliage treatment and region-appropriate species. |
| Selected props only | A03 [Zombie Apocalypse Kit](https://quaternius.com/packs/zombieapocalypsekit.html) | Debris, barriers, containers, vehicles | CC0 | Props are useful; cartoon humans/zombies diverge from the target. |
| Infrastructure fallback | A16 [Low Poly City Kit](https://github.com/kayquer/kit-cidade-lowpoly) | GLB city pieces, ambulance, fire truck | CC0 | Broad coverage, but toy scale and Brazilian signs/species need adaptation. |

Download links intentionally point to the publisher's normal download page or creator-linked folder. Kenney uses fresh signed links; itch.io may show a voluntary-payment screen. No guessed permanent archive URLs or alternate downloaders are supplied.

### Character preview and free-tier boundary

![Quaternius Universal Base Characters publisher preview](https://quaternius.com/assets/images/fullres/universalbasecharacters.jpg)

Publisher preview by Quaternius; this is not an ESSAIM screenshot. The regular bodies offer a better basis than oversized cartoon heads. These are base bodies, not completed civilian/police uniforms. The [publisher](https://quaternius.com/packs/universalbasecharacters.html) reports an average of about 13k triangles; population-scale skinning/material performance still needs measurement.

The [animation purchase page](https://quaternius.itch.io/universal-animation-library/purchase) separates Standard from paid Pro/Source editions. Do not interpret the advertised full-library clip count as an inventory of free clips or assume free Blender source. Resolve walking, running, sitting, interacting and police-work requirements against the actual Standard archive before replacement. Sleeping, eating, repairing, barrier placement and vehicle entry/exit may still need custom clips or procedural poses.

### A consistent vehicle/building family

![Kenney Car Kit publisher preview](https://kenney.nl/media/pages/assets/car-kit/81f9d77bc7-1775131953/preview.png)

Publisher preview by Kenney. The pictured fleet includes the core civilian/emergency types and cone/barrier pieces. There is no implication that wheels, doors or emergency lights come with all required animations. See the [pack page and CC0 statement](https://kenney.nl/assets/car-kit).

![Kenney Suburban publisher preview](https://kenney.nl/media/pages/assets/city-kit-suburban/8c3d4e93a3-1745479402/sample.png)

Publisher preview by Kenney. This is coherent and readable but much cleaner and more rounded than the target. A small selected set is preferable to importing a whole sample city. Building footprints, entrances, indoor rooms and shelter identities remain simulation-owned.

### Roads, furniture and practical survival props

![Kenney Roads publisher preview](https://kenney.nl/media/pages/assets/city-kit-roads/8021370415-1787042780/sample.png)

Publisher preview by Kenney. Use matching street furniture and surface treatment while retaining ESSAIM's actual road graph. Do not force the city onto the pack's grid or import traffic direction from a demonstration layout.

![Kenney Furniture publisher preview](https://kenney.nl/media/pages/assets/furniture-kit/4573c6a40b-1677580842/sample.png)

Publisher preview by Kenney. The creator's [older OpenGameArt edition](https://opengameart.org/content/furniture-kit) explicitly lists OBJ, PNG and four-angle isometric renders. That provides a possible sprite route; it is not proof that the latest download has identical contents.

![Quaternius Survival Pack publisher preview](https://quaternius.com/assets/images/fullres/survival.jpg)

Publisher preview by Quaternius. This pack supplies practical small props under its [CC0 declaration](https://quaternius.com/packs/survival.html). Choose items that support existing interactions; a visible radio or repair tool must not fabricate a new skill, resource or behavior.

## Project Zomboid community findings

These are the strongest style leads, but **none is cleared for ESSAIM import in this pass**. The source pages supply public screenshot previews. No mod files or proprietary game files were downloaded.

| ID / source with previews | Published reuse position | ESSAIM decision |
| --- | --- | --- |
| A19 [Daddy Dirkie Dirk's tiles](https://steamcommunity.com/sharedfiles/filedetails/?id=2337452747) | Credited PZ map use allowed; written permission required for editing/redistribution. | Seek a grant for exact original tile files, modifications and standalone distribution. |
| A20 [Dylan's Tile Pack](https://steamcommunity.com/sharedfiles/filedetails/?id=2599752664) | Permissions discuss PZ modpacks and continuing maps. | Separate-game asset distribution is not explicit; clarify with Dylan/(PlentyT). |
| A21 [throttlekitty's tiles](https://steamcommunity.com/sharedfiles/filedetails/?id=2384329562) | Broad permission to use/modify with credit; additional contributor credited. | Promising custom grant. Confirm standalone scope and ownership of selected files; this is a verification hold, not a claim of prohibition. |
| A22 [Filibuster Rhymes' Used Cars — Animation Beta](https://steamcommunity.com/sharedfiles/filedetails/?id=3315561157) | A PZ vehicle mod with several contributors; no standalone asset license verified. | Request original model/texture/animation exports and contributor clearance. |

The [official PZ modding policy](https://projectzomboid.com/blog/modding-policy/) requires rights to third-party materials. A mod dependency, downloadable editor tilesheet or public repository does not itself grant rights to game-derived assets. Fallout imagery, logos, vault branding and ripped models are likewise outside the approved shortlist.

[PERMISSIONS.md](asset_discovery/PERMISSIONS.md) contains a review checklist and an unsent request template. No creator has been contacted and no permission response is implied.

## Other sources searched and unresolved candidates

| Source | Discovery result | Download/import decision |
| --- | --- | --- |
| GitHub | A16 has an explicit CC0 file and direct GLB distribution. T01 PZ Sprite Forge and T02 TileSetZ are tools, not reusable PZ art packs. | A16 is an inspection fallback. Do not equate MIT tool code with licensed game imagery. |
| OpenGameArt | A05 basic isometric human animation and A17 isometric furniture have CC0 in indexed primary-page text. | Live pages were inaccessible through the reader; previews/files are unreviewed. Hold download until normal access verifies the exact file/license. |
| Sketchfab | A18 low-poly police officer is indexed as CC Attribution. | Direct page returned 403. Exact license version, animation rig and downloadable format remain unknown; no download. |
| itch.io / RGS_Dev | A07 covers civilian cars, police SUV, ambulance and firetruck. Itch says CC0; the creator's CGTrader listing currently shows custom terms. | Hold for exact archive grant/creator clarification. A normal HTTP request also hit rate limiting; it was not retried or bypassed. |
| itch.io / JEVIN_DEV | A23 Isometric Survival advertises an eight-direction character. | No explicit reuse license located; free pricing is insufficient. Also a weaker style match. |
| itch.io / reodesuxz | A24 advertises GLB/FBX emergency vehicles with personal/commercial use, but forbids file redistribution. | Hold until public-repository and game packaging rights are clear. |

## Visual consistency strategy

Use a muted olive, warm concrete, faded blue, rust and dusty earth palette. Keep identifiable emergency colors readable. Prefer realistic human proportions, plain modern silhouettes, low roughness contrast and weathering concentrated around damage, edges and abandoned areas. Do not mix bobble-headed survivors, realistic humans and miniature buildings without a deliberate scale/proportion review.

The existing 45-degree yaw and approximately 35.264-degree camera pitch are a useful baseline. For a later sprite-render path, render **licensed models** at one agreed angle, light direction, scale and pixel density; retain shared contact shadows and foot pivots. Treat 2:1 and true-isometric projection as separate choices to test rather than mixing sheets by eye. This discovery pass does not convert the project to a sprite renderer.

Keep each scene's visual mesh under its existing behavior/selection owner. Vehicles must fit existing dimensions and keep separate wheels/doors where useful. Road meshes must respect existing lane widths and centerlines. Buildings must preserve ground-level entrances, fade/cutaway controls and walkable rooms. Vegetation and debris must not silently alter navigation or collision.

## Proposed selective integration order

1. **Verify the package:** use the normal creator download, preserve license text, pin version/hash, inspect the file list and identify any third-party components. Check the exact free edition.
2. **Preview a tiny set:** one civilian and authority appearance, one civilian/police/emergency vehicle, one house/shop, one tree and a few room/road props in an isolated Godot review scene. Confirm style at the actual gameplay camera before selecting a family.
3. **Normalize:** use GLB/glTF 2.0 where practical, apply transforms, align Y-up/front/foot pivots, reduce duplicate materials, test transparency and keep source files separately. The [Godot format guide](https://docs.godotengine.org/en/stable/tutorials/assets_pipeline/importing_3d_scenes/available_formats.html) documents FBX support and Blender's installed-tool requirement. Asset-specific compatibility is still untested.
4. **Attach visual children:** future changes belong in `scripts/three_d/agent_3d.gd`, `building_3d.gd`, `city_3d.gd`, `social_world.gd` and the relevant reusable scenes. Keep `world_coordinates.gd`, seeded state, dispatch and vehicle dimensions authoritative.
5. **Connect animation states:** map existing states to imported clips; use in-place locomotion so root motion cannot double movement. Add required missing clips only after confirming reuse options.
6. **Measure and accept:** verify feet/door alignment, fade behavior, intersections, vehicle boarding, police deployment/removal, material cost and the existing 100-agent population. Record actual import and preview results before promoting selected files into runtime assets.

## Gaps to resolve before production adoption

- No ready-made, license-cleared PZ-quality **complete** human library with the full shelter/police action set was verified.
- The regular base humans need suitable clothing/authority identity; CC0 alone does not make their advertised paid extras free.
- A police SUV is explicit in the held RGS fleet; its exact package license still needs verification.
- Damage states, equipment pivots and much post-apocalyptic wear require adaptation; clean city samples are not ruined-city variants.
- The reviewed free buildings lean away from Moroccan architectural detail. Keep them as selected foundations rather than importing a generic foreign city wholesale.

## Verified pilot imports (2026-11-12)

The four requested GitHub starting points were reviewed as discovery catalogs: [TMHSDigital/Free-Game-Dev-Assets](https://github.com/TMHSDigital/Free-Game-Dev-Assets) is a curated link list, [jjones26/free-and-open-source-game-dev-resources](https://github.com/jjones26/free-and-open-source-game-dev-resources) is a broad evolving directory, [jammyfu/awesome-game-assets](https://github.com/jammyfu/awesome-game-assets) has many categories with source-specific terms, and [Hidencod/tge-assets](https://github.com/Hidencod/tge-assets) catalogs Kenney CC0 packs. None of their repository licenses was used as a license for downloaded art. Publisher archives were inspected from [Kenney's Car Kit](https://kenney.nl/assets/car-kit), [Kenney's City Kit Commercial](https://kenney.nl/assets/city-kit-commercial), and [Quaternius' Universal Animation Library](https://quaternius.itch.io/universal-animation-library).

| Package | Archive | Exact review result | ESSAIM selection |
| --- | --- | --- | --- |
| Kenney Car Kit 3.1 | 4,814,237 bytes; SHA-256 `fac7dacac5c7874348cf19729af3ef205f3d366493edaf0a827d93f4fdf3d0c4` | `License.txt` identifies Kenney, CC0, commercial use and optional credit. 268 archive entries, 50 GLBs. Selected vehicles are 2,032-2,804 triangles each with one shared 512x512 atlas; no animations. | Five selected GLBs render in live vehicles. Imported wheel nodes follow simulation speed and steering; simulation retains movement, collision, lights and emergency logic. |
| Kenney City Kit Commercial 2.1 | 4,096,974 bytes; SHA-256 `f8b09b081c2bb88bcc126e2dec1cb40fd0dad7e7e591b6c26aaefe96fb35276b` | `License.txt` identifies Kenney, CC0, commercial use and optional credit. 228 archive entries, 41 GLBs. Three selected high-detail models are 1,195-1,276 triangles; matching low-detail models are 142-200; one shared 512x512 atlas. | All six selected models render in the city: high-detail variants in streamed chunks and matching low-detail variants in overview proxies. |

## Quaternius terms hold

The Universal Animation Library Standard archive was 15,904,933 bytes (SHA-256 `cc73fc4e495b82958207316596317a3f40b9fa38065bde1027937452da537724`). Its bundled license and current itch.io page state CC0 1.0. The exact GLB contains 13,744 triangles, a 65-bone rig and 43 clips, and it passed an initial Godot 4.7.2 import test. However, the separate [Quaternius Asset License (QAL v1.0)](https://quaternius.github.io/license.html), updated 2026-08-28, allows use in commercial products but restricts redistribution of raw assets. These official terms conflict on including the Standard GLB in ESSAIM's source repository. The GLB was removed from `assets/` and recorded as `LICENSE_CONFLICT_HOLD`; it must not be bundled again until Quaternius clarifies the exact package terms.

The Universal Base Characters Standard archive was 128,968,391 bytes (SHA-256 `fdbf1804c90dfc1ea03e992bff7da2dfd1a79318e13270a660180f9308455f40`). Its archive license says CC0 1.0, but it has the same unresolved QAL redistribution conflict. Its free full-body examples are also superhero-costumed and use several 2048×2048 textures. It is not included in the project library.

The selective extraction, manifest scanner, duplicate/unused checks and Godot developer preview live in [ASSET_LIBRARY.md](ASSET_LIBRARY.md) and [tools/asset_library.py](../tools/asset_library.py). All 11 imported Kenney GLBs are active runtime presentation assets. Vehicle movement and collision, navigation, renderer interfaces, and the existing agent animation rig remain simulation-owned. The direct package hashes, model hashes, held-package record and included license texts are in [assets/ASSET_MANIFEST.json](../assets/ASSET_MANIFEST.json) and [LICENSES.md](../LICENSES.md).
