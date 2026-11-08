# N80xx System 2 GiB repartitioner

One recovery ZIP, `N80xx-System-2GiB.zip`, with a shared implementation and
explicitly checked device/layout profiles. The installer accepts only known
combinations of device identity and actual partition boundaries.

Download the ZIP and its SHA-256 file from
[GitHub Releases](https://github.com/html6405/n80xx-repartition/releases).
Each version provides one common ZIP. Current releases are prereleases.

## Device support

| Device / observed layout | System target | Cache target | Boundaries preserved |
| --- | ---: | ---: | --- |
| N8000, matching layout tested on both 32 GB and 16 GB devices | 2048 MiB | 152 MiB | Partitions 1–7 and 10–12 |
| N8010, previously modified 16 GB test device | 2048 MiB | 704.99609375 MiB | Partitions 1–7 and 10–12 |

**N8000: two separate devices have been tested successfully.**

- **First device: 32 GB.** The original preserving procedure completed and was
  verified, including recovery reboot and preservation of EFS, Vendor and OTA.
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
By default, the ZIP also saves complete images of EFS, Vendor, OTA, Cache and
System, plus two 4 MiB GPT regions. Partition images are checked against the
source by size and SHA-256. Required free space is calculated from the actual
image sizes plus a 256 MiB reserve. Insufficient space causes an abort before
creating the backup directory, unmounting filesystems or changing partitions.

The installer prefers Data under `/data/media/0`. If no Android user directory
exists yet, it uses the existing `/data/media`. Otherwise it can select a
writable external SD mounted at `/external_sdcard`. The SD must be on mmcblk1;
vfat, exfat and ext4 are accepted. Individual images for these profiles remain
below 4 GiB, so FAT32 is supported. Backups are not split between devices and
existing files are not deleted. Allow at least 4 GiB free on SD for the observed
N8010 with all default image backups enabled.

The selected location contains `n80xx-repartition-backup-<profile>` with mode
suffixes when applicable. Existing backup directories are never overwritten.
EFS backups are private. FAT32 has no Unix access permissions; do not publish
any device snapshots.

The backup also contains:

- `partitions-before.txt`: the original machine-readable partition table.
- `gpt-primary.bin` and `gpt-tail.bin`: original raw GPT regions.
- `layout-backup.env`: disk size, original/target boundaries and backup mode.
- `SHA256SUMS`: checksums for images and layout records.

Copy these files to a PC before attempting another layout change.
`layout-backup.env` is data and must not be executed or sourced as shell code.

These files are **not an automatic revert function**. A 4 MiB tail region may
include Userdata on some layouts: never blindly write the whole region back.
GPT restoration must use only the actual GPT metadata sectors from the backup.
After moving System, its contents must also be restored at the original start,
or System must be reformatted there and the ROM reinstalled. Restoring only
the old GPT would otherwise leave the table and filesystem inconsistent.

### Explicit options for empty test devices

The default preserves System and backs up Vendor and Cache. Advanced callers
can explicitly set the following environment variables before invoking the
installer:

- `N80XX_FRESH_SYSTEM=1`: skip the System image backup and create an empty 2 GiB
  ext4 System filesystem after repartitioning. **Existing System contents are
  erased. Install a suitable ROM afterwards.**
- `N80XX_BACKUP_VENDOR=0`: omit the Vendor image backup; HIDDEN boundaries remain
  protected.
- `N80XX_BACKUP_CACHE=0`: omit the Cache image backup. Cache is still checked
  and shrunk in place. A failure without a Cache image may require reformatting.

EFS, OTA and GPT are always backed up. Space checks reflect the chosen options.
Without these explicit variables, the preserving defaults remain enabled.
Different backup modes use distinct directory names.

## Preflight and installation

The ZIP includes static ARM Parted and extracts its tools under `/tmp`.
Recovery needs `/sbin/sh`, unzip, e2fsck, resize2fs, tune2fs, sha256sum,
blockdev and common BusyBox utilities. Fresh System mode also requires mke2fs.

The included static `read-range` helper saves GPT regions with a 64-bit kernel
seek. Unlike the old recovery dd, it does not read forward through the whole
eMMC for a large skip. Its source and MIT license are included.

After extracting the tools into `/tmp/n80xx-repartition`, run a read-only check:

```sh
/sbin/sh /tmp/n80xx-repartition/tools/repartition.sh --check
```

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
