#!/usr/bin/env python3
"""Exercise layout selection against observed tables and incompatible variants."""
from pathlib import Path
import subprocess
import tempfile
import unittest

SCRIPT = Path(__file__).resolve().parents[1] / 'package/tools/profiles.sh'
COMMON = '''1:8192s:16383s:8192s::BOTA0:;
2:16384s:24575s:8192s::BOTA1:;
3:24576s:65535s:40960s:ext4:EFS:;
4:65536s:81919s:16384s::PARAM:;
5:81920s:98303s:16384s::BOOT:;
6:98304s:114687s:16384s::RECOVERY:;
7:114688s:180223s:65536s::RADIO:;
8:180224s:1818623s:1638400s:ext4:CACHE:;
'''
N8000 = 'BYT;\n/dev/block/mmcblk0:61071360s:sd/mmc:512:512:gpt:MMC;\n' + COMMON + '''9:1818624s:4685823s:2867200s:ext4:SYSTEM:;
10:4685824s:5709823s:1024000s:ext2:HIDDEN:;
11:5709824s:5726207s:16384s::OTA:;
12:5726208s:61063167s:55336960s:ext4:USERDATA:;
'''
N8010 = 'BYT;\n/dev/block/mmcblk0:30777344s:sd/mmc:512:512:gpt:MMC;\n' + COMMON + '''9:1818624s:5818359s:3999736s:ext2:SYSTEM:;
10:5818360s:6843750s:1025391s:ext2:HIDDEN:;
11:6843751s:6860134s:16384s::OTA:;
12:6860135s:30777310s:23917176s:ext4:USERDATA:;
'''

def select(device, table, fresh=0, vendor=1, cache=1):
    with tempfile.NamedTemporaryFile(mode='w') as fixture:
        fixture.write(table)
        fixture.flush()
        return subprocess.run(['sh', '-c', '. "$1"; DEVICE=$2; TABLE=$(cat "$3"); FRESH_SYSTEM=$4; BACKUP_VENDOR=$5; BACKUP_CACHE=$6; select_profile || exit 1; printf "%s %s %s %s %s\\n" "$PROFILE" "$STATE" "$TARGET_SYSTEM_START" "$TARGET_CACHE_KIB" "$REQUIRED_KIB"',
                               'test', str(SCRIPT), device, fixture.name, str(fresh), str(vendor), str(cache)],
                              text=True, capture_output=True)

class Profiles(unittest.TestCase):
    def test_observed_n8000(self):
        result = select('p4noterf', N8000)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout.split()[:4], ['n8000-observed', 'original', '491520', '155648'])

    def test_observed_n8010(self):
        result = select('p4notewifi', N8010)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout.split(), ['n8010-observed-16gb', 'original', '1624056', '721916', '3671732'])

    def test_n8000_capacity_not_fixed(self):
        table = N8000.replace('61071360s', '30777344s').replace('61063167s:55336960s', '30769151s:25042944s')
        self.assertEqual(select('p4noterf', table).returncode, 0)

    def test_selected_backup_sizes(self):
        for device, table in [('p4noterf', N8000), ('p4notewifi', N8010)]:
            self.assertEqual(select(device, table, fresh=1, vendor=0).stdout.split()[-1], '1159168')
            self.assertEqual(select(device, table, fresh=1, vendor=0, cache=0).stdout.split()[-1], '339968')
            self.assertEqual(select(device, table, fresh=1, vendor=1).stdout.split()[-1],
                             '1671168' if device=='p4noterf' else '1671864')

    def test_finished_layouts(self):
        for device, table, start, end, cache_sectors, old_system in [
            ('p4noterf', N8000, 491520, 491519, 311296, '4685823s:2867200s'),
            ('p4notewifi', N8010, 1624056, 1624055, 1443832, '5818359s:3999736s')]:
            table = table.replace('180224s:1818623s:1638400s', f'180224s:{end}s:{cache_sectors}s')
            table = table.replace(f'1818624s:{old_system}', f'{start}s:{old_system.split(":")[0]}:4194304s')
            result = select(device, table)
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertEqual(result.stdout.split()[1], 'resized')

    def test_reject_other_models_and_layouts(self):
        for device, table in [('p4notelte', N8010), ('p4notewifi', N8000), ('p4noterf', N8010),
                              ('p4notewifi', N8010.replace('6860135s:', '6860136s:')),
                              ('p4notewifi', N8010.replace(':OTA:', ':UNKNOWN:')),
                              ('p4notewifi', N8010 + '13:30777311s:30777312s:2s::EXTRA:;\n'),
                              ('p4notewifi', N8010.replace('114688s:', '114696s:'))]:
            self.assertNotEqual(select(device, table).returncode, 0, (device, table))

if __name__ == '__main__':
    unittest.main()
