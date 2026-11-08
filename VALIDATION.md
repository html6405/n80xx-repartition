# Validation status

## N8000, 16 GB — 2026-11-08

- Original CACHE/SYSTEM/HIDDEN/OTA boundaries matched the N8000 profile.
- ext4 without a journal, reported as ext2 by old Parted, passed superblock checks.
- A fresh Data partition with `/data/media` but no user-0 directory was supported.
- Independent PC backups of EFS, OTA and both GPT regions were checksum-verified.
- The owner explicitly requested no System or Vendor image backup on this empty
  test device. The initial preserving-backup run was stopped before GPT changes.
- The shared ZIP then completed with fresh System and no Vendor image backup.
  EFS, OTA, Cache and GPT were backed up; layout metadata and checksums were saved.
- SYSTEM partition and new ext4 filesystem: exactly 2147483648 bytes.
- CACHE partition and filesystem: exactly 159383552 bytes.
- Post-install e2fsck checks passed. Repeating the final ZIP detected the completed
  layout and passed read-only checks without repartitioning or formatting.
- Independent checks confirmed valid GPT header/entry CRCs, unchanged disk GUID
  and byte-identical entries outside CACHE/SYSTEM. EFS and OTA matched the PC
  backups byte-for-byte before recovery reboot.
- Recovery reboot completed. Partition sizes and filesystems remained correct;
  the old recovery's by-name links returned. Independent post-reboot verification
  again confirmed the unchanged GPT entries outside CACHE/SYSTEM and identical
  OTA. EFS differed only at five bytes in its ext4 mount/write timestamps and
  mount counter; every other byte, including all EFS file contents, was identical.
- No ROM was installed; fresh System is intentionally empty.

## Other profiles

- N8000, 32 GB: the original preserving implementation completed and was checked
  on a real device, including EFS, Vendor and OTA verification and recovery reboot.
- N8010, observed modified 16-GB layout: layout inspection, read-only preflight
  and a host GPT simulation passed. A device run was interrupted; final state is
  not yet verified. Treat this profile as experimental.
- N8020: unsupported and explicitly rejected until its real layout is inspected.

## Automated checks

`python3 -m unittest discover -s tests -p 'test_*.py'`

Twelve tests cover original/completed layouts, variable capacity, incompatible
model/layout rejection, selected backup-space requirements and ext superblock
validation with/without a journal, invalid magic, wrong block size, oversized
filesystems and read failures. Shell scripts pass syntax validation.

Skipping Cache image backup is supported as an explicit option. The first full
device run above retained Cache backup; the no-Cache space calculation is tested.

Private snapshots, device identifiers and raw logs remain local, excluded by the
Git allowlist and the ZIP builder's exact package-file allowlist.
