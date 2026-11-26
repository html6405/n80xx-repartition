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
N8010_STOCK_32GB = N8000.replace('2867200s:ext4:SYSTEM:', '2867200s:ext2:SYSTEM:')
N8010_STOCK_16GB = N8010_STOCK_32GB.replace(
    '61071360s:', '30777344s:'
).replace('61063167s:55336960s', '30769151s:25042944s')
N8010 = 'BYT;\n/dev/block/mmcblk0:30777344s:sd/mmc:512:512:gpt:MMC;\n' + COMMON + '''9:1818624s:5818359s:3999736s:ext2:SYSTEM:;
10:5818360s:6843750s:1025391s:ext2:HIDDEN:;
11:6843751s:6860134s:16384s::OTA:;
12:6860135s:30777310s:23917176s:ext4:USERDATA:;
'''

# Physical N8020 geometry and case-sensitive by-name aliases from the
# read-only recovery preflight. The parted report is modeled from them.
N8020 = '''BYT;
/dev/block/mmcblk0:30777344s:sd/mmc:512:512:gpt:MMC;
1:8192s:16383s:8192s::BOTA0:;
2:16384s:24575s:8192s::BOTA1:;
3:24576s:65535s:40960s:ext4:EFS:;
4:65536s:73727s:8192s::m9kefs1:;
5:73728s:81919s:8192s::m9kefs2:;
6:81920s:90111s:8192s::m9kefs3:;
7:90112s:106495s:16384s::PARAM:;
8:106496s:122879s:16384s::BOOT:;
9:122880s:139263s:16384s::RECOVERY:;
10:139264s:319487s:180224s:fat16:RADIO:;
11:319488s:843775s:524288s:ext4:TOMBSTONES:;
12:843776s:2940927s:2097152s:ext4:CACHE:;
13:2940928s:6086655s:3145728s:ext4:SYSTEM:;
14:6086656s:7233535s:1146880s:ext4:HIDDEN:;
15:7233536s:7249919s:16384s::OTA:;
16:7249920s:30769151s:23519232s:ext4:USERDATA:;
'''
N8020_RESIZED = N8020.replace(
    '843776s:2940927s:2097152s', '843776s:1892351s:1048576s'
).replace('2940928s:6086655s:3145728s', '1892352s:6086655s:4194304s')


def select(device, table, fresh=0, vendor=1, cache=1, detail=False):
    output = ('"$PROFILE" "$STATE" "$TARGET_SYSTEM_START" "$TARGET_CACHE_KIB" "$REQUIRED_KIB"')
    if detail:
        output += (' "$CACHE_PART" "$SYSTEM_PART" "$VENDOR_PART" "$OTA_PART" "$DATA_PART"'
                   ' "$TARGET_CACHE_END" "$TARGET_CACHE_BYTES" "$backup_parts"')
    command = ('. "$1"; DEVICE=$2; TABLE=$(cat "$3"); FRESH_SYSTEM=$4; '
               'BACKUP_VENDOR=$5; BACKUP_CACHE=$6; select_profile || exit 1; '
               'printf "%s\\n" ' + output)
    with tempfile.NamedTemporaryFile(mode='w') as fixture:
        fixture.write(table)
        fixture.flush()
        return subprocess.run(
            ['sh', '-c', command, 'test', str(SCRIPT), device, fixture.name,
             str(fresh), str(vendor), str(cache)],
            text=True, capture_output=True,
        )

class Profiles(unittest.TestCase):
    def test_observed_n8000(self):
        result = select('p4noterf', N8000)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout.split()[:4], ['n8000-observed', 'original', '491520', '155648'])

    def test_observed_n8010(self):
        result = select('p4notewifi', N8010)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout.split(), ['n8010-observed-16gb', 'original', '1624056', '721916', '3671732'])

    def test_stock_n8010_original_and_resized_on_both_capacities(self):
        # Issue #1 supplies the 32 GB table; issue #2 confirms the fixed
        # stock boundaries on 16 GB devices.
        aliases = ('p4notewifi', 'p4notewifiww', 'n8010', 'GT-N8010')
        for alias in aliases:
            for original in (N8010_STOCK_16GB, N8010_STOCK_32GB):
                resized = original.replace(
                    '180224s:1818623s:1638400s', '180224s:491519s:311296s'
                ).replace('1818624s:4685823s:2867200s', '491520s:4685823s:4194304s')
                for table, state in ((original, 'original'), (resized, 'resized')):
                    with self.subTest(alias=alias, state=state, disk=original.splitlines()[1]):
                        result = select(alias, table, fresh=1, vendor=0, cache=0, detail=True)
                        self.assertEqual(result.returncode, 0, result.stderr)
                        self.assertEqual(result.stdout.splitlines(), [
                            'n8010-stock', state, '491520', '155648', '339968',
                            '8', '9', '10', '11', '12', '491519', '159383552',
                            '3:efs.img 6:recovery.img 7:modem.img 11:ota.img',
                        ])

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

    def test_n8020_original_and_resized_exact_geometry(self):
        for table, state in [(N8020, 'original'), (N8020_RESIZED, 'resized')]:
            result = select('p4notelte', table, fresh=1, vendor=0, cache=0, detail=True)
            self.assertEqual(result.returncode, 0, result.stderr)
            lines = result.stdout.splitlines()
            self.assertEqual(lines[:12], [
                'n8020-observed-16gb', state, '1892352', '524288', '425984',
                '12', '13', '14', '15', '16', '1892351', '536870912',
            ])
            self.assertEqual(lines[12].split(), [
                '3:efs.img', '4:m9kefs1.img', '5:m9kefs2.img', '6:m9kefs3.img',
                '7:param.img', '8:boot.img', '9:recovery.img', '10:modem.img', '15:ota.img',
            ])

    def test_n8020_optional_backup_sizes(self):
        self.assertEqual(select('p4notelte', N8020, fresh=0, vendor=1, cache=1).stdout.split()[-1],
                         str(425984 + (1536 + 560 + 1024) * 1024))
        self.assertEqual(select('p4notelte', N8020, fresh=1, vendor=1, cache=1).stdout.split()[-1],
                         str(425984 + (560 + 1024) * 1024))

    def test_n8020_rejects_wrong_geometry_and_lte_names(self):
        variants = [
            N8020.replace(':m9kefs1:', ':M9KEFS1:'),
            N8020.replace(':m9kefs1:', ':TEMP:').replace(':m9kefs2:', ':m9kefs1:').replace(':TEMP:', ':m9kefs2:'),
            N8020.replace('90112s:106495s', '90113s:106495s'),
            N8020.replace('2940928s:6086655s', '2940936s:6086655s'),
            N8020.replace('7249920s:30769151s:23519232s', '7249920s:30769143s:23519224s'),
            N8020.replace('30777344s:', '61071360s:'),
            N8020.replace('524288s:ext4:TOMBSTONES:', '524287s:ext4:TOMBSTONES:'),
            N8020 + '17:30769152s:30777200s:8049s::EXTRA:;\n',
        ]
        for table in variants:
            self.assertNotEqual(select('p4notelte', table).returncode, 0, table)
        self.assertNotEqual(select('p4noterf', N8020).returncode, 0)

    def test_reject_other_models_and_layouts(self):
        for device, table in [('p4notelte', N8010), ('p4noterf', N8010),
                              ('GT-N8013', N8010_STOCK_16GB),
                              ('p4notewifi', N8010_STOCK_32GB.replace('5726208s:', '5726216s:')),
                              ('p4notewifi', N8010_STOCK_32GB.replace('4685824s:5709823s:1024000s', '4685832s:5709823s:1023992s')),
                              ('p4notewifi', N8010_STOCK_32GB.replace('1818624s:4685823s:2867200s', '1624056s:4685823s:3061768s')),
                              ('p4notewifi', N8010.replace('6860135s:', '6860136s:')),
                              ('p4notewifi', N8010.replace(':OTA:', ':UNKNOWN:')),
                              ('p4notewifi', N8010 + '13:30777311s:30777312s:2s::EXTRA:;\n'),
                              ('p4notewifi', N8010.replace('114688s:', '114696s:'))]:
            self.assertNotEqual(select(device, table).returncode, 0, (device, table))

if __name__ == '__main__':
    unittest.main()
