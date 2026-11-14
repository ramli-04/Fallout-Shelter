# Categorized reference collection

The existing lowercase `assets/` and `scenes/` roots are retained for compatibility
with the project and Linux exports. Windows cannot host separate `Assets` and
`assets` directories. The requested categories are now available:

- `assets/buildings/Houses/`
- `assets/buildings/Apartments/`
- `assets/buildings/Police/`
- `assets/buildings/FireStations/`
- `assets/buildings/Offices/`
- `assets/buildings/Parking/`
- `assets/Nature/Trees/`
- `assets/Nature/Bushes/`
- `assets/Nature/Grass/`
- `assets/Roads/`
- `scenes/ReferenceAssets/` with matching reusable visual prefabs.

The `.tres` cutouts are Godot AtlasTexture resources, usable directly by Sprite2D
or Sprite3D. They share one PNG rather than duplicating pixels. Some tightly packed
illustrations have overlapping rectangular bounds; the provided scenes and live
renderer apply cutout masks to remove neighboring artwork. The scene prefabs are
flat image meshes compatible with the existing map renderer, not reconstructed
solid buildings. Existing colliders and simulation footprints remain separate.

`resources/reference_collection.json` stores the 26 regions and categories.
`assets/reference_city/neighborhood-nature.png` is a transparent AI-edited
preparation of the user's newly supplied sheet. Built-in imagegen was used to
remove the checkerboard and presentation labels while preserving the original
composition and detailed illustration style. Prompt: preserve the 1536x1024
layout and every object; replace only checkerboard/background/labels with alpha.
The result is a prepared derivative, not a claim of pixel-exact extraction.

The live map mixes the new houses and apartments with the prior sheet, updates
police/fire/office art, adds the parking-garage variant in industrial parcels,
and replaces playable and horizon cone trees with flat tree illustrations.
Eight tree variants are batched by texture region; shrubs add planted detail.
Hospital and motel artwork from previous sheets remain available. Asset import
uses mipmaps for overview rendering. No new physics is attached to bushes.

Regenerate categorized resources after changing atlas regions:
`godot --headless --path . --script res://tools/organize_reference_assets.gd`
Restart to refresh loaded visuals. No new map generation is required.
