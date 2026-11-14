# Asset discovery catalog

Start with [the discovery report](../ASSET_DISCOVERY_REPORT.md) or open [gallery.html](gallery.html) in a browser. The gallery works without a server; its publisher-hosted images need internet access. Source pages remain available when an image host fails. Images are reference previews, not in-engine validation.

`catalog.json` is the canonical register. `catalog.csv` is its spreadsheet-readable view. Both cover the same 26 entries. Licensing decisions also appear in the root [LICENSES.md](../../LICENSES.md). The imported pilot files and developer preview are documented in [ASSET_LIBRARY.md](../ASSET_LIBRARY.md).

A06 (Kenney Car Kit) and A09 (Kenney City Kit Commercial) have selected files integrated into the live vehicle and building renderers. A01 and A02 were downloaded and audited but are held because the package CC0 statements conflict with Quaternius' current QAL restriction on redistributing raw assets. A01 also has superhero styling and a 2K texture budget. A creator's CC0 statement is a useful download gate; it does not replace inspecting the exact downloaded archive and current terms. Unknown formats, absent actions, free-tier boundaries, custom permissions, inaccessible pages and license conflicts are recorded explicitly.

For each later selected file, add the exact archive page/version, retrieval date, archive SHA-256, original file license, creator/credit, source filename, conversion settings, preview result and final Godot path. Only then promote a verified file into a runtime visual component and record the renderer binding. Update CSV and the licensing register when changing the JSON.

This directory is excluded from Godot resource import with `.gdignore`. The game reads only `assets/ASSET_MANIFEST.json` for the developer preview browser; no runtime downloader is present. Temporary publisher-preview inspection images and source ZIP archives remain in ignored `.tools/asset-discovery/`.
