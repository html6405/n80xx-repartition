#!/usr/bin/env python3
"""Regression: inspect ext superblocks instead of old parted type labels."""
import os
from pathlib import Path
import subprocess
import unittest

text=(Path(__file__).resolve().parents[1]/'package/tools/repartition.sh').read_text()
FUNCTION=text[text.index('check_ext() {'):text.index('\ncheck_size() {')]
BASE='Filesystem magic number: 0xEF53\nFilesystem features: extent sparse_super\nBlock count: 358400\nBlock size: 4096\n'
def check(info,failed=False):
    env=os.environ.copy()
    env.update(FS_INFO=info,FS_FAILED=str(int(failed)))
    script='die() { exit 1; }; tune2fs() { [ "$FS_FAILED" = 0 ] || return 1; printf "%s" "$FS_INFO"; };\n'+FUNCTION+'\ncheck_ext /fake 1468006400'
    return subprocess.run(['sh','-c',script],env=env,capture_output=True).returncode
class Filesystems(unittest.TestCase):
    def test_without_journal(self): self.assertEqual(check(BASE),0)
    def test_with_journal(self): self.assertEqual(check(BASE.replace('extent','has_journal extent')),0)
    def test_bad_magic(self): self.assertNotEqual(check(BASE.replace('0xEF53','0x0000')),0)
    def test_oversized(self): self.assertNotEqual(check(BASE.replace('358400','999999')),0)
    def test_wrong_block_size(self): self.assertNotEqual(check(BASE.replace('4096','8192')),0)
    def test_read_failure(self): self.assertNotEqual(check(BASE,True),0)
if __name__=='__main__': unittest.main()
