Fresh-ROM installer with a verified two-step TWRP flow.

**Existing System contents are erased. Install a compatible ROM afterwards.**

1. Install the downloaded ZIP normally. Step 1 copies and checksum-verifies it
   at `/tmp/N80xx-System-2GiB.zip`, without changing partitions.
2. Return to Install, browse to `/tmp`, and install that same ZIP from RAM.
   Do not reboot between the two steps. After completion, reboot recovery
   before installing the ROM.

TWRP memory-maps its source ZIP. Running the repartitioner from RAM lets it
unmount internal Data safely. No microSD or PC command is required.

- Mandatory, size/checksum-verified backups: EFS, Recovery, Modem (RADIO), OTA
  and original GPT/layout records. Internal Data is preferred; 332 MiB free
  includes the safety reserve. Copy backups off-device before formatting Data.
- Vendor, Cache and old System image backups are omitted by default.
- Fresh System is created with `mke2fs -E nodiscard`.
- Regular unmount retries and durable progress checkpoints; no forced unmount.
- N8000 targets: System 2048 MiB, Cache 152 MiB. Other partition boundaries
  remain unchanged and Data is not formatted by the ZIP.
- N8010 remains experimental; N8020 and unknown layouts are rejected.

The complete flow passed through TWRP on a 32 GB N8000, including independent
PC verification, read-only repeat and recovery reboot. Seventeen host tests
pass. Earlier shared-installer testing also covered a separate 16 GB N8000;
the current two-step flow has not yet been fully verified on a 16 GB device.

Another 16 GB test device has an unresolved MMC/controller failure, also
reproduced outside the installer while creating a directory on Data. Neither
reduced clock nor omitted large backups established a fix. This release does
not diagnose or repair a hardware/recovery I/O fault. See VALIDATION.md.
