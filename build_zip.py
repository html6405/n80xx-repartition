#!/usr/bin/env python3
import hashlib
import argparse
from pathlib import Path
import subprocess
import struct
from zipfile import ZipFile, ZipInfo, ZIP_DEFLATED

root = Path(__file__).resolve().parent
parser = argparse.ArgumentParser()
parser.add_argument('--clang', help='ARM-capable clang for rebuilding read-range')
args = parser.parse_args()
clang = root.parent / 'prebuilts/clang/host/linux-x86/clang-r563880/bin/clang'
if args.clang or clang.is_file():
    subprocess.run([args.clang or str(clang), '--target=armv7a-linux-gnueabi', '-marm', '-mfloat-abi=soft',
                '-O2', '-ffreestanding', '-fno-builtin', '-fno-stack-protector',
                '-nostdlib', '-static', '-fuse-ld=lld', '-Wl,--build-id=none', '-Wl,-e,_start',
                '-o', str(root/'package/tools/read-range'), str(root/'package/tools/read-range.c')], check=True)
for binary in ['parted', 'read-range']:
    data = (root/'package/tools'/binary).read_bytes()
    assert data[:6] == b'\x7fELF\x01\x01' and struct.unpack_from('<HH', data, 16) == (2, 40), binary
allowed = {'README.md', 'LICENSE', 'META-INF/com/google/android/update-binary',
           'tools/parted', 'tools/read-range', 'tools/read-range.c',
           'tools/COPYING.parted', 'tools/LICENSE.read-range',
           'tools/profiles.sh', 'tools/repartition.sh'}
(root/'package/LICENSE').write_bytes((root/'LICENSE').read_bytes())
actual = {p.relative_to(root/'package').as_posix() for p in (root/'package').rglob('*') if p.is_file()}
assert actual == allowed, f'Unexpected or missing package files: {actual ^ allowed}'
assert all(not (root/'package'/name).is_symlink() for name in allowed)
(root/'package/README.md').write_bytes((root/'README.md').read_bytes())
output = root / 'N80xx-System-2GiB.zip'
with ZipFile(output, 'w', ZIP_DEFLATED) as archive:
    for path in sorted((root / 'package').rglob('*')):
        if not path.is_file():
            continue
        name = path.relative_to(root / 'package').as_posix()
        info = ZipInfo(name, (2026, 10, 29, 0, 0, 0))
        info.compress_type = ZIP_DEFLATED
        info.external_attr = (0o100755 if name.endswith(('parted', 'read-range', '.sh', 'update-binary')) else 0o100644) << 16
        archive.writestr(info, path.read_bytes())
with ZipFile(output) as archive:
    assert archive.testzip() is None
digest = hashlib.sha256(output.read_bytes()).hexdigest()
output.with_suffix('.zip.sha256').write_text(f'{digest}  {output.name}\n')
print(output)
print(digest)
