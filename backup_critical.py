#!/usr/bin/env python3
"""Read-only PC backup. Requires the common ZIP's tools extracted under /tmp."""
import argparse
from datetime import datetime, timezone
import hashlib
import json
from pathlib import Path
import re
import shlex
import subprocess

parser=argparse.ArgumentParser()
parser.add_argument('--serial', required=True)
parser.add_argument('--expect-device', required=True)
args=parser.parse_args()
adb=['adb','-s',args.serial]
def shell(command):
    return subprocess.check_output(adb+['shell', command]).decode().strip()
device=shell('getprop ro.product.device')
assert device==args.expect_device, 'Wrong model/device'
assert re.fullmatch(r'[A-Za-z0-9_.-]+',device) and re.fullmatch(r'[A-Za-z0-9_.-]+',args.serial)
helper='/tmp/n80xx-repartition/tools/read-range'
parted='/tmp/n80xx-repartition/tools/parted'
efs='/dev/block/platform/dw_mmc/by-name/EFS'
ota='/dev/block/platform/dw_mmc/by-name/OTA'
efs_block=shell('readlink -f '+shlex.quote(efs))
mounts=shell('cat /proc/mounts')
for row in mounts.splitlines():
    source, mountpoint=row.split()[:2]
    assert mountpoint!='/efs', 'Unmount EFS before taking a consistent backup'
    if source.startswith('/dev/block/'):
        assert shell('readlink -f '+shlex.quote(source))!=efs_block, 'EFS is mounted'
disk='/dev/block/mmcblk0'
assert shell('blockdev --getss '+disk)=='512', 'Unexpected sector size'
sectors=int(shell('blockdev --getsz '+disk))
assert sectors>16384
backups=Path(__file__).resolve().parent/'backups'
backups.mkdir(exist_ok=True)
backups.chmod(0o700)
stamp=datetime.now(timezone.utc).strftime('%Y%m%dT%H%M%S.%fZ')
root=backups/f'{device}-{args.serial}'/stamp
root.mkdir(parents=True,mode=0o700)
root.parent.chmod(0o700)
metadata={'device':device,'model':shell('getprop ro.product.model'),
          'serial':args.serial,'sectors':sectors,'snapshot_utc':stamp,'files':{}}
items=[('efs.img',efs,0,int(shell('blockdev --getsz '+shlex.quote(efs)))),
       ('recovery.img','/dev/block/mmcblk0p6',0,int(shell('blockdev --getsz /dev/block/mmcblk0p6'))),
       ('modem.img','/dev/block/mmcblk0p7',0,int(shell('blockdev --getsz /dev/block/mmcblk0p7'))),
       ('ota.img',ota,0,int(shell('blockdev --getsz '+shlex.quote(ota)))),
       ('gpt-primary.bin',disk,0,8192),('gpt-tail.bin',disk,sectors-8192,8192)]
for name,source,start,count in items:
    command=shlex.join([helper,source,str(start),str(count)])
    data=subprocess.check_output(adb+['exec-out',command+' 2>/dev/null'])
    assert len(data)==count*512, f'{name}: invalid length'
    digest=hashlib.sha256(data).hexdigest()
    assert shell(command+' | sha256sum').split()[0]==digest, f'{name}: checksum mismatch'
    path=root/name
    with path.open('xb') as output:
        path.chmod(0o600)
        output.write(data)
    metadata['files'][name]={'bytes':len(data),'sha256':digest}
    print(name,'verified',digest,flush=True)
(root/'partitions.txt').write_text(shell(shlex.join([parted,'-m','-s',disk,'unit','s','print']))+'\n')
(root/'metadata.json').write_text(json.dumps(metadata,indent=2)+'\n')
(root/'SHA256SUMS').write_text(''.join(f"{info['sha256']}  {name}\n" for name,info in metadata['files'].items()))
print('Snapshot:',root,flush=True)
