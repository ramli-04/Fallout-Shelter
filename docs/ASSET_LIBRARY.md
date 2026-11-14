# ESSAIM asset library

The project keeps a small, locally imported set of third-party GLBs for the live city renderer and development previews. The Director Mode **Asset library** button opens the browser. It shows source, author, license, texture dimensions, polygon and mesh counts, rig/clip counts, exact-file duplicates, source references, and the current optimization/runtime status. The preview uses the orthographic projection and yaw/pitch from `resources/visual_3d.json` so models can be reviewed at the same isometric angle as the city. It can play clips when a license-cleared animated model is added.

The browser loads local files only. It does not download or update assets when the game starts.

## Imported selection

| Pack | Selected files | Import review |
| --- | --- | --- |
| [Kenney Car Kit](https://kenney.nl/assets/car-kit), v3.1 | Sedan, SUV, police car, ambulance and fire truck | 2,032-2,804 triangles per model, one material and shared 512x512 atlas. Live vehicle visuals use the imported bodies and animated wheel meshes; simulation code still owns movement, collision, lights and emergency behavior. |
| [Kenney City Kit Commercial](https://kenney.nl/assets/city-kit-commercial), v2.1 | Three building models and their three low-detail variants | 1,195-1,276 triangles for high-detail models; 142-200 for low-detail variants; shared 512x512 atlas. High-detail models render in streamed city chunks, while low-detail models cover buildings in the overview. |

Archive SHA-256 values, exact imported file hashes, source links, license files, and measured metadata are in [ASSET_MANIFEST.json](../assets/ASSET_MANIFEST.json). The original Kenney package license texts and Quaternius audit license text are under `assets/licenses/`. Source archives are retained only in the ignored `.tools/asset-discovery/downloads/` audit cache; they are not copied wholesale into the game.

Quaternius Universal Base Characters Standard and Universal Animation Library Standard were downloaded and audited but are not bundled. The character examples wear superhero costumes and use several 2048×2048 textures. Both archives and package pages say CC0, while Quaternius’ current [Asset License](https://quaternius.github.io/license.html) restricts redistribution of raw assets. That scope is unresolved for the Standard files, so the local GLB was removed from the project and the archive remains in the ignored audit cache. Do not import or redistribute either package until the publisher clarifies the license applicable to these editions.

## Source discovery and licensing

The four requested GitHub repositories are indexes and discovery catalogs, not blanket licenses for linked artwork: [Free Game Dev Assets](https://github.com/TMHSDigital/Free-Game-Dev-Assets), [Free and Open Source Game Development Resources](https://github.com/jjones26/free-and-open-source-game-dev-resources), [Awesome Game Assets](https://github.com/jammyfu/awesome-game-assets), and [Kenney CC0 catalog](https://github.com/Hidencod/tge-assets). The selected files came from Kenney publisher downloads. Each downloaded archive was checked for its own license file before extraction.

The two selected Kenney archives identify Kenney and state CC0, commercial use permitted, and attribution not required. ESSAIM keeps the supplied license text and creator/source record. Do not infer an asset license from a GitHub repository license or from a different edition of the package.

## Add or refresh a package

1. Use the publisher's normal download flow for the exact free package. The CLI can fetch a direct publisher/CDN HTTPS URL when a reviewed SHA-256 is available. It refuses other domains, redirects outside the publisher/CDN allowlist, checksum mismatches, and archives over 300 MiB. Do not use third-party game rips or treat a catalog page as a license grant.
2. Inspect the archive's license and file list. Keep its version, retrieval date, archive SHA-256, and author in the asset record. Account, payment, or download restrictions are not bypassed by the tool.
3. Use the allowlisted extractor for a reviewed package:

   ```powershell
   .venv/Scripts/python.exe tools/asset_library.py import-archive --pack kenney-car-kit --archive .tools/asset-discovery/downloads/kenney-car-kit.zip
   .venv/Scripts/python.exe tools/asset_library.py import-archive --pack kenney-city-commercial --archive .tools/asset-discovery/downloads/kenney-city-kit-commercial.zip
   ```

   To repeat an exact pinned acquisition, pass the publisher's direct archive URL and the SHA-256 recorded in the manifest:

   ```powershell
   .venv/Scripts/python.exe tools/asset_library.py download --url <publisher-archive-url> --sha256 <64-character-sha256> --output .tools/asset-discovery/downloads/package.zip
   ```

   Extraction rejects an archive whose bundled license does not match the reviewed creator/CC0 terms. It copies only the listed GLBs, shared textures and license text. Kenney GLB texture references are rewritten to use one shared atlas per pack.
4. Add a manifest record in `assets/ASSET_MANIFEST.json`, including original source, discovery catalog, author, license evidence, archive hash, local file path and runtime/preview status.
5. Run the scanner and validator. Launch Godot’s editor once to import updated GLB/texture resources, then use the in-game browser and inspect the asset at gameplay scale before binding it to a production renderer.

   ```powershell
   .venv/Scripts/python.exe tools/asset_library.py scan
   .venv/Scripts/python.exe tools/asset_library.py validate
   & "$env:USERPROFILE/Downloads/godot/Godot_v4.7.2-stable_win64_console.exe" --headless --editor --path . --quit
   ```

`scan` refreshes file hashes, geometry, material/mesh/rig/clip information, texture dimensions and an RGBA8-with-mipmaps memory estimate. It compares exact file hashes and searches source files for direct `res://` references. Models referenced by `runtime_model_catalog.gd` should be reported as `RUNTIME_REFERENCED`. The estimates are conservative diagnostics, not measurements of final GPU residency; Godot compression, texture filtering and driver allocation affect actual memory.

## GPU and rendering budget

- Each Kenney 512×512 RGBA8 atlas is estimated at about 1.33 MiB including a full mip chain; both packs together are about 2.66 MiB if resident. The GLBs point at one shared atlas per pack.
- Selected Kenney vehicles use about 2.0k-2.8k triangles each. City buildings have matching low-detail models: the three pairs reduce geometry by about 84-88%; the low-detail set is used by the overview renderer.
- The preview SubViewport updates only while its window is visible. Godot's scene/resource cache shares imported model resources between vehicles and building instances.
- These are asset-level estimates. A live-scene GPU profiler measurement has not been recorded.

## Runtime boundary

Kenney car and building models are active presentation assets. The Godot scene remains authoritative for evacuation, navigation, collision, crowd logic, vehicle motion, lighting, and building access. Vehicle GLBs have no authored wheel clips, so the vehicle renderer animates their wheel nodes from simulation speed and steering. The Quaternius clips are held outside the library pending license clarification. Decorative yard fences were removed; operational roadblocks remain part of the traffic simulation.
