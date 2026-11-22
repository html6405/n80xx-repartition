#!/usr/bin/env python3
"""Backup regression: flush before verification, reject corrupt saved images."""
import hashlib
import os
from pathlib import Path
import subprocess
import tempfile
import unittest

TEXT=(Path(__file__).resolve().parents[1]/'package/tools/repartition.sh').read_text()
FUNCTIONS=TEXT[TEXT.index('checkpoint() {'):TEXT.index('\nis_mounted()')]
class BackupIO(unittest.TestCase):
    def exercise(self,corrupt=False):
        with tempfile.TemporaryDirectory() as directory:
            root=Path(directory)
            source=root/'source';source.write_bytes(bytes(range(256))*16)
            backup=root/'backup';backup.mkdir()
            env=os.environ.copy()
            env.update(BACKUP=str(backup),PROFILE='test',TRACE=str(root/'trace'),
                       SOURCE=str(source),CORRUPT=str(int(corrupt)))
            setup='''
die() { exit 1; }
say() { :; }
sync() { echo sync >>"$TRACE"; }
blockdev() { echo 8; }
dd() {
    for arg in "$@"; do
        case "$arg" in if=*) input=${arg#if=};; of=*) output=${arg#of=};; esac
    done
    cp "$input" "$output"
    if [ "$CORRUPT" = 1 ]; then printf X | /bin/dd of="$output" bs=1 conv=notrunc 2>/dev/null; fi
    echo copy >>"$TRACE"
}
hash() {
    echo "hash:$1" >>"$TRACE"
    result=$(sha256sum "$1") || exit 1
    printf '%s\\n' "${result%% *}"
}
'''
            result=subprocess.run(['sh','-eu','-c',setup+FUNCTIONS+'\nsave "$SOURCE" sample.img'],
                                  env=env,capture_output=True,text=True)
            trace=(root/'trace').read_text().splitlines()
            copy=trace.index('copy')
            first_hash=next(i for i,item in enumerate(trace) if item.startswith('hash:'))
            self.assertIn('sync',trace[copy+1:first_hash])
            if corrupt:
                self.assertNotEqual(result.returncode,0)
                self.assertFalse((backup/'SHA256SUMS').exists())
                self.assertNotIn('PHASE=backup-verified:sample.img',(backup/'progress.txt').read_text())
            else:
                self.assertEqual(result.returncode,0,result.stderr)
                self.assertEqual((backup/'sample.img').read_bytes(),source.read_bytes())
                self.assertIn(hashlib.sha256(source.read_bytes()).hexdigest(),(backup/'SHA256SUMS').read_text())
                self.assertIn('PHASE=backup-verified:sample.img',(backup/'progress.txt').read_text())
    def test_flush_and_durable_success(self): self.exercise()
    def test_corrupt_copy_rejected(self): self.exercise(True)


class BackupDestination(unittest.TestCase):
    def test_does_not_probe_sd_when_internal_storage_has_enough_space(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            data = root / 'data'
            (data / 'media/0').mkdir(parents=True)
            sd = root / 'external_sdcard'
            sd.mkdir()
            mounts = root / 'mounts'
            mounts.write_text(
                f'/dev/block/mmcblk0p12 {data} ext4 rw 0 0\n'
                f'/dev/block/mmcblk1p1 {sd} vfat rw 0 0\n'
            )
            choose = TEXT.split('choose_backup() {', 1)[1].split('\n}\n', 1)[0]
            choose = ('choose_backup() {' + choose + '\n}\n').replace('/data', str(data))
            choose = choose.replace('/external_sdcard', str(sd)).replace('/proc/mounts', str(mounts))
            setup = '''
say() { :; }
die() { echo "$*" >&2; exit 1; }
readlink() {
    case "$2" in /dev/block/mmcblk*) printf '%s\n' "$2";; *) command readlink "$@";; esac
}
free_kib() {
    [ "$1" = "$TEST_DATA" ] || { echo 'Unexpected microSD probe' >&2; return 1; }
    echo 400000
}
'''
            result = subprocess.run(
                ['sh', '-eu', '-c', setup + choose + 'choose_backup\n[ "$BACKUP" = "$TEST_DATA/media/0/n80xx-repartition-backup-test" ]'],
                env=dict(os.environ, TEST_DATA=str(data), DATA_DEVICE='/dev/block/mmcblk0p12',
                         BACKUP_TAG='test', REQUIRED_KIB='339968'),
                capture_output=True, text=True,
            )
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertNotIn('microSD probe', result.stderr)


if __name__=='__main__': unittest.main()
