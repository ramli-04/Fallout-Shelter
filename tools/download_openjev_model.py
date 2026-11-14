"""Resumable bounded-range download for the pinned public Laya checkpoint on Windows."""
from concurrent.futures import ThreadPoolExecutor, as_completed
import hashlib
import json
from pathlib import Path
import time

import httpx

ROOT = Path(__file__).resolve().parents[1]
CHUNK = 8 * 1024 * 1024


def download():
    config = json.loads((ROOT / "config/openjev.json").read_text())
    repository, revision = config["checkpoint"], config["checkpoint_revision"]
    destination = ROOT / ".tools/openjev/checkpoint"
    destination.mkdir(parents=True, exist_ok=True)
    base = f"https://huggingface.co/{repository}/resolve/{revision}/"
    with httpx.Client(timeout=90, follow_redirects=True) as client:
        for name in ["rl_agent_config.json", "encoder/config.json", "tokenizer/tokenizer.json", "tokenizer/tokenizer_config.json"]:
            path = destination / name
            if not path.exists():
                response = client.get(base + name)
                response.raise_for_status()
                path.parent.mkdir(parents=True, exist_ok=True)
                path.write_bytes(response.content)
        head = client.head(base + "model.safetensors", follow_redirects=False)
        head.raise_for_status() if head.status_code >= 400 else None
        size = int(head.headers["x-linked-size"])
        digest = head.headers["x-linked-etag"].strip('"')
    target = destination / "model.safetensors"
    if target.exists() and target.stat().st_size == size:
        with target.open("rb") as stream:
            if hashlib.file_digest(stream,"sha256").hexdigest()!=digest:
                raise RuntimeError("Existing checkpoint differs from the pinned revision")
        print("Laya checkpoint already downloaded.", flush=True)
        return
    partial = destination / "model.safetensors.partial"
    state_path = destination / "download-state.json"
    state = json.loads(state_path.read_text()) if state_path.exists() else {}
    if state.get("sha256") != digest or not partial.exists() or partial.stat().st_size != size:
        state = {"sha256": digest, "revision": revision, "size": size, "complete": []}
        with partial.open("wb") as stream:
            stream.truncate(size)
        # Reuse complete chunks from an interrupted official Hub download.
        prefix_files = list((ROOT / ".tools/openjev/models/hub").glob(f"**/{digest}*.incomplete"))
        if prefix_files:
            prefix = max(prefix_files, key=lambda path: path.stat().st_size)
            with prefix.open("rb") as source, partial.open("r+b") as output:
                for index in range(prefix.stat().st_size // CHUNK):
                    data = source.read(CHUNK)
                    if len(data) != CHUNK:
                        break
                    output.seek(index * CHUNK)
                    output.write(data)
                    state["complete"].append(index)
    count = (size + CHUNK - 1) // CHUNK

    def part(index):
        start, end = index * CHUNK, min((index + 1) * CHUNK, size) - 1
        for attempt in range(4):
            try:
                with httpx.stream("GET", base + "model.safetensors", headers={"Range": f"bytes={start}-{end}"},
                                  follow_redirects=True, timeout=90) as response:
                    response.raise_for_status()
                    if response.status_code != 206 or not response.headers.get("content-range", "").startswith(f"bytes {start}-{end}/"):
                        raise RuntimeError("Checkpoint server returned an unexpected byte range")
                    written = 0
                    with partial.open("r+b") as output:
                        output.seek(start)
                        for data in response.iter_bytes(256 * 1024):
                            if written + len(data) > end - start + 1:
                                raise RuntimeError("Checkpoint range exceeds expected length")
                            output.write(data)
                            written += len(data)
                    if written != end - start + 1:
                        raise RuntimeError("Incomplete checkpoint range")
                return index
            except (httpx.HTTPError, RuntimeError):
                if attempt == 3:
                    raise
                time.sleep(min(1 + attempt, 3))

    missing = [index for index in range(count) if index not in state["complete"]]
    print(f"Downloading pinned Laya weights: {size / 1024**2:.1f} MiB, {len(missing)} ranges remaining", flush=True)
    with ThreadPoolExecutor(max_workers=8) as pool:
        futures = [pool.submit(part, index) for index in missing]
        for result in as_completed(futures):
            try:
                completed_index=result.result()
            except Exception:
                for future in futures: future.cancel()
                raise
            state["complete"].append(completed_index)
            temporary = state_path.with_suffix(".tmp")
            temporary.write_text(json.dumps(state))
            temporary.replace(state_path)
            if len(state["complete"]) % 8 == 0 or len(state["complete"]) == count:
                print(f"Downloaded {len(state['complete'])}/{count} ranges", flush=True)
    with partial.open("rb") as stream:
        actual = hashlib.file_digest(stream, "sha256").hexdigest()
    if actual != digest:
        raise RuntimeError("Laya checkpoint SHA-256 mismatch; model was not activated")
    partial.replace(target)
    print("Laya checkpoint SHA-256 verified.", flush=True)


if __name__ == "__main__":
    download()
