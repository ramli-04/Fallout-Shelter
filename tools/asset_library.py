#!/usr/bin/env python3
"""Inspect and import a small, explicitly selected set of ESSAIM assets.

This tool never runs as part of the game. It consumes archives downloaded by a
developer from the original publisher and extracts only the allowlisted files.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import math
import re
import struct
import sys
import tempfile
import urllib.request
from urllib.parse import urlparse
import zipfile
from collections import defaultdict
from datetime import date
from pathlib import Path, PurePosixPath
from typing import Any


ROOT = Path(__file__).resolve().parents[1]
MANIFEST_PATH = Path("assets/ASSET_MANIFEST.json")
MAX_ARCHIVE_BYTES = 300 * 1024 * 1024
ALLOWED_DOWNLOAD_HOSTS = ("kenney.nl", "quaternius.com", "quaternius.itch.io", "itch.io", "itch.zone")
KENNEY_CAR_LICENSE = "licenses/kenney/car_kit/LICENSE.txt"
KENNEY_CITY_LICENSE = "licenses/kenney/city_kit_commercial/LICENSE.txt"
PACKS: dict[str, dict[str, Any]] = {
    "kenney-car-kit": {
        "license_entry": "License.txt",
        "license_path": KENNEY_CAR_LICENSE,
        "required_license_tokens": ("CC0", "Kenney"),
        "license_markers": ("Creative Commons Zero", "Created/distributed by Kenney"),
        "extract": {
            "Models/GLB format/sedan.glb": "vehicles/civilian/kenney/sedan.glb",
            "Models/GLB format/suv.glb": "vehicles/civilian/kenney/suv.glb",
            "Models/GLB format/police.glb": "vehicles/emergency/kenney/police.glb",
            "Models/GLB format/ambulance.glb": "vehicles/emergency/kenney/ambulance.glb",
            "Models/GLB format/firetruck.glb": "vehicles/emergency/kenney/firetruck.glb",
            "Models/GLB format/Textures/colormap.png": "textures/kenney/car_kit_colormap.png",
        },
        "shared_texture": ("Models/GLB format/Textures/colormap.png", "../../../textures/kenney/car_kit_colormap.png"),
    },
    "kenney-city-commercial": {
        "license_entry": "License.txt",
        "license_path": KENNEY_CITY_LICENSE,
        "required_license_tokens": ("CC0", "Kenney"),
        "license_markers": ("Creative Commons Zero", "Created/distributed by Kenney"),
        "extract": {
            **{f"Models/GLB format/building-{letter}.glb": f"buildings/commercial/kenney/building-{letter}.glb" for letter in "abc"},
            **{f"Models/GLB format/low-detail-building-{letter}.glb": f"buildings/commercial/kenney/low-detail-building-{letter}.glb" for letter in "abc"},
            "Models/GLB format/Textures/colormap.png": "textures/kenney/city_commercial_colormap.png",
        },
        "shared_texture": ("Models/GLB format/Textures/colormap.png", "../../../textures/kenney/city_commercial_colormap.png"),
    },
}


def sha256(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def read_json(path: Path) -> dict[str, Any]:
    return json.loads(path.read_text(encoding="utf-8"))


def glb_document(data: bytes) -> tuple[dict[str, Any], bytes | None]:
    if len(data) < 20 or data[:4] != b"glTF":
        raise ValueError("Not a valid GLB file")
    version, declared_size = struct.unpack_from("<II", data, 4)
    if version != 2 or declared_size != len(data):
        raise ValueError("Unsupported or malformed GLB header")
    json_size, json_type = struct.unpack_from("<II", data, 12)
    if json_type != 0x4E4F534A or 20 + json_size > len(data):
        raise ValueError("GLB JSON chunk is missing or malformed")
    document = json.loads(data[20:20 + json_size].decode("utf-8").rstrip(" \0"))
    offset = 20 + json_size
    binary = None
    if offset + 8 <= len(data):
        chunk_size, chunk_type = struct.unpack_from("<II", data, offset)
        if chunk_type == 0x004E4942 and offset + 8 + chunk_size <= len(data):
            binary = data[offset + 8:offset + 8 + chunk_size]
    return document, binary


def rewrite_glb_image_uri(data: bytes, uri: str) -> bytes:
    """Point a Kenney GLB at the shared atlas in assets/textures."""
    document, binary = glb_document(data)
    if len(document.get("images", [])) != 1:
        raise ValueError("Expected one shared atlas image in Kenney GLB")
    document["images"][0]["uri"] = uri
    json_bytes = json.dumps(document, separators=(",", ":"), ensure_ascii=False).encode("utf-8")
    json_bytes += b" " * ((4 - len(json_bytes) % 4) % 4)
    chunks = [struct.pack("<II", len(json_bytes), 0x4E4F534A), json_bytes]
    if binary is not None:
        binary += b"\0" * ((4 - len(binary) % 4) % 4)
        chunks.extend((struct.pack("<II", len(binary), 0x004E4942), binary))
    total = 12 + sum(map(len, chunks))
    return b"glTF" + struct.pack("<II", 2, total) + b"".join(chunks)


def inspect_gltf(data: bytes) -> dict[str, Any]:
    if data[:4] == b"glTF":
        document, _ = glb_document(data)
    else:
        document = json.loads(data.decode("utf-8"))
    accessors = document.get("accessors", [])
    triangle_count = 0
    vertex_count = 0
    for mesh in document.get("meshes", []):
        for primitive in mesh.get("primitives", []):
            indices = primitive.get("indices")
            if indices is not None:
                triangle_count += int(accessors[indices].get("count", 0)) // 3
            else:
                position_accessor = primitive.get("attributes", {}).get("POSITION")
                if position_accessor is not None:
                    triangle_count += int(accessors[position_accessor].get("count", 0)) // 3
            position_accessor = primitive.get("attributes", {}).get("POSITION")
            if position_accessor is not None:
                vertex_count += int(accessors[position_accessor].get("count", 0))
    return {
        "format": "glb" if data[:4] == b"glTF" else "gltf",
        "vertex_count": vertex_count,
        "polygon_count": triangle_count,
        "mesh_count": len(document.get("meshes", [])),
        "material_count": len(document.get("materials", [])),
        "skeleton_count": len(document.get("skins", [])),
        "bone_count": max((len(skin.get("joints", [])) for skin in document.get("skins", [])), default=0),
        "animation_count": len(document.get("animations", [])),
        "animation_names": [item.get("name", "Unnamed") for item in document.get("animations", [])],
        "image_uris": [image.get("uri", "embedded") for image in document.get("images", [])],
    }


def png_dimensions(data: bytes) -> tuple[int, int] | None:
    if len(data) >= 24 and data[:8] == b"\x89PNG\r\n\x1a\n":
        return struct.unpack_from(">II", data, 16)
    return None


def validate_license(pack: dict[str, Any], license_data: bytes) -> str:
    license_text = license_data.decode("utf-8", errors="replace")
    missing = [marker for marker in pack["license_markers"] if marker.lower() not in license_text.lower()]
    if missing:
        raise ValueError("Archive license does not match the reviewed publisher terms: " + ", ".join(missing))
    return license_text


def validate_download_url(url: str) -> None:
    parsed = urlparse(url)
    host = (parsed.hostname or "").lower().rstrip(".")
    trusted_host = any(host == domain or host.endswith("." + domain) for domain in ALLOWED_DOWNLOAD_HOSTS)
    if parsed.scheme != "https" or not trusted_host:
        raise ValueError("Use a direct HTTPS archive URL from Kenney, Quaternius, or itch.io")


def download_archive(url: str, output: Path, expected_sha256: str) -> Path:
    validate_download_url(url)
    if not re.fullmatch(r"[0-9a-fA-F]{64}", expected_sha256):
        raise ValueError("A 64-character expected SHA-256 is required")
    output.parent.mkdir(parents=True, exist_ok=True)
    request = urllib.request.Request(url, headers={"User-Agent": "ESSAIM-AssetLibrary/1.0"})
    with urllib.request.urlopen(request, timeout=45) as response:
        final_url = response.geturl()
        validate_download_url(final_url)
        content_length = response.headers.get("Content-Length")
        if content_length and int(content_length) > MAX_ARCHIVE_BYTES:
            raise ValueError("Archive exceeds the 300 MiB development download limit")
        digest = hashlib.sha256()
        downloaded = 0
        temporary_name = None
        try:
            with tempfile.NamedTemporaryFile(prefix=".asset-download-", dir=output.parent, delete=False) as temporary:
                temporary_name = Path(temporary.name)
                while True:
                    chunk = response.read(1024 * 1024)
                    if not chunk:
                        break
                    downloaded += len(chunk)
                    if downloaded > MAX_ARCHIVE_BYTES:
                        raise ValueError("Archive exceeds the 300 MiB development download limit")
                    digest.update(chunk)
                    temporary.write(chunk)
            if digest.hexdigest().lower() != expected_sha256.lower():
                raise ValueError("Downloaded archive SHA-256 does not match the reviewed value")
            temporary_name.replace(output)
            return output
        finally:
            if temporary_name and temporary_name.exists():
                temporary_name.unlink()


def import_archive(pack_id: str, archive: Path, project_root: Path) -> list[Path]:
    pack = PACKS[pack_id]
    if not zipfile.is_zipfile(archive):
        raise ValueError(f"Archive is not a valid ZIP: {archive}")
    imported: list[Path] = []
    with zipfile.ZipFile(archive) as source:
        names = set(source.namelist())
        license_entry = pack["license_entry"]
        if license_entry not in names:
            raise ValueError(f"Expected archive license file is missing: {license_entry}")
        license_data = source.read(license_entry)
        validate_license(pack, license_data)
        for entry, relative_destination in pack["extract"].items():
            if entry not in names:
                raise ValueError(f"Allowlisted asset missing from archive: {entry}")
            output = project_root / "assets" / relative_destination
            output.parent.mkdir(parents=True, exist_ok=True)
            contents = source.read(entry)
            if entry.lower().endswith(".glb") and pack["shared_texture"]:
                texture_entry, uri = pack["shared_texture"]
                if texture_entry not in names:
                    raise ValueError(f"Referenced shared texture missing: {texture_entry}")
                contents = rewrite_glb_image_uri(contents, uri)
            output.write_bytes(contents)
            imported.append(output)
        license_out = project_root / "assets" / pack["license_path"]
        license_out.parent.mkdir(parents=True, exist_ok=True)
        license_out.write_bytes(license_data)
        imported.append(license_out)
    return imported


def load_manifest(root: Path) -> dict[str, Any]:
    path = root / MANIFEST_PATH
    if not path.exists():
        raise FileNotFoundError(f"Asset manifest not found: {path}")
    return read_json(path)


def source_reference_count(root: Path, resource_path: str) -> int:
    occurrences = 0
    for folder in ("scripts", "scenes", "resources"):
        base = root / folder
        if not base.exists():
            continue
        for path in base.rglob("*"):
            if path.suffix.lower() not in {".gd", ".tscn", ".tres", ".json", ".cfg"}:
                continue
            try:
                occurrences += path.read_text(encoding="utf-8", errors="ignore").count(resource_path)
            except OSError:
                continue
    return occurrences


def analyse_asset(root: Path, asset: dict[str, Any]) -> dict[str, Any]:
    resource_path = str(asset.get("path", ""))
    disk_path = root / resource_path.removeprefix("res://")
    if not disk_path.is_file():
        return {"exists": False, "path": resource_path, "error": "file missing"}
    data = disk_path.read_bytes()
    report: dict[str, Any] = {
        "exists": True,
        "path": resource_path,
        "bytes": len(data),
        "sha256": sha256(data),
        "format": disk_path.suffix.removeprefix(".").lower(),
    }
    if disk_path.suffix.lower() in {".glb", ".gltf"}:
        report.update(inspect_gltf(data))
        dimensions = []
        for uri in report["image_uris"]:
            if uri == "embedded":
                continue
            texture_path = (disk_path.parent / PurePosixPath(uri)).resolve()
            if texture_path.exists():
                texture_size = png_dimensions(texture_path.read_bytes())
                if texture_size:
                    dimensions.append({"path": uri, "width": texture_size[0], "height": texture_size[1]})
        report["textures"] = dimensions
        report["estimated_texture_vram_bytes"] = sum(
            math.ceil(item["width"] * item["height"] * 4 * 4 / 3) for item in dimensions
        )
    elif disk_path.suffix.lower() == ".png":
        dimensions = png_dimensions(data)
        report["textures"] = [] if dimensions is None else [{"path": disk_path.name, "width": dimensions[0], "height": dimensions[1]}]
        report["estimated_texture_vram_bytes"] = 0 if dimensions is None else math.ceil(dimensions[0] * dimensions[1] * 4 * 4 / 3)
    references = source_reference_count(root, resource_path)
    report["source_references"] = references
    report["usage_status"] = "RUNTIME_REFERENCED" if references else "PREVIEW_LIBRARY_ONLY"
    report["optimized"] = bool(asset.get("optimized", False))
    return report


def scan_manifest(root: Path, write: bool) -> tuple[dict[str, Any], list[str]]:
    manifest = load_manifest(root)
    errors: list[str] = []
    sha_groups: dict[str, list[str]] = defaultdict(list)
    analyses = {}
    for asset in manifest.get("assets", []):
        analysis = analyse_asset(root, asset)
        analyses[str(asset.get("id", "?"))] = analysis
        if not analysis.get("exists"):
            errors.append(f"{asset.get('id')}: {analysis.get('error')}")
            continue
        sha_groups[analysis["sha256"]].append(str(asset.get("id", "?")))
        for field in ("polygon_count", "mesh_count", "material_count", "skeleton_count", "bone_count", "animation_count", "animation_names", "textures", "estimated_texture_vram_bytes", "format", "vertex_count"):
            if field in analysis:
                asset[field] = analysis[field]
        asset["file_size_bytes"] = analysis["bytes"]
        asset["file_sha256"] = analysis["sha256"]
        asset["usage_status"] = analysis["usage_status"]
        asset["duplicate_of"] = []
    for asset in manifest.get("assets", []):
        asset_id = str(asset.get("id", "?"))
        analysis = analyses.get(asset_id, {})
        digest = analysis.get("sha256")
        if digest and len(sha_groups[digest]) > 1:
            asset["duplicate_of"] = [other for other in sha_groups[digest] if other != asset_id]
    manifest["last_scanned"] = date.today().isoformat()
    if write:
        (root / MANIFEST_PATH).write_text(json.dumps(manifest, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
    return manifest, errors


def validate_manifest(manifest: dict[str, Any], root: Path) -> list[str]:
    errors = []
    ids = set()
    for asset in manifest.get("assets", []):
        asset_id = str(asset.get("id", ""))
        if not asset_id or asset_id in ids:
            errors.append(f"duplicate or empty asset ID: {asset_id!r}")
        ids.add(asset_id)
        for field in ("name", "category", "source_repository", "original_source", "source_page", "download_page", "license", "license_url", "license_evidence_url", "author", "path", "format", "archive_name", "archive_sha256"):
            if not asset.get(field):
                errors.append(f"{asset_id}: missing {field}")
        if asset.get("commercial_use") is None or asset.get("attribution_required") is None:
            errors.append(f"{asset_id}: license permissions are incomplete")
        path = root / str(asset.get("path", "")).removeprefix("res://")
        if not path.is_file():
            errors.append(f"{asset_id}: missing imported file {path}")
        license_path = root / str(asset.get("license_file", "")).removeprefix("res://")
        if not license_path.is_file():
            errors.append(f"{asset_id}: missing bundled license text {license_path}")
        elif asset.get("license") == "CC0-1.0":
            license_text = license_path.read_text(encoding="utf-8", errors="replace").lower()
            if "cc0" not in license_text:
                errors.append(f"{asset_id}: bundled license text does not mention CC0")
        expected = asset.get("file_sha256")
        if path.is_file() and expected and sha256(path.read_bytes()) != expected:
            errors.append(f"{asset_id}: SHA-256 mismatch")
        archive_hash = str(asset.get("archive_sha256", ""))
        if not re.fullmatch(r"[0-9a-fA-F]{64}", archive_hash):
            errors.append(f"{asset_id}: invalid archive SHA-256")
        source_hash = str(asset.get("source_file_sha256", ""))
        if not re.fullmatch(r"[0-9a-fA-F]{64}", source_hash):
            errors.append(f"{asset_id}: invalid publisher-file SHA-256")
    for candidate in manifest.get("held_assets", []):
        candidate_id = str(candidate.get("id", ""))
        if not candidate_id or candidate_id in ids:
            errors.append(f"duplicate or empty held asset ID: {candidate_id!r}")
        ids.add(candidate_id)
        if candidate.get("license_status") != "LICENSE_CONFLICT_HOLD":
            errors.append(f"{candidate_id}: held candidate must carry LICENSE_CONFLICT_HOLD")
        if candidate.get("path"):
            errors.append(f"{candidate_id}: license-held raw asset must not have a project path")
        for field in ("archive_sha256", "source_file_sha256"):
            if not re.fullmatch(r"[0-9a-fA-F]{64}", str(candidate.get(field, ""))):
                errors.append(f"{candidate_id}: invalid held-candidate {field}")
        evidence_path = root / str(candidate.get("archive_license_file", "")).removeprefix("res://")
        if not evidence_path.is_file():
            errors.append(f"{candidate_id}: missing archive license evidence {evidence_path}")
    return errors


def command_import(args: argparse.Namespace) -> int:
    for path in import_archive(args.pack, args.archive, args.project_root.resolve()):
        print(path.relative_to(args.project_root.resolve()).as_posix())
    return 0


def command_download(args: argparse.Namespace) -> int:
    path = download_archive(args.url, args.output, args.sha256)
    print(f"Downloaded and hash-verified publisher archive: {path}")
    return 0


def command_scan(args: argparse.Namespace) -> int:
    manifest, errors = scan_manifest(args.project_root.resolve(), write=not args.check_only)
    for asset in manifest.get("assets", []):
        print(f"{asset.get('id'):>3}  {asset.get('name')}  {asset.get('polygon_count', 0):,} tris  {asset.get('usage_status', 'UNKNOWN')}")
    if errors:
        print("\nScan errors:", *errors, sep="\n- ", file=sys.stderr)
    return 1 if errors else 0


def command_validate(args: argparse.Namespace) -> int:
    manifest = load_manifest(args.project_root.resolve())
    errors = validate_manifest(manifest, args.project_root.resolve())
    if errors:
        print("Validation failed:", *errors, sep="\n- ", file=sys.stderr)
        return 1
    print(f"Validated {len(manifest.get('assets', []))} library assets and {len(manifest.get('held_assets', []))} license holds.")
    return 0


def command_report(args: argparse.Namespace) -> int:
    manifest = load_manifest(args.project_root.resolve())
    for asset in manifest.get("assets", []):
        print(
            f"{asset['id']:>3} {asset['name']} | {asset.get('polygon_count', 0):,} tris | "
            f"{asset.get('format', '?')} | {asset.get('license', '?')} | "
            f"{asset.get('usage_status', 'NOT_SCANNED')}"
        )
    return 0


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description=__doc__)
    subparsers = parser.add_subparsers(dest="command", required=True)
    importer = subparsers.add_parser("import-archive", help="extract a reviewed allowlist from a publisher ZIP")
    importer.add_argument("--pack", choices=sorted(PACKS), required=True)
    importer.add_argument("--archive", type=Path, required=True)
    importer.add_argument("--project-root", type=Path, default=ROOT)
    importer.set_defaults(func=command_import)
    downloader = subparsers.add_parser("download", help="download a pinned archive from an original publisher/CDN")
    downloader.add_argument("--url", required=True, help="direct HTTPS file URL obtained from the publisher's normal download flow")
    downloader.add_argument("--output", type=Path, required=True)
    downloader.add_argument("--sha256", required=True, help="expected archive SHA-256 from the reviewed asset record")
    downloader.set_defaults(func=command_download)
    scanner = subparsers.add_parser("scan", help="refresh metadata, hashes, duplicates and source usage")
    scanner.add_argument("--project-root", type=Path, default=ROOT)
    scanner.add_argument("--check-only", action="store_true")
    scanner.set_defaults(func=command_scan)
    validator = subparsers.add_parser("validate", help="check files, manifest fields, bundled licenses and hashes")
    validator.add_argument("--project-root", type=Path, default=ROOT)
    validator.set_defaults(func=command_validate)
    report = subparsers.add_parser("report", help="print a compact asset inventory")
    report.add_argument("--project-root", type=Path, default=ROOT)
    report.set_defaults(func=command_report)
    return parser


def main() -> int:
    args = build_parser().parse_args()
    try:
        return args.func(args)
    except (OSError, ValueError, KeyError, zipfile.BadZipFile, json.JSONDecodeError) as error:
        print(f"asset_library: {error}", file=sys.stderr)
        return 2


if __name__ == "__main__":
    raise SystemExit(main())
