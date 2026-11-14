"""The first TWRP pass must only stage a verified copy, never run the updater."""
from pathlib import Path
import os
import subprocess
import tempfile
import unittest

UPDATER = Path(__file__).resolve().parents[1] / 'package/META-INF/com/google/android/update-binary'


class Staging(unittest.TestCase):
    def exercise(self, copy_mode='normal'):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            tools = root / 'bin'
            tools.mkdir()
            ram = root / 'ram'
            ram.mkdir()
            source = root / 'download.zip'
            source.write_bytes(b'installer fixture\0' * 123)
            staged = ram / 'installer.zip'
            work = ram / 'work'
            marker = root / 'unexpected-extraction'
            commands = {
                'readlink': '#!/bin/sh\necho /data/media/0/download.zip\n',
                'unzip': '#!/bin/sh\ntouch "$EXTRACTION_MARKER"\nexit 99\n',
            }
            if copy_mode == 'corrupt':
                commands['cp'] = '#!/bin/sh\ncat "$1" > "$2"\nprintf corrupt >> "$2"\n'
            elif copy_mode == 'fail':
                commands['cp'] = '#!/bin/sh\nexit 1\n'
            for name, text in commands.items():
                path = tools / name
                path.write_text(text)
                path.chmod(0o755)
            script = root / 'update-binary'
            script.write_text(UPDATER.read_text()
                              .replace('WORK=/tmp/n80xx-repartition', f'WORK={work}')
                              .replace('STAGED=/tmp/N80xx-System-2GiB.zip', f'STAGED={staged}'))
            env = dict(os.environ, PATH=f'{tools}:{os.environ["PATH"]}',
                       EXTRACTION_MARKER=str(marker))
            result = subprocess.run(['sh', str(script), '3', '1', str(source)],
                                    env=env, capture_output=True, text=True)
            self.assertFalse(marker.exists(), 'First pass must not extract or run the repartitioner')
            self.assertFalse(work.exists())
            if copy_mode == 'normal':
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertEqual(staged.read_bytes(), source.read_bytes())
                self.assertIn('STEP 1/2 COMPLETE', result.stdout)
                self.assertIn('No partitions have been changed.', result.stdout)
                self.assertFalse(Path(str(staged) + '.tmp').exists())
            else:
                self.assertNotEqual(result.returncode, 0)
                self.assertFalse(staged.exists())
                self.assertNotIn('STEP 1/2 COMPLETE', result.stdout)

    def test_internal_zip_only_staged(self):
        self.exercise()

    def test_corrupt_ram_copy_rejected(self):
        self.exercise('corrupt')

    def test_copy_failure_stops_first_pass(self):
        self.exercise('fail')


if __name__ == '__main__':
    unittest.main()
