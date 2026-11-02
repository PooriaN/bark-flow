"""Download only pinned publisher model files and verify their contents."""
import concurrent.futures
import hashlib
import json
import pathlib
import urllib.request
import sys
import argparse

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('folder')
parser.add_argument('--model', choices=['plus','pro'], default='pro')
args = parser.parse_args()
root = pathlib.Path(args.folder)
manifest_name = 'PlusModelManifest.json' if args.model == 'plus' else 'ModelManifest.json'
manifest = json.loads((pathlib.Path(__file__).parent / 'Resources' / manifest_name).read_text())
revision = manifest['revision']
entries = manifest["files"]

def digest(path, entry):
    data_hash = hashlib.sha256() if "lfs" in entry else hashlib.sha1()
    if "lfs" not in entry:
        data_hash.update(f"blob {entry['size']}\0".encode())
    with path.open("rb") as source:
        while block := source.read(4 * 1024 * 1024):
            data_hash.update(block)
    return data_hash.hexdigest()

def download(entry):
    name = entry["path"].removeprefix('coreml/ane/').removeprefix('coreml/')
    dest = root / name
    expected = entry.get("lfs", {}).get("oid", entry["oid"])
    if dest.exists() and dest.stat().st_size == entry["size"] and digest(dest, entry) == expected:
        return name + " already verified"
    dest.parent.mkdir(parents=True, exist_ok=True)
    temporary = dest.with_name(dest.name + ".partial")
    url = f"https://huggingface.co/{manifest['repository']}/resolve/{revision}/{entry['path']}?download=true"
    with urllib.request.urlopen(url, timeout=120) as response, temporary.open("wb") as output:
        while block := response.read(4 * 1024 * 1024):
            output.write(block)
    if temporary.stat().st_size != entry["size"] or digest(temporary, entry) != expected:
        temporary.unlink(missing_ok=True)
        raise ValueError("Integrity check failed: " + name)
    temporary.replace(dest)
    return name + " verified"

with concurrent.futures.ThreadPoolExecutor(max_workers=4) as pool:
    for result in pool.map(download, entries):
        print(result, flush=True)
print("All pinned model files verified.", flush=True)
