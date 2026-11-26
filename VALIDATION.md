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

## N8000, 16 GB — 2026-11-22: same-session ROM installation

- This was a previously repartitioned N8000 running LineageOS 21. The original
  800 MiB Cache and 1400 MiB System boundaries were recreated, and its exact
  installed System contents were restored to the original-size partition.
  TWRP 3.7.0_9-0 was then restarted before installing the candidate.
- Both ZIP stages passed. Independent checks confirmed both GPT copies, the
  PIT, 2 GiB System, 152 MiB ext4 Cache, the protected GPT entries and critical
  partition images. All eight installer backup checksums passed.
- The candidate restored all 12 missing by-name links and the internal
  `/sdcard` mount. LineageOS 21 was installed from `/sdcard` in the same TWRP
  session. The original Magisk-patched BOOT was then restored byte-for-byte,
  and the same LineageOS build booted in Enforcing mode.
- This N8000 had no `/data/system/storage.xml`. This confirms that the
  same-session flow works on the tested N8000 profile. It does not reproduce
  the ABX parser hang observed on the N8010.
- N8000 artifact SHA-256:
  `5f345f90ccbcdb3ebd64b6e45c05a75fe0576cd3d659b37f955b40df5d2cb9cc`.

## N8010, reported stock boundaries — 2026-11-26

- [Issue #1](https://github.com/html6405/n80xx-repartition/issues/1) supplied a
  32 GB GPT table and reported successful RAM staging only.
- [Issue #2](https://github.com/html6405/n80xx-repartition/issues/2) reported the
  same fixed boundaries on four stock 16 GB units, successful repartitioning
  with a manually adapted RC2 profile, and a LineageOS 23.2 Enforcing boot
  with 152 MiB Cache. These are community results.
- The new stock profile passes host checks for the original and resized GPT
  on both capacities. It produces 2 GiB System and 152 MiB Cache without
  moving HIDDEN, OTA or Userdata. The previously modified profile and its
  larger Cache are retained. The new ZIP itself has no physical stock N8010
  install or OTA cycle on record.

## N8010, previously modified 16 GB — 2026-11-22

- The published v0.2.0-rc1 ZIP completed both TWRP stages on the observed
  16 GB layout, starting with an 800 MiB ext4 Cache. The installer produced a
  2 GiB System and a 739241984-byte Cache. All installer backup checksums,
  independent GPT and critical partition checks, and the read-only repeat passed
  before reboot.
- TWRP hung at its splash screen after reboot. During troubleshooting, it
  logged repeated errors parsing Android's binary `/data/system/storage.xml`
  as text XML, even with a freshly formatted ext4 Cache mounted. Temporarily
  moving that file allowed TWRP to start. The byte-identical original was put
  back before Android boot.
- After separate Download-mode Cache repair attempts, System needed a fresh
  ext4 filesystem and RADIO differed from its original image. The cause of
  those changes was not established. System was recreated and RADIO restored
  from the verified PC backup. Both GPT copies, the PIT, filesystem sizes,
  EFS contents, OTA, BOOT, RADIO and the installed recovery were checked.
  Userdata and the existing TWRP backup were preserved. The published
  LineageOS 23.2 ROM was reinstalled and completed boot with SELinux enforcing,
  using the 2 GiB System and an ext4 Cache.
- A controlled second run used the same published ZIP. Checks immediately
  before and after the recovery reboot passed for both GPT copies, the PIT,
  the full ext4 Cache and 2 GiB ext4 System, EFS, RADIO, OTA, BOOT and the
  installed TWRP. No partition repair or Download-mode flash was needed.
  The published LineageOS 23.2 ROM was restored and completed boot in
  Enforcing mode again.
- The second run isolated the splash hang. With LineageOS installed, TWRP
  skipped parsing Android's binary storage metadata and reached its main menu.
  With the fresh, empty System, TWRP tried to parse the same binary format as
  text and hung. Temporarily moving `/data/system/storage.xml` and restarting
  TWRP let the test continue. The original file was restored before Android
  boot. Users of this TWRP version should plan for this manual recovery step.
- Both installer runs covered the same device and exact layout.

### Same-session workaround candidate

- A subsequent candidate restored all 12 missing partition device links and
  the internal-storage bind mount after updating the GPT on this N8010 with
  TWRP 3.7.0_9-0. Independent GPT, filesystem and critical partition checks
  passed, as did all eight installer backup checksums.
- The published LOS23.2 ROM was installed from internal storage in the same
  TWRP session. Android booted in Enforcing mode. The original binary
  `storage.xml` was byte-identical throughout the installer and ROM flash.
- The initial candidate attempt also exposed a separate microSD read failure
  before the installer had made any partition changes. The updated backup
  selection skips the microSD probe when internal storage has enough room.
- N8010 artifact SHA-256:
  `b79d4b74074949e50f542779c65fa62fbfc6c39ea1252946dd5ad5f7598ebf9d`.

## N8020, exact observed 16 GB layout — 2026-11-22

- Physical TWRP 3.7.0_9-0, 512-byte sectors, 30777344 sectors total. The two
  ZIP stages completed from the original 1024 MiB Cache and 1536 MiB System.
  Independently checked both GPT copies, all 16 kernel mappings, the PIT,
  protected GPT entries, and the 512 MiB ext4 Cache and 2 GiB ext4 System.
- All 13 installer backup checksums passed. The LTE EFS images, BOOT, Recovery,
  RADIO and OTA matched the independent checks. EFS and PARAM matched the
  snapshots taken before the GPT change, after the recovery restart.
- The installer verified all 16 by-name links and restored the internal
  storage bind mount in the same TWRP session. This device had no
  `storage.xml`; no ROM was flashed as part of this test.
- After the test, the original GPT and both affected partition images were
  restored from verified PC backups. Both GPT copies, the PIT, the complete
  Cache and System images, and the protected partitions passed the final
  checks. The device was returned in the original layout.
- Hardware test ZIP SHA-256:
  `2318e1d08b53716c21df4affa7b74008a17f2d0976a0a8ad880cec6a1ac15275`.
  The release ZIP uses identical installer files and updated bundled
  documentation.

## Other profiles

- N8000, 32 GB: the original preserving implementation completed and was checked
  on a real device, including EFS, Vendor and OTA verification and recovery reboot.
- N8020 layouts other than the exact observed 16 GB layout are rejected.

## Automated checks

`python3 -m unittest discover -s tests -p 'test_*.py'`

Twenty-two tests cover original/completed layouts, variable capacity, incompatible
model/layout rejection, selected backup-space requirements and ext superblock
validation with/without a journal, invalid magic, wrong block size, oversized
filesystems and read failures, flushed/verified backup copies, rejection of
corrupt copies, internal backup selection without an unnecessary microSD probe,
N8020 LTE partition order and backup budgets, and first-pass staging with
corrupt-copy/copy-failure handling.
Shell scripts pass syntax validation.

The current default omits Cache/Vendor/old System images and always saves EFS,
Recovery, Modem, OTA and GPT. Backup-space tests include all selected modes.
The older 16 GB run retained Cache backup; the current 32 GB run did not.

Private snapshots, device identifiers and raw logs remain local, excluded by the
Git allowlist and the ZIP builder's exact package-file allowlist.
