import importlib.util
import json
import struct
import tempfile
import unittest
import zipfile
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
SPEC = importlib.util.spec_from_file_location("asset_library", ROOT / "tools" / "asset_library.py")
asset_library = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(asset_library)


def make_glb(document: dict) -> bytes:
    payload = json.dumps(document, separators=(",", ":")).encode("utf-8")
    payload += b" " * ((4 - len(payload) % 4) % 4)
    chunk = struct.pack("<II", len(payload), 0x4E4F534A) + payload
    return b"glTF" + struct.pack("<II", 2, 12 + len(chunk)) + chunk


class AssetLibraryTests(unittest.TestCase):
    def test_inspects_mesh_triangle_and_animation_counts(self):
        document = {
            "meshes": [{"primitives": [{"indices": 0, "attributes": {"POSITION": 1}}]}],
            "accessors": [{"count": 9}, {"count": 6}],
            "materials": [{}],
            "skins": [{"joints": [0, 1, 2]}],
            "animations": [{"name": "Walk"}],
            "images": [{"uri": "Textures/color.png"}],
        }
        inspected = asset_library.inspect_gltf(make_glb(document))
        self.assertEqual(inspected["polygon_count"], 3)
        self.assertEqual(inspected["vertex_count"], 6)
        self.assertEqual(inspected["mesh_count"], 1)
        self.assertEqual(inspected["bone_count"], 3)
        self.assertEqual(inspected["animation_names"], ["Walk"])

    def test_shared_texture_rewrite_keeps_valid_glb(self):
        original = make_glb({"images": [{"uri": "Textures/colormap.png"}], "meshes": []})
        rewritten = asset_library.rewrite_glb_image_uri(original, "../../../textures/shared.png")
        document, _ = asset_library.glb_document(rewritten)
        self.assertEqual(document["images"][0]["uri"], "../../../textures/shared.png")

    def test_importer_rejects_archive_without_reviewed_license(self):
        with tempfile.TemporaryDirectory() as temporary:
            archive = Path(temporary) / "bad.zip"
            with zipfile.ZipFile(archive, "w") as package:
                package.writestr("License.txt", "Copyright, all rights reserved")
                package.writestr("Models/GLB format/sedan.glb", make_glb({"images": [{"uri": "atlas.png"}]}))
            with self.assertRaisesRegex(ValueError, "license"):
                asset_library.import_archive("kenney-car-kit", archive, Path(temporary) / "project")

    def test_pinned_downloader_accepts_only_publisher_https_hosts(self):
        asset_library.validate_download_url("https://kenney.nl/assets/car-kit/download")
        asset_library.validate_download_url("https://files.quaternius.com/pack.zip")
        asset_library.validate_download_url("https://download123.itch.zone/archive.zip")
        for url in ("http://kenney.nl/archive.zip", "https://fakekenney.nl/archive.zip", "https://example.com/archive.zip"):
            with self.subTest(url=url), self.assertRaises(ValueError):
                asset_library.validate_download_url(url)

    def test_manifest_has_unique_ids_and_bundled_license_files(self):
        manifest = json.loads((ROOT / "assets" / "ASSET_MANIFEST.json").read_text(encoding="utf-8"))
        errors = asset_library.validate_manifest(manifest, ROOT)
        self.assertEqual(errors, [])
        self.assertEqual(len(manifest["assets"]), len({item["id"] for item in manifest["assets"]}))
        held = {item["id"]: item for item in manifest.get("held_assets", [])}
        self.assertEqual(held["QANIM01"]["license_status"], "LICENSE_CONFLICT_HOLD")
        self.assertNotIn("path", held["QANIM01"])
        license_path = ROOT / held["QANIM01"]["archive_license_file"].removeprefix("res://")
        self.assertTrue(license_path.is_file())

    def test_conflicted_quaternius_pack_is_not_in_extractor_allowlist(self):
        self.assertNotIn("quaternius-animation-library", asset_library.PACKS)

    def test_scanner_marks_exact_duplicates_and_unreferenced_previews(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            first = root / "assets" / "models" / "first.glb"
            second = root / "assets" / "models" / "second.glb"
            first.parent.mkdir(parents=True)
            contents = make_glb({"meshes": [], "images": []})
            first.write_bytes(contents)
            second.write_bytes(contents)
            manifest = {
                "schema_version": 1,
                "assets": [
                    {"id": "one", "name": "one", "path": "res://assets/models/first.glb", "optimized": False},
                    {"id": "two", "name": "two", "path": "res://assets/models/second.glb", "optimized": False},
                ],
            }
            (root / "assets" / "ASSET_MANIFEST.json").write_text(json.dumps(manifest), encoding="utf-8")
            scanned, errors = asset_library.scan_manifest(root, write=False)
            self.assertEqual(errors, [])
            by_id = {item["id"]: item for item in scanned["assets"]}
            self.assertEqual(by_id["one"]["duplicate_of"], ["two"])
            self.assertEqual(by_id["two"]["duplicate_of"], ["one"])
            self.assertEqual(by_id["one"]["usage_status"], "PREVIEW_LIBRARY_ONLY")


if __name__ == "__main__":
    unittest.main()
