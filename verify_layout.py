#!/usr/bin/env python3
"""Read-only check of current layout and EFS/OTA against a critical PC snapshot."""
import argparse
import hashlib
import json
from pathlib import Path
import re
import struct
import subprocess
import zlib

parser=argparse.ArgumentParser()
parser.add_argument('--snapshot',required=True,type=Path)
parser.add_argument('--phase',choices=['before-reboot','after-reboot'],required=True)
args=parser.parse_args()
root=args.snapshot.resolve()
metadata=json.loads((root/'metadata.json').read_text())
adb=['adb','-s',metadata['serial']]
def shell(command):
    return subprocess.check_output(adb+['shell',command]).decode().strip()
assert shell('getprop ro.product.device')==metadata['device'], 'Wrong device'
def read(device,start,count):
    data=subprocess.check_output(adb+['exec-out',f'/tmp/n80xx-repartition/tools/read-range {device} {start} {count} 2>/dev/null'])
    assert len(data)==count*512
    return data
def parse(data):
    h=bytearray(data[512:1024]); assert h[:8]==b'EFI PART'
    length,crc=struct.unpack_from('<II',h,12); h[16:20]=bytes(4)
    assert zlib.crc32(h[:length])==crc
    lba,count,size,crc=struct.unpack_from('<QIII',h,72)
    block=data[lba*512:lba*512+count*size]
    assert len(block)==count*size and zlib.crc32(block)==crc
    return h[56:72],[block[i*size:(i+1)*size] for i in range(count)]
old_guid,old=parse((root/'gpt-primary.bin').read_bytes())
current=read('/dev/block/mmcblk0',0,8192)
guid,new=parse(current)
assert guid==old_guid and len(new)==len(old)
for i,(a,b) in enumerate(zip(old,new)):
    if i not in (7,8): assert a==b,f'Unexpected change to GPT entry {i+1}'
system_end=struct.unpack_from('<Q',old[8],40)[0]
start=system_end+1-4194304
cache_start=struct.unpack_from('<Q',old[7],32)[0]
assert struct.unpack_from('<QQ',new[7],32)==(cache_start,start-1)
assert struct.unpack_from('<QQ',new[8],32)==(start,system_end)
print('GPT: CRCs valid; disk GUID unchanged; only CACHE/SYSTEM entries changed.',flush=True)
def block_for_name(name):
    matches=[i+1 for i,entry in enumerate(new) if entry[56:128].decode('utf-16le').rstrip('\0')==name]
    assert len(matches)==1, f'Missing or ambiguous GPT partition name: {name}'
    return f'/dev/block/mmcblk0p{matches[0]}'
# Old recovery loses by-name links after BLKRRPART; raw nodes remain valid.
efs=read(block_for_name('EFS'),0,metadata['files']['efs.img']['bytes']//512)
original=(root/'efs.img').read_bytes()
assert len(efs)==len(original)
differences=[i for i,(a,b) in enumerate(zip(original,efs)) if a!=b]
assert set(differences)<=set(range(1068,1078)),f'Unexpected EFS byte differences: {differences[:30]}'
print('EFS: identical contents; mount metadata offsets changed:',differences,flush=True)
ota=read(block_for_name('OTA'),0,metadata['files']['ota.img']['bytes']//512)
assert hashlib.sha256(ota).hexdigest()==metadata['files']['ota.img']['sha256']
print('OTA: identical to original PC backup.',flush=True)
for number,expected_start,sectors in [(8,cache_start,start-cache_start),(9,start,4194304)]:
    assert int(shell(f'cat /sys/class/block/mmcblk0p{number}/start'))==expected_start
    assert int(shell(f'cat /sys/class/block/mmcblk0p{number}/size'))==sectors
    info=shell(f'tune2fs -l /dev/block/mmcblk0p{number}')
    blocks=int(re.search(r'^Block count:\s+(\d+)',info,re.M)[1])
    size=int(re.search(r'^Block size:\s+(\d+)',info,re.M)[1])
    assert blocks*size==sectors*512
print('Kernel and filesystem sizes verified: SYSTEM 2 GiB; CACHE', (start-cache_start)//2,'KiB.',flush=True)
report={'phase':args.phase,'system_bytes':2147483648,'cache_bytes':(start-cache_start)*512,
        'gpt_verified':True,'efs_changed_mount_metadata_offsets':differences,'ota_identical':True}
(root/f'verification-{args.phase}.json').write_text(json.dumps(report,indent=2)+'\n')
