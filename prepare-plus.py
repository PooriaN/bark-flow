"""Expand the publisher's quantized decoder exactly as bark_coreml.py does.
Only needed when preparing models. The installed app does not use Python.
"""
import hashlib, json, pathlib, sys
import numpy as np

root = pathlib.Path(sys.argv[1])
z = np.load(root / 'decoder.npz', allow_pickle=False)
out = root / 'decoder-data'
out.mkdir(exist_ok=True)
manifest = {}
keys = [key.removesuffix('.q') for key in z.files if not key.endswith('.s')]
for key in keys:
    value = (z[key+'.q'].astype(np.float32) * z[key+'.s'].astype(np.float32)[:,None]) if key+'.q' in z else z[key].astype(np.float32)
    data = np.ascontiguousarray(value, dtype='<f4').tobytes()
    filename = key + '.f32'
    (out / filename).write_bytes(data)
    manifest[key] = {'file':filename, 'shape':list(value.shape), 'sha256':hashlib.sha256(data).hexdigest()}
(out / 'weights.json').write_text(json.dumps(manifest, indent=2))
print(json.dumps({key:spec['shape'] for key,spec in manifest.items()}, indent=2))
