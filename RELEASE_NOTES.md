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

The published ZIP subsequently passed the complete flow through TWRP on both
a 32 GB and a 16 GB N8000, including independent PC verification, read-only
repeat and recovery reboot. Seventeen host tests pass. See the current
VALIDATION.md for the later 16 GB retest of this unchanged ZIP.

The 16 GB retest device had previously shown MMC/controller errors, also
reproduced outside the installer while creating a directory on Data. The
complete published-ZIP retest passed without experimental clock settings;
the cause of the earlier errors remains undiagnosed. This release does not
establish a general hardware/recovery I/O repair. See VALIDATION.md.
