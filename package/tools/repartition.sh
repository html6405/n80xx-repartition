#!/sbin/sh
# Candidate: exact N8000/N8010 profiles, immutable SYSTEM end and partitions 1-7/10-12.
set -eu
umask 077
MODE=${1:---check}
case "$MODE" in --check|--apply) ;; *) echo 'Use --check or --apply'; exit 1;; esac
PATH=/sbin:/system/bin:/vendor/bin:$PATH
export PATH
HERE=${0%/*}
DISK=/dev/block/mmcblk0
PARTED="$HERE/parted"
READ_RANGE="$HERE/read-range"
FRESH_SYSTEM=${N80XX_FRESH_SYSTEM:-0}
BACKUP_VENDOR=${N80XX_BACKUP_VENDOR:-1}
BACKUP_CACHE=${N80XX_BACKUP_CACHE:-1}
say() {
    echo "$*"
    if [ -n "${OUTFD:-}" ]; then
        echo "ui_print $*" >&"$OUTFD"
        echo ui_print >&"$OUTFD"
    fi
}
die() { say "ERROR: $*"; exit 1; }
hash() {
    digest_output=$(sha256sum "$1") || die "Cannot hash $1"
    printf '%s\n' "${digest_output%% *}"
}
fsck() {
    rc=0
    e2fsck -fy "$1" || rc=$?
    [ "$rc" -le 1 ] || die "e2fsck failed ($rc): $1"
}
check_ext() {
    fs_info=$(tune2fs -l "$1") || die "Not a readable ext filesystem: $1"
    printf '%s\n' "$fs_info" | awk -F: -v limit="$2" '
        /^Filesystem magic number:/ {magic=($2 ~ /0xEF53/)}
        /^Block count:/ {count=$2+0}
        /^Block size:/ {size=$2+0}
        END {exit !(magic && size==4096 && count>0 && count*size<=limit)}' || die "Unsupported or oversized filesystem: $1"
}
check_size() {
    fs_info=$(tune2fs -l "$1") || return 1
    printf '%s\n' "$fs_info" | awk -F: -v expected="$2" '
        /^Block count:/ {count=$2+0}
        /^Block size:/ {size=$2+0}
        END {exit !(count*size==expected)}'
}
save() {
    src=$1; dst=$2
    say "Backing up $dst..."
    dd if="$src" of="$BACKUP/$dst" bs=1048576 || die "Backup failed: $dst"
    expected_bytes=$(blockdev --getsz "$src") || die "Cannot size $src"
    expected_bytes=$(awk -v s="$expected_bytes" 'BEGIN {printf "%.0f", s*512}')
    actual_bytes=$(wc -c <"$BACKUP/$dst")
    [ "$actual_bytes" = "$expected_bytes" ] || die "Backup size mismatch: $dst"
    source_hash=$(hash "$src") || die "Cannot hash source: $dst"
    backup_hash=$(hash "$BACKUP/$dst") || die "Cannot hash backup: $dst"
    [ "$source_hash" = "$backup_hash" ] || die "Backup checksum mismatch: $dst"
    printf '%s  %s\n' "$backup_hash" "$BACKUP/$dst" >>"$BACKUP/SHA256SUMS"
    say "Verified $dst."
}
is_mounted() { awk -v mp="$1" '$2==mp {ok=1} END {exit !ok}' /proc/mounts; }
free_kib() { df -k "$1" | awk 'END {print $(NF-2)}'; }
choose_backup() {
    BACKUP=
    data_base=/data/media/0
    # Fresh Data in an older recovery may have media/ but no Android user 0 yet.
    [ -d "$data_base" ] || data_base=/data/media
    for base in "$data_base" /external_sdcard; do
        if [ "$base" = /data/media/0 ] || [ "$base" = /data/media ]; then
            mp=/data
            awk '$2=="/data" && $3=="ext4" && $4 ~ /(^|,)rw(,|$)/ {ok=1} END {exit !ok}' /proc/mounts || continue
            source=$(awk '$2=="/data" {print $1}' /proc/mounts)
            [ "$(readlink -f "$source")" = /dev/block/mmcblk0p12 ] || continue
        else
            mp=/external_sdcard
            awk '$2=="/external_sdcard" && $3 ~ /^(vfat|exfat|ext4)$/ && $4 ~ /(^|,)rw(,|$)/ {ok=1} END {exit !ok}' /proc/mounts || continue
            source=$(awk '$2=="/external_sdcard" {print $1}' /proc/mounts)
            case "$(readlink -f "$source")" in /dev/block/mmcblk1|/dev/block/mmcblk1p[0-9]*) ;; *) continue;; esac
        fi
        [ -d "$base" ] || continue
        [ "$(readlink -f "$base")" = "$base" ] || die "Symlinked backup base is unsupported: $base"
        candidate="$base/n80xx-repartition-backup-$BACKUP_TAG"
        [ ! -e "$candidate" ] && [ ! -L "$candidate" ] || die "Existing backup: $candidate. Preserve it on a PC before retrying."
        available=$(free_kib "$mp")
        case "$available" in ''|*[!0-9]*) die "Cannot read free space on $mp";; esac
        say "$mp: $available KiB free; need $REQUIRED_KIB KiB including reserve."
        if [ "$available" -ge "$REQUIRED_KIB" ] && [ -z "$BACKUP" ]; then
            BACKUP=$candidate
        fi
    done
    [ -n "$BACKUP" ] || die 'Insufficient backup space. Free at least 4 GiB on the external SD and mount it at /external_sdcard.'
    say "Backup destination: $BACKUP"
}

case "$FRESH_SYSTEM:$BACKUP_VENDOR:$BACKUP_CACHE" in [01]:[01]:[01]) ;; *) die 'Invalid backup mode; flags must be 0 or 1.';; esac
BACKUP_TAG=
for tool in e2fsck resize2fs tune2fs sha256sum dd wc blockdev mount umount readlink df awk sed cut; do
    command -v "$tool" >/dev/null || die "Missing recovery tool: $tool"
done
[ -x "$PARTED" ] || die 'Bundled static parted missing.'
[ -x "$READ_RANGE" ] || die 'Bundled read-only range helper missing.'
. "$HERE/profiles.sh"
DEVICE=$(getprop ro.product.device)
TABLE=$("$PARTED" -m -s "$DISK" unit s print) || die 'Cannot read GPT.'
printf '%s\n' "$TABLE" | sed -n '2p' | awk -F: '$4==512 && $5==512 && $6=="gpt" {ok=1} END {exit !ok}' || die 'Expected GPT with 512-byte sectors.'
select_profile || die "Unsupported model or partition layout: $DEVICE. No changes made."
BACKUP_TAG=$PROFILE
if [ "$FRESH_SYSTEM" = 1 ]; then
    BACKUP_TAG="$BACKUP_TAG-fresh-system"
    command -v mke2fs >/dev/null || die 'Fresh SYSTEM mode requires mke2fs.'
    say 'FRESH SYSTEM: existing SYSTEM contents will be erased; install a ROM afterwards.'
fi
if [ "$BACKUP_VENDOR" = 0 ]; then
    BACKUP_TAG="$BACKUP_TAG-no-vendor"
    say 'Vendor image backup disabled; HIDDEN boundaries remain protected.'
fi
if [ "$BACKUP_CACHE" = 0 ]; then
    BACKUP_TAG="$BACKUP_TAG-no-cache"
    say 'CACHE image backup disabled; its filesystem is still checked and resized.'
fi
say "Profile: $PROFILE; state: $STATE. SYSTEM target: 2048 MiB."
say "CACHE target: $TARGET_CACHE_KIB KiB. EFS/vendor/OTA/Data boundaries stay unchanged."
system_bytes=$(partition_line 9 | awk -F: '{printf "%.0f", ($4+0)*512}')
cache_bytes=$(partition_line 8 | awk -F: '{printf "%.0f", ($4+0)*512}')
if [ "$FRESH_SYSTEM" = 0 ] || [ "$STATE" = resized ]; then
    check_ext /dev/block/mmcblk0p9 "$system_bytes"
fi
check_ext /dev/block/mmcblk0p8 "$cache_bytes"
if [ "$STATE" = resized ]; then
    check_size /dev/block/mmcblk0p9 2147483648 || die 'SYSTEM restoration/growth incomplete. Recover from the backup before retrying.'
    check_size /dev/block/mmcblk0p8 "$TARGET_CACHE_BYTES" || die 'CACHE filesystem size mismatch.'
    for part in /dev/block/mmcblk0p9 /dev/block/mmcblk0p8; do
        e2fsck -fn "$part" || die "Unmount and check $part in recovery."
    done
    say 'Already resized. Read-only checks passed; no changes made.'
    exit 0
fi
choose_backup
[ "$MODE" = --apply ] || { say 'Preflight passed. Check only; no changes made.'; exit 0; }
# Data must be unencrypted ext4 even when backups go to external SD.
awk '$2=="/data" && $3=="ext4" {ok=1} END {exit !ok}' /proc/mounts || die 'Mount unencrypted ext4 Data first.'
data_source=$(awk '$2=="/data" {print $1}' /proc/mounts)
[ "$(readlink -f "$data_source")" = /dev/block/mmcblk0p12 ] || die 'Unexpected Data device.'
for mp in /system /system_root /cache /efs /vendor /preload; do
    if is_mounted "$mp"; then umount "$mp" || die "Cannot unmount $mp"; fi
done
mkdir -p "$BACKUP"
# vfat has no Unix permission bits. Host/device backups contain private EFS data.
case "$BACKUP" in /data/*) chmod 700 "$BACKUP";; esac
printf '%s\n' "$TABLE" >"$BACKUP/partitions-before.txt"
printf '%s\n' "$PROFILE" >"$BACKUP/profile.txt"
save /dev/block/mmcblk0p3 efs.img
if [ "$BACKUP_VENDOR" = 1 ]; then save /dev/block/mmcblk0p10 vendor.img; fi
save /dev/block/mmcblk0p11 ota.img
if [ "$BACKUP_CACHE" = 1 ]; then save /dev/block/mmcblk0p8 cache.img; fi
if [ "$FRESH_SYSTEM" = 0 ]; then save /dev/block/mmcblk0p9 system.img; fi
SECTORS=$(blockdev --getsz "$DISK")
"$READ_RANGE" "$DISK" 0 8192 >"$BACKUP/gpt-primary.bin"
"$READ_RANGE" "$DISK" "$((SECTORS - 8192))" 8192 >"$BACKUP/gpt-tail.bin"
[ "$(wc -c <"$BACKUP/gpt-primary.bin")" = 4194304 ] || die 'Primary GPT backup size mismatch.'
[ "$(wc -c <"$BACKUP/gpt-tail.bin")" = 4194304 ] || die 'Tail GPT backup size mismatch.'
printf '%s\n' 'FORMAT_VERSION=1' "PROFILE=$PROFILE" "DEVICE=$DEVICE" \
    "DISK_SECTORS=$SECTORS" 'SECTOR_BYTES=512' "FRESH_SYSTEM=$FRESH_SYSTEM" \
    "BACKUP_VENDOR=$BACKUP_VENDOR" "BACKUP_CACHE=$BACKUP_CACHE" 'ORIGINAL_CACHE_START=180224' \
    'ORIGINAL_CACHE_END=1818623' 'ORIGINAL_SYSTEM_START=1818624' \
    "ORIGINAL_SYSTEM_END=$SYSTEM_END" "TARGET_CACHE_END=$TARGET_CACHE_END" \
    "TARGET_SYSTEM_START=$TARGET_SYSTEM_START" "TARGET_SYSTEM_END=$SYSTEM_END" \
    >"$BACKUP/layout-backup.env"
sha256sum "$BACKUP/gpt-primary.bin" "$BACKUP/gpt-tail.bin" \
    "$BACKUP/partitions-before.txt" "$BACKUP/layout-backup.env" >>"$BACKUP/SHA256SUMS"
sync
if [ "$FRESH_SYSTEM" = 0 ]; then fsck /dev/block/mmcblk0p9; fi
fsck /dev/block/mmcblk0p8
say "Shrinking CACHE filesystem to $TARGET_CACHE_KIB KiB..."
resize2fs /dev/block/mmcblk0p8 "${TARGET_CACHE_KIB}K"
fsck /dev/block/mmcblk0p8
check_size /dev/block/mmcblk0p8 "$TARGET_CACHE_BYTES" || die 'CACHE shrink size mismatch; GPT unchanged.'
sync
for mp in /sdcard /data; do
    if is_mounted "$mp"; then umount "$mp" || die "Cannot unmount $mp; GPT unchanged."; fi
done
awk '$1 ~ /mmcblk0p|dw_mmc/ {found=1} END {exit found}' /proc/mounts || die 'Internal storage still mounted; GPT unchanged.'
say 'Updating only CACHE/SYSTEM entries. Do not interrupt.'
"$PARTED" -s "$DISK" unit s rm 9 rm 8 mkpart CACHE ext4 180224 "$TARGET_CACHE_END" mkpart SYSTEM ext4 "$TARGET_SYSTEM_START" "$SYSTEM_END" name 8 CACHE name 9 SYSTEM
TABLE_AFTER=$("$PARTED" -m -s "$DISK" unit s print)
[ "$(printf '%s\n' "$TABLE" | sed '/^8:/d; /^9:/d')" = "$(printf '%s\n' "$TABLE_AFTER" | sed '/^8:/d; /^9:/d')" ] || die 'Unexpected GPT change outside CACHE/SYSTEM. Keep recovery running.'
[ "$(blockdev --getsz /dev/block/mmcblk0p8)" = "$TARGET_CACHE_SECTORS" ] || die 'Kernel CACHE size stale. Recover after recovery reboot.'
[ "$(blockdev --getsz /dev/block/mmcblk0p9)" = 4194304 ] || die 'Kernel SYSTEM size stale. Recover after recovery reboot.'
mount -t ext4 /dev/block/mmcblk0p12 /data
if [ "$FRESH_SYSTEM" = 1 ]; then
    say 'Creating fresh 2 GiB SYSTEM filesystem...'
    mke2fs -t ext4 -b 4096 -m 0 -L system -F /dev/block/mmcblk0p9
else
    say 'Restoring SYSTEM and growing its filesystem...'
    dd if="$BACKUP/system.img" of=/dev/block/mmcblk0p9 bs=1048576
    sync
    fsck /dev/block/mmcblk0p9
    resize2fs /dev/block/mmcblk0p9
fi
fsck /dev/block/mmcblk0p9
fsck /dev/block/mmcblk0p8
check_size /dev/block/mmcblk0p9 2147483648 || die 'SYSTEM final size mismatch.'
check_size /dev/block/mmcblk0p8 "$TARGET_CACHE_BYTES" || die 'CACHE final size mismatch.'
for pair in '3 efs.img' '10 vendor.img' '11 ota.img'; do
    set -- $pair
    if [ "$1" = 10 ] && [ "$BACKUP_VENDOR" = 0 ]; then continue; fi
    source_hash=$(hash "/dev/block/mmcblk0p$1") || die "Cannot hash partition $1"
    backup_hash=$(hash "$BACKUP/$2") || die "Cannot hash backup $2"
    [ "$source_hash" = "$backup_hash" ] || die "Partition $1 checksum changed. Keep recovery running."
done
printf '%s\n' "$TABLE_AFTER" >"$BACKUP/partitions-after.txt"
sync
say 'Done. SYSTEM 2048 MiB; EFS/OTA verified unchanged; vendor boundaries preserved.'
if [ "$BACKUP_VENDOR" = 1 ]; then say 'Vendor image checksum also verified unchanged.'; fi
say "Backups: $BACKUP. Reboot recovery before installing a ROM."
