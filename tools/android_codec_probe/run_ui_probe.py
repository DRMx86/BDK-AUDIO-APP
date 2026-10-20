"""Finite semantic UI QA on the identity-checked project Redmagic only."""
import argparse
import json
import os
from pathlib import Path
import re
import shlex
import subprocess

parser = argparse.ArgumentParser()
parser.add_argument("mode", choices=["dump", "click", "scrollForward", "scrollBackward"])
parser.add_argument("name")
parser.add_argument("--target")
parser.add_argument("--prefix", action="store_true")
args = parser.parse_args()
assert re.fullmatch(r"[A-Za-z0-9_-]+", args.name)
if args.mode == "click" and not args.target:
    parser.error("click requires an observed --target label")
root = Path(__file__).resolve().parents[2]
out = root / "artifacts/android-ship-20261020"
out.mkdir(parents=True, exist_ok=True)
receipt = out / (args.name + ".ui.json")
raw_path = out / (args.name + ".ui.txt")
assert not receipt.exists() and not raw_path.exists(), "Preserve prior evidence"
adb = [str(Path(os.environ["LOCALAPPDATA"]) / "Android/Sdk/platform-tools/adb.exe"), "-s", "9125299103B7"]

def call(*items):
    return subprocess.check_output(adb + list(items), timeout=40)

assert call("shell", "getprop", "ro.product.manufacturer").strip().lower() == b"nubia"
assert call("shell", "getprop", "ro.product.model").strip() == b"NX809J"
assert call("shell", "getprop", "ro.serialno").strip() == b"9125299103B7"
command = ["am", "instrument", "-w", "-r", "-e", "mode", args.mode]
if args.target:
    command += ["-e", "target", args.target, "-e", "match", "prefix" if args.prefix else "exact"]
command += ["com.bdkaudio.codecprobe/.UiProbe"]
raw = call("shell", shlex.join(command))
raw_path.write_bytes(raw)
row = next((line for line in raw.decode().splitlines() if line.startswith("INSTRUMENTATION_RESULT: ui_probe=")), None)
assert row is not None, raw.decode()
result = json.loads(row.split("=", 1)[1])
receipt.write_text(json.dumps(result, indent=2), encoding="utf-8")
shown = {
    "mode": result.get("mode"),
    "action_attempted": result.get("action_attempted"),
    "action_result": result.get("action_result"),
    "error": result.get("ui_probe_error"),
}
if args.mode == "dump":
    shown["nodes"] = [
        {key: node.get(key) for key in ["description", "text", "clickable", "scrollable", "visible", "bounds"]}
        for node in result.get("nodes", []) if node.get("description") or node.get("text")
    ]
else:
    shown["target"] = result.get("target_node")
print(json.dumps(shown, ensure_ascii=True, indent=2))
if result.get("ui_probe_error"):
    raise SystemExit(1)
if args.mode != "dump" and not result.get("action_result"):
    raise SystemExit(1)
