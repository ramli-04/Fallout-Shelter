"""Run the pinned OpenJev server with its supported small Laya backend on CPU."""
import json
import os
from pathlib import Path
import runpy
from urllib.parse import urlsplit

root = Path(__file__).resolve().parents[1]
config = json.loads((root / "config/openjev.json").read_text())
endpoint = urlsplit(config["endpoint"])
if endpoint.hostname not in {"127.0.0.1", "localhost", "::1"}:
    raise SystemExit("The managed OpenJev launcher requires a loopback endpoint")
os.environ["OPENJEV_BACKEND"] = config["backend"]
os.environ["OPENJEV_DEVICE"] = "cpu"
os.environ["OPENJEV_HOST"] = "127.0.0.1"
os.environ["OPENJEV_PORT"] = str(endpoint.port or 8780)
checkpoint = root / ".tools/openjev/checkpoint"
if (checkpoint / "model.safetensors").is_file():
    os.environ["OPENJEV_LAYA_MODEL"] = str(checkpoint)
os.environ.setdefault("OPENJEV_ENCODER_BATCH", "4")
os.environ.setdefault("OMP_NUM_THREADS", "4")
os.environ.setdefault("MKL_NUM_THREADS", "4")
os.environ.setdefault("HF_HOME", str(root / ".tools/openjev/models"))
os.environ.setdefault("HF_HUB_DISABLE_TELEMETRY", "1")
os.environ.setdefault("HF_HUB_DISABLE_SYMLINKS_WARNING", "1")
os.environ.setdefault("HF_HUB_DISABLE_XET", "1")
os.environ.setdefault("HF_HUB_DOWNLOAD_TIMEOUT", "90")
os.environ.setdefault("PYTHONUTF8", "1")
runpy.run_module("openjev", run_name="__main__")
