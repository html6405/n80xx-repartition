# N80xx System 2 GiB repartitioner

One recovery ZIP, `N80xx-System-2GiB.zip`, with a shared implementation and
explicitly checked device/layout profiles. The installer accepts only known
combinations of device identity and actual partition boundaries.

Download the ZIP and its SHA-256 file from
[GitHub Releases](https://github.com/html6405/n80xx-repartition/releases).
Each version provides one common ZIP. Current releases are prereleases.

**Installation mode:** this ZIP prepares an empty 2 GiB System for a new ROM.
Existing System contents are erased. Install a suitable ROM afterwards.
EFS, Recovery, Modem, OTA and GPT backups are mandatory and verified before
partition changes. Internal Data is the preferred destination; no microSD
is required when sufficient internal space is available.

**Tested installation:** the complete two-step TWRP flow passed on a 32 GB
N8000 on 2026-11-14, starting from restored original Cache/System boundaries.
Mandatory backups, repartitioning, fresh System creation without discard,
read-only repeat installation and recovery reboot passed. Independent PC
checks confirmed both GPT copies, filesystem sizes and unchanged EFS,
Recovery, Modem and OTA. See [VALIDATION.md](VALIDATION.md).

**Unresolved device-specific I/O failure:** another 16 GB N8000 stalled with
MMC/controller errors during backups and System creation. A separate test
also stalled merely creating a directory on Data, outside the repartitioner,
even at a reduced MMC clock. Hardware versus recovery/driver cause remains
unresolved. This ZIP is not a repair for that I/O failure.

## Device support

| Device / observed layout | System target | Cache target | Boundaries preserved |
| --- | ---: | ---: | --- |
| N8000, matching layout tested on both 32 GB and 16 GB devices | 2048 MiB | 152 MiB | Partitions 1–7 and 10–12 |
| N8010, previously modified 16 GB test device | 2048 MiB | 704.99609375 MiB | Partitions 1–7 and 10–12 |

**N8000: two separate devices have been tested successfully.**

- **First device: 32 GB.** The original preserving procedure completed. The
  current two-step ZIP was also tested through TWRP from original partition
  boundaries, with critical-image checks, read-only repeat and recovery reboot.
- **Additional device: 16 GB.** The shared ZIP completed on 2026-11-08 in fresh
  System mode at the owner's explicit request. Post-install checks, a read-only
  repeat run and recovery reboot passed. EFS contents and OTA were verified
  against independent PC backups.

Both N8000 capacities use the same checked layout profile; Userdata's end is
allowed to differ. See [VALIDATION.md](VALIDATION.md) for the test details.

**N8010 is experimental.** Its observed layout and preflight were checked,
but a device run was interrupted before final verification. Inspect that
device's current state before attempting further writes.

**N8020 is unsupported and rejected.** Unknown or differently modified layouts
are also rejected. Device names alone never select arbitrary new boundaries.

Total storage capacity and the end of Userdata may vary. That does not imply
blanket support for every 16 GB variant: all fixed boundaries must match an
included profile exactly.

EFS, HIDDEN/Vendor, OTA/misc, Userdata, Boot, Recovery and bootloader partition
boundaries are preserved. Cache shrinks; System moves towards the start of the
disk and grows. Only GPT entries 8 and 9 are recreated. Mount configurations
must use partition names or block devices, not the old PARTUUIDs of these two
partitions. Supported ext filesystems must use 4096-byte blocks. ext4 without
a journal is recognized through tune2fs, even if old Parted labels it ext2.
Data must be unencrypted ext4.

## Backups and free space

Create independent PC backups first, especially EFS and personal files.
By default, the ZIP saves complete images of EFS, Recovery, Modem (RADIO) and
OTA, plus two 4 MiB GPT regions. Vendor, Cache and the old System image are
omitted because the intended use is a fresh ROM installation. Partition images are checked against the
source by size and SHA-256. Required free space is calculated from the actual
image sizes plus a 256 MiB reserve. Insufficient space causes an abort before
creating the backup directory, unmounting filesystems or changing partitions.

The installer prefers Data under `/data/media/0`. If no Android user directory
exists yet, it uses the existing `/data/media`. Otherwise it can select a
writable external SD mounted at `/external_sdcard`. The SD must be on mmcblk1;
vfat, exfat and ext4 are accepted. Individual images for these profiles remain
below 4 GiB, so FAT32 is supported. Backups are not split between devices and
existing files are not deleted. The default mandatory backups require 76 MiB; with the
256 MiB reserve, preflight requires 332 MiB free. A microSD is optional.

The selected location contains `n80xx-repartition-backup-<profile>` with mode
suffixes when applicable. Existing backup directories are never overwritten.
EFS backups are private. FAT32 has no Unix access permissions; do not publish
any device snapshots.

The backup also contains:

- `partitions-before.txt`: the original machine-readable partition table.
- `gpt-primary.bin` and `gpt-tail.bin`: original raw GPT regions.
- `layout-backup.env`: disk size, original/target boundaries and backup mode.
- `SHA256SUMS`: checksums for images and layout records.
- `progress.txt`: the last durable checkpoint, including copy/verification,
  filesystem checks, pending GPT update, System restore and completion phases.

Copy these files to a PC before attempting another layout change or formatting
Data. An internal backup does not survive formatting the Data partition.
`layout-backup.env` is data and must not be executed or sourced as shell code.

These files are **not an automatic revert function**. A 4 MiB tail region may
include Userdata on some layouts: never blindly write the whole region back.
GPT restoration must use only the actual GPT metadata sectors from the backup.
After moving System, its contents must also be restored at the original start,
or System must be reformatted there and the ROM reinstalled. Restoring only
the old GPT would otherwise leave the table and filesystem inconsistent.

### Optional preservation modes

The default creates a fresh System and omits Vendor/Cache images. Advanced
callers may set environment variables before invoking the installer:

- `N80XX_FRESH_SYSTEM=0`: back up and restore the old System image instead of
  creating an empty filesystem. This requires substantially more space.
- `N80XX_BACKUP_VENDOR=1`: additionally back up and verify the Vendor image.
- `N80XX_BACKUP_CACHE=1`: additionally back up the Cache image.

These opt-in modes exercise the large-image backup path that stalled on the
additional N8000 and are not validated on that device. In the default mode,
Cache is checked and shrunk in place without an image backup. A failure may
require reformatting Cache. Vendor is not formatted by this ZIP; the new ROM
installs its Vendor contents. EFS, Recovery, Modem, OTA and GPT backups cannot
be disabled. Space checks reflect the selected options. Different backup
modes use distinct directory names.

## Preflight and installation

The ZIP includes static ARM Parted and extracts its tools under `/tmp`.
Fresh System creation uses `mke2fs -E nodiscard` to avoid discarding the
partition before writing the new filesystem on the legacy MMC stack.
Recovery needs `/sbin/sh`, unzip, e2fsck, resize2fs, tune2fs, sha256sum,
blockdev and common BusyBox utilities. Fresh System mode also requires mke2fs.

The included static `read-range` helper saves GPT regions with a 64-bit kernel
seek. Unlike the old recovery dd, it does not read forward through the whole
eMMC for a large skip. Its source and MIT license are included.

After extracting the tools into `/tmp/n80xx-repartition`, run a read-only check:

```sh
/sbin/sh /tmp/n80xx-repartition/tools/repartition.sh --check
```

### Flashing in TWRP: two steps, one ZIP

TWRP keeps the source ZIP memory-mapped while its installer runs. If that ZIP
is on internal Data, Data cannot be unmounted safely for the partition-table
update. The installer therefore stages itself in recovery RAM first:

1. Install the downloaded ZIP normally. It copies and checksum-verifies itself
   at `/tmp/N80xx-System-2GiB.zip` and prints **STEP 1/2 COMPLETE**. This step
   changes no partitions and does not erase System.
2. Return to **Install**, navigate to `/tmp` in the file browser, and select
   `/tmp/N80xx-System-2GiB.zip`. This second installation performs the backup,
   repartitioning and fresh System creation. **Existing System is erased.**
3. After the final **Done. SYSTEM 2048 MiB** message, reboot recovery and install
   a suitable ROM. Internal Data is not formatted by this ZIP.

Do not reboot between steps 1 and 2: `/tmp` is temporary RAM storage. No microSD,
PC command or second download is required. Direct installation of a ZIP already
located in `/tmp` starts step 2 immediately. The installer never force-unmounts
Data and aborts before GPT changes if a regular unmount remains blocked.

Preflight already requires a suitable backup destination. It reports missing
space without unmounting or creating anything. Flashing the ZIP in recovery,
or running the script with `--apply`, performs the change after preflight.

For an already resized layout, filesystem sizes and consistency are checked
without repartitioning or formatting. If Cache/System are mounted, consistency
checks may fail; unmount them in recovery before repeating the check.

An interrupted change is not automatically resumed or rolled back. On failure,
keep recovery running and preserve the logs and backups. Do not blindly restore
an old GPT after moving System. A pending System restore must be performed
manually from its backup at the verified new boundaries. After success, reboot
recovery before installing a suitable ROM.

## Build and tests

```sh
python3 build_zip.py
python3 -m unittest discover -s tests -p 'test_*.py'
```

Inside the Android source tree, the builder recompiles `read-range` using the
available Android Clang r563880. A standalone checkout uses the bundled ARM
helper. To rebuild it with an ARM-capable Clang and LLD:

```sh
python3 build_zip.py --clang /path/to/clang
```

The builder accepts only explicitly allowed package files and rejects symlinks
and unexpected files. Private backups, archives and raw logs stay local and are
also excluded from Git through an explicit public-file allowlist.

Tagged releases run the tests, build the single ZIP and publish it with its
SHA-256 file as a GitHub prerelease.

## Licenses and provenance

Project scripts and the read-range helper use MIT licenses. GNU Parted has its
own GPLv3 license. The legacy Parted binary reports `1.8.8.1.179-aef3` and is the
same static executable used in the smdk4412 device builds. Its exact original
build environment and matching complete source have not yet been verified.
See [THIRD_PARTY.md](THIRD_PARTY.md) for its provenance and checksum.
