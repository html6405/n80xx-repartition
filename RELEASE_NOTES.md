One recovery ZIP with explicitly checked device/layout profiles.

- Matching N8000 layouts: System 2048 MiB, Cache 152 MiB.
- Real N8000 16 GB test passed in explicitly requested fresh System mode:
  independent EFS/OTA verification, GPT and filesystem checks, read-only repeat
  run and recovery reboot.
- ext4 without a journal is recognized even when old Parted reports ext2.
- Original GPT regions, layout records and checksums are saved.
- System, Vendor and Cache images are backed up by default. Skipping these
  images requires the explicit options documented in README.
- N8010 profile is experimental; final device verification is still pending.
- N8020 and unknown layouts are rejected.

Create independent EFS and personal-data backups first. Fresh System mode
requires installing a suitable ROM afterwards. GPT backup files are not an
automatic revert function; follow the README. See THIRD_PARTY.md for the legacy
Parted binary's provenance.

This prerelease updates the documentation to English. The repartitioning
implementation is unchanged from v0.1.0-rc1.
