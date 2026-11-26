This prerelease accepts the stock GT-N8010 boundaries reported in
[#1](https://github.com/html6405/n80xx-repartition/issues/1) and
[#2](https://github.com/html6405/n80xx-repartition/issues/2). It produces
2 GiB System and 152 MiB Cache while preserving HIDDEN, OTA and Userdata
boundaries. The earlier, previously modified N8010 profile is still included.

**System is erased. Have a compatible ROM ready before starting.** Read the
[installation and backup instructions](https://github.com/html6405/n80xx-repartition/blob/v0.2.0-rc3/README.md).

1. In TWRP, leave automatic reboot disabled and install the downloaded ZIP.
   Step 1 verifies a copy at `/tmp/N80xx-System-2GiB.zip`.
2. Install that verified ZIP from `/tmp` without rebooting. Step 2 saves and
   checks the critical partitions and GPT, shrinks Cache, and prepares 2 GiB
   System.
3. If the installer reports **ROM installation is ready in this TWRP session**,
   install the ROM immediately in that session. For other recoveries, follow the
   message shown by the installer.

On TWRP 3.7.0_9-0, the ZIP verifies and restores any missing partition paths and
restores the internal storage mount if it was originally present. This avoids
starting an affected TWRP with an empty System, which could trigger a hang when
reading Android's binary storage metadata. The ZIP also skips probing microSD
when internal storage has enough space for the backups.

| Tested device/profile | Cache after repartition | Hardware validation |
| --- | ---: | --- |
| GT-N8000, matching 16 GB layout | 152 MiB | Both ZIP stages, same-session LOS21 installation and Android boot |
| GT-N8010, stock boundaries reported on 16 GB and 32 GB units | 152 MiB | New profile checked on the host. Community-reported repartitioning and Android boot on four 16 GB units using an adapted RC2 profile. |
| GT-N8010, observed previously modified 16 GB layout | About 705 MiB | Both ZIP stages, same-session LOS23.2 installation and Android boot |
| GT-N8020, exact observed 16 GB layout | 512 MiB | Both ZIP stages and all layout checks passed. The original GPT, Cache and System were then restored byte-for-byte. ROM installation and Android boot on the resized layout remain unverified. |

The published RC1 ZIP also passed partitioning tests on a matching 32 GB N8000.
The N8020 profile changes only partitions 12 (Cache) and 13 (System), and
additionally backs up BOOT, PARAM and all three LTE modem EFS partitions.
All profiles reject unknown layouts. The
[validation record](https://github.com/html6405/n80xx-repartition/blob/v0.2.0-rc3/VALIDATION.md)
identifies the exact candidate run on each device. Twenty-two host tests pass.
