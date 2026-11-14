# Validation status

Successful N8000 testing covers 32 GB and 16 GB devices. The published
v0.2.0-rc1 ZIP passed the complete two-step TWRP flow on both capacities on
2026-11-14. They share the same fixed partition-boundary profile; the end of
Userdata differs with storage capacity.

## N8000, 32 GB — 2026-11-14: actual two-step TWRP installation

- Recovery: TWRP 3.7.0_9-0; kernel 3.0.101-TWRP-gcbcdf2dc554.
- The owner completed their backup and explicitly authorized erasing System.
- Independent PC snapshots of EFS, Recovery, Modem, OTA and both GPT regions
  were size/checksum-verified. EFS files were unchanged after the user's backup.
- Only Cache/System were reset to the original observed partition boundaries
  to exercise the complete repartition path. Data was not formatted.
- Direct installation from internal storage reached the safe unmount guard.
  Diagnostics showed TWRP's memory mapping of the source ZIP on Data, preventing
  a regular unmount. GPT was unchanged by that aborted attempt.
- The updated first-pass installer copied and checksum-verified the ZIP in RAM;
  its successful staging message and unchanged partition sizes were checked.
- Installing the same ZIP from `/tmp` through TWRP completed in approximately
  33 seconds, including mandatory EFS/Recovery/Modem/OTA/GPT backups, Cache/System
  partition changes and fresh System creation without discard. No MMC errors
  were found in the captured kernel log for this complete pass.
- Every saved image/layout checksum passed; `progress.txt` reported `complete`.
- Primary and backup GPT header/entry CRCs passed, the tables agreed, the disk
  GUID was unchanged, and entries outside Cache/System were byte-identical.
- Kernel partition and filesystem sizes matched: System 2147483648 bytes;
  Cache 159383552 bytes. Filesystem consistency checks passed.
- EFS, Recovery, Modem and OTA matched the immediate PC snapshot byte-for-byte.
- A repeat TWRP installation detected the finished layout and performed only
  read-only checks, without repartitioning or formatting.
- After rebooting recovery, independent checks again passed for both GPT copies,
  filesystem sizes, Recovery, Modem and OTA. EFS differed only at five bytes in
  mount/write timestamps and its mount counter; all other bytes were identical.
- System is intentionally empty for the subsequent ROM installation.

## Additional N8000, 16 GB — earlier MMC failures and successful released-ZIP retest

- Earlier default large-image backup tests stalled near Vendor verification.
  Flush checkpoints and delayed clock gating did not resolve the fault.
- Mandatory small backups subsequently passed, but System creation with default
  discard stalled. After restarting recovery, isolated System creation without
  discard and independent critical-image/layout checks passed.
- A full ZIP retest then stalled during Modem-backup verification/checkpoint,
  before GPT changes. Avoiding Vendor images was not a general fix.
- After another recovery restart, independent checks again confirmed the
  protected GPT entries and EFS/Recovery/Modem/OTA against PC snapshots.
- A diagnostic at 25 MHz instead of the original 50 MHz stalled while creating
  a directory on Data, before any test-file payload or repartitioning.
- Those failures also occurred outside the ZIP. Their hardware versus recovery/
  driver cause remains undiagnosed.
- On 2026-11-14, the published v0.2.0-rc1 ZIP was retested on this same device:
  SHA-256 `6ba90b6e79948d802c62d225ffd349a4dc6e1880f10550616618d93734d63bf1`.
  Recovery/kernel and partition layout were unchanged; no experimental clock or
  clock-gating adjustment was applied. Fresh critical PC snapshots were checked.
- Both actual TWRP steps completed. The RAM copy was checksum-verified and left
  partition sizes unchanged; the second pass performed all mandatory backups,
  GPT changes and fresh System creation without discard in about 29 seconds.
- No MMC/controller errors were found in the captured kernel log for this run.
  All eight saved image/layout checksum entries passed and progress was complete.
- Independent pre-reboot checks verified primary/backup GPT CRCs and matching
  entries, unchanged disk GUID and entries outside Cache/System, correct kernel
  and filesystem sizes, and byte-identical EFS/Recovery/Modem/OTA against the PC.
- A repeat TWRP installation passed read-only checks without changes.
- After a recovery reboot, all independent checks passed again. EFS differed
  only at five ext4 mount/write timestamp and mount-counter bytes; all other
  bytes, including file contents, were identical. Recovery/Modem/OTA were exact.
- System is intentionally empty. This successful retest does not establish a
  general repair or diagnosis for the earlier intermittent I/O failures.

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

Seventeen tests cover original/completed layouts, variable capacity, incompatible
model/layout rejection, selected backup-space requirements and ext superblock
validation with/without a journal, invalid magic, wrong block size, oversized
filesystems and read failures, flushed/verified backup copies, rejection of
corrupt copies, and first-pass staging with corrupt-copy/copy-failure handling.
Shell scripts pass syntax validation.

The current default omits Cache/Vendor/old System images and always saves EFS,
Recovery, Modem, OTA and GPT. Backup-space tests include all selected modes.
The older 16 GB run retained Cache backup; the current 32 GB run did not.

Private snapshots, device identifiers and raw logs remain local, excluded by the
Git allowlist and the ZIP builder's exact package-file allowlist.
