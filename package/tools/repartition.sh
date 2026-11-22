#!/sbin/sh
# Exact layout profiles. Only CACHE and SYSTEM boundaries may change.
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
FRESH_SYSTEM=${N80XX_FRESH_SYSTEM:-1}
BACKUP_VENDOR=${N80XX_BACKUP_VENDOR:-0}
BACKUP_CACHE=${N80XX_BACKUP_CACHE:-0}
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
checkpoint() {
    printf '%s\n' 'FORMAT_VERSION=1' "PROFILE=$PROFILE" "PHASE=$1" \
        >"$BACKUP/progress.txt.tmp"
    sync
    mv "$BACKUP/progress.txt.tmp" "$BACKUP/progress.txt"
    sync
}
save() {
    src=$1; dst=$2
    checkpoint "backup-copy:$dst"
    say "Backing up $dst..."
    dd if="$src" of="$BACKUP/$dst" bs=1048576 || die "Backup failed: $dst"
    say "Flushing $dst before verification..."
    sync
    checkpoint "backup-flushed:$dst"
    expected_bytes=$(blockdev --getsz "$src") || die "Cannot size $src"
    expected_bytes=$(awk -v s="$expected_bytes" 'BEGIN {printf "%.0f", s*512}')
    actual_bytes=$(ls -ln "$BACKUP/$dst" | awk '{print $5}')
    [ "$actual_bytes" = "$expected_bytes" ] || die "Backup size mismatch: $dst"
    say "Verifying source checksum for $dst..."
    source_hash=$(hash "$src") || die "Cannot hash source: $dst"
    checkpoint "backup-source-hashed:$dst"
    say "Verifying saved checksum for $dst..."
    backup_hash=$(hash "$BACKUP/$dst") || die "Cannot hash backup: $dst"
    [ "$source_hash" = "$backup_hash" ] || die "Backup checksum mismatch: $dst"
    printf '%s  %s\n' "$backup_hash" "$BACKUP/$dst" >>"$BACKUP/SHA256SUMS"
    checkpoint "backup-verified:$dst"
    say "Verified $dst."
}
is_mounted() { awk -v mp="$1" '$2==mp {ok=1} END {exit !ok}' /proc/mounts; }

# Check the entire kernel map before touching a partition after a GPT reread.
verify_kernel_map() {
    map_table=$1
    map_part=0
    for map_name in $PARTITION_NAMES; do
        map_part=$((map_part + 1))
        node="/dev/block/mmcblk0p$map_part"
        [ -b "$node" ] || return 1
        geometry=$(printf '%s\n' "$map_table" | awk -F: -v number="$map_part" -v name="$map_name" '
            $1==number && $6==name {printf "%.0f %.0f\n", $2+0, $4+0}')
        start=$(cat "/sys/class/block/mmcblk0p$map_part/start") || return 1
        size=$(cat "/sys/class/block/mmcblk0p$map_part/size") || return 1
        [ "$geometry" = "$start $size" ] || return 1
    done
}

check_by_name_directory() {
    command -v ln >/dev/null || return 1
    awk '$2=="/dev" && $3=="tmpfs" {ok=1} END {exit !ok}' /proc/mounts || return 1
    [ -d "$BY_NAME" ] && [ "$(readlink -f "$BY_NAME")" = "$BY_NAME" ]
}

verify_existing_aliases() {
    alias_part=0
    for alias_name in $PARTITION_NAMES; do
        alias_part=$((alias_part + 1))
        alias="$BY_NAME/$alias_name"
        if [ -e "$alias" ] || [ -L "$alias" ]; then
            [ -L "$alias" ] &&
                [ "$(readlink -f "$alias")" = "/dev/block/mmcblk0p$alias_part" ] || return 1
        fi
    done
}

# The GPT reread can remove ueventd's by-name links in legacy TWRP. With an
# empty System, legacy TWRP can hang during a recovery reboot.
prepare_same_session_rom_install() {
    check_by_name_directory || return 1
    mount_source=$(awk '$2=="/data" && $3=="ext4" {print $1}' /proc/mounts)
    [ -n "$mount_source" ] && [ "$(readlink -f "$mount_source")" = "$DATA_DEVICE" ] || return 1

    verify_kernel_map "$TABLE_AFTER" && verify_existing_aliases || return 1
    # Create only missing aliases; never replace a link or device node.
    links_created=0
    number=0
    for name in $PARTITION_NAMES; do
        number=$((number + 1))
        node="/dev/block/mmcblk0p$number"
        alias="$BY_NAME/$name"
        if [ ! -L "$alias" ]; then
            [ ! -e "$alias" ] && ln -s "$node" "$alias" || return 1
            links_created=$((links_created + 1))
        fi
        [ "$(readlink -f "$alias")" = "$node" ] || return 1
    done
    if [ "$restore_internal_storage" = 1 ]; then
        [ -d /data/media/0 ] && [ "$(readlink -f /data/media/0)" = /data/media/0 ] || return 1
        [ -d /sdcard ] && [ "$(readlink -f /sdcard)" = /sdcard ] || return 1
        if ! is_mounted /sdcard; then
            mount -o bind /data/media/0 /sdcard || return 1
        fi
        internal_storage_is_mounted || return 1
    fi
    say "Verified all $PARTITION_COUNT partition paths; restored $links_created missing links."
}

internal_storage_is_mounted() {
    mmc_data_dev=$(cat /sys/class/block/mmcblk0p$DATA_PART/dev) || return 1
    awk -v dev="$mmc_data_dev" '$3==dev && $4=="/media/0" && $5=="/sdcard" {ok=1} END {exit !ok}' /proc/self/mountinfo
}

log_data_references() {
    # Failure diagnostics remain in recovery RAM and may contain private paths.
    for ref_pid in /proc/[0-9]*; do
        for ref_fd in "$ref_pid"/fd/* "$ref_pid"/cwd; do
            ref_target=$(readlink "$ref_fd") || continue
            case "$ref_target" in /data*|/sdcard*) printf '%s %s\n' "$ref_fd" "$ref_target";; esac
        done
        awk -v pid="$ref_pid" '/\/data\/|\/sdcard\// {print pid, $0}' "$ref_pid/maps" 2>/dev/null || :
    done > /tmp/n80xx-open-data.txt
}
unmount_checked() {
    unmount_attempt=0
    while is_mounted "$1"; do
        if umount "$1"; then return 0; fi
        unmount_attempt=$((unmount_attempt + 1))
        if [ "$unmount_attempt" -ge 5 ]; then
            log_data_references
            die "Cannot unmount $1; GPT unchanged. See /tmp/n80xx-open-data.txt."
        fi
        say "Waiting for open accesses to $1 to close..."
        sleep 1
    done
}
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
            [ "$(readlink -f "$source")" = "$DATA_DEVICE" ] || continue
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
        if [ "$available" -ge "$REQUIRED_KIB" ]; then
            BACKUP=$candidate
            break
        fi
    done
    [ -n "$BACKUP" ] || die "Insufficient backup space. Need $REQUIRED_KIB KiB free on internal Data or an optional external SD."
    say "Backup destination: $BACKUP"
}

case "$FRESH_SYSTEM:$BACKUP_VENDOR:$BACKUP_CACHE" in [01]:[01]:[01]) ;; *) die 'Invalid backup mode; flags must be 0 or 1.';; esac
BACKUP_TAG=
for tool in e2fsck resize2fs tune2fs sha256sum dd wc ls mv cat blockdev mount umount readlink df awk sed cut sleep; do
    command -v "$tool" >/dev/null || die "Missing recovery tool: $tool"
done
[ -x "$PARTED" ] || die 'Bundled static parted missing.'
[ -x "$READ_RANGE" ] || die 'Bundled read-only range helper missing.'
. "$HERE/profiles.sh"
DEVICE=$(getprop ro.product.device)
TABLE=$("$PARTED" -m -s "$DISK" unit s print) || die 'Cannot read GPT.'
printf '%s\n' "$TABLE" | sed -n '2p' | awk -F: '$4==512 && $5==512 && $6=="gpt" {ok=1} END {exit !ok}' || die 'Expected GPT with 512-byte sectors.'
select_profile || die "Unsupported model or partition layout: $DEVICE. No changes made."
CACHE_DEVICE="/dev/block/mmcblk0p$CACHE_PART"
SYSTEM_DEVICE="/dev/block/mmcblk0p$SYSTEM_PART"
DATA_DEVICE="/dev/block/mmcblk0p$DATA_PART"
BY_NAME=/dev/block/platform/dw_mmc/by-name
verify_kernel_map "$TABLE" || die 'Kernel and GPT maps disagree. No changes made.'
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
system_bytes=$(partition_line "$SYSTEM_PART" | awk -F: '{printf "%.0f", ($4+0)*512}')
cache_bytes=$(partition_line "$CACHE_PART" | awk -F: '{printf "%.0f", ($4+0)*512}')
if [ "$FRESH_SYSTEM" = 0 ] || [ "$STATE" = resized ]; then
    check_ext "$SYSTEM_DEVICE" "$system_bytes"
fi
check_ext "$CACHE_DEVICE" "$cache_bytes"
if [ "$STATE" = resized ]; then
    check_size "$SYSTEM_DEVICE" 2147483648 || die 'SYSTEM restoration/growth incomplete. Recover from the backup before retrying.'
    check_size "$CACHE_DEVICE" "$TARGET_CACHE_BYTES" || die 'CACHE filesystem size mismatch.'
    for part in "$SYSTEM_DEVICE" "$CACHE_DEVICE"; do
        e2fsck -fn "$part" || die "Unmount and check $part in recovery."
    done
    say 'Already resized. Read-only checks passed; no changes made.'
    exit 0
fi
choose_backup
[ "$MODE" = --apply ] || { say 'Preflight passed. Check only; no changes made.'; exit 0; }
same_session=0
restore_internal_storage=0
if [ "$FRESH_SYSTEM" = 1 ] && [ "$(getprop ro.twrp.version)" = 3.7.0_9-0 ]; then
    check_by_name_directory && verify_existing_aliases ||
        die 'Cannot prepare ROM device paths for this TWRP session. No changes made.'
    same_session=1
    if internal_storage_is_mounted; then restore_internal_storage=1; fi
fi
# Data must be unencrypted ext4 even when backups go to external SD.
awk '$2=="/data" && $3=="ext4" {ok=1} END {exit !ok}' /proc/mounts || die 'Mount unencrypted ext4 Data first.'
data_source=$(awk '$2=="/data" {print $1}' /proc/mounts)
[ "$(readlink -f "$data_source")" = "$DATA_DEVICE" ] || die 'Unexpected Data device.'
for mp in /system /system_root /cache /efs /vendor /preload $EXTRA_UNMOUNTS; do
    if is_mounted "$mp"; then umount "$mp" || die "Cannot unmount $mp"; fi
done
mkdir -p "$BACKUP"
# vfat has no Unix permission bits. Host/device backups contain private EFS data.
case "$BACKUP" in /data/*) chmod 700 "$BACKUP";; esac
printf '%s\n' "$TABLE" >"$BACKUP/partitions-before.txt"
printf '%s\n' "$PROFILE" >"$BACKUP/profile.txt"
checkpoint backup-started
for item in $backup_parts; do
    save "/dev/block/mmcblk0p${item%%:*}" "${item#*:}"
done
SECTORS=$(blockdev --getsz "$DISK")
checkpoint backup-gpt
"$READ_RANGE" "$DISK" 0 8192 >"$BACKUP/gpt-primary.bin"
"$READ_RANGE" "$DISK" "$((SECTORS - 8192))" 8192 >"$BACKUP/gpt-tail.bin"
[ "$(wc -c <"$BACKUP/gpt-primary.bin")" = 4194304 ] || die 'Primary GPT backup size mismatch.'
[ "$(wc -c <"$BACKUP/gpt-tail.bin")" = 4194304 ] || die 'Tail GPT backup size mismatch.'
printf '%s\n' 'FORMAT_VERSION=1' "PROFILE=$PROFILE" "DEVICE=$DEVICE" \
    "DISK_SECTORS=$SECTORS" 'SECTOR_BYTES=512' "FRESH_SYSTEM=$FRESH_SYSTEM" \
    "BACKUP_VENDOR=$BACKUP_VENDOR" "BACKUP_CACHE=$BACKUP_CACHE" "ORIGINAL_CACHE_START=$CACHE_START" \
    "ORIGINAL_CACHE_END=$ORIGINAL_CACHE_END" "ORIGINAL_SYSTEM_START=$ORIGINAL_SYSTEM_START" \
    "ORIGINAL_SYSTEM_END=$SYSTEM_END" "TARGET_CACHE_END=$TARGET_CACHE_END" \
    "TARGET_SYSTEM_START=$TARGET_SYSTEM_START" "TARGET_SYSTEM_END=$SYSTEM_END" \
    "CACHE_PART=$CACHE_PART" "SYSTEM_PART=$SYSTEM_PART" "VENDOR_PART=$VENDOR_PART" \
    "OTA_PART=$OTA_PART" "DATA_PART=$DATA_PART" >"$BACKUP/layout-backup.env"
sha256sum "$BACKUP/gpt-primary.bin" "$BACKUP/gpt-tail.bin" \
    "$BACKUP/partitions-before.txt" "$BACKUP/layout-backup.env" >>"$BACKUP/SHA256SUMS"
sync
checkpoint filesystem-checks
if [ "$FRESH_SYSTEM" = 0 ]; then fsck "$SYSTEM_DEVICE"; fi
fsck "$CACHE_DEVICE"
say "Shrinking CACHE filesystem to $TARGET_CACHE_KIB KiB..."
checkpoint cache-shrink
resize2fs "$CACHE_DEVICE" "${TARGET_CACHE_KIB}K"
fsck "$CACHE_DEVICE"
check_size "$CACHE_DEVICE" "$TARGET_CACHE_BYTES" || die 'CACHE shrink size mismatch; GPT unchanged.'
sync
checkpoint gpt-update-pending
for mp in /sdcard /data; do
    unmount_checked "$mp"
done
awk '$1 ~ /mmcblk0p|dw_mmc/ {found=1} END {exit found}' /proc/mounts || die 'Internal storage still mounted; GPT unchanged.'
say 'Updating only CACHE/SYSTEM entries. Do not interrupt.'
"$PARTED" -s "$DISK" unit s rm "$SYSTEM_PART" rm "$CACHE_PART" \
    mkpart CACHE ext4 "$CACHE_START" "$TARGET_CACHE_END" \
    mkpart SYSTEM ext4 "$TARGET_SYSTEM_START" "$SYSTEM_END" name "$CACHE_PART" CACHE name "$SYSTEM_PART" SYSTEM
TABLE_AFTER=$("$PARTED" -m -s "$DISK" unit s print) || die 'Cannot read GPT after update. Keep recovery running.'
protected_table() {
    printf '%s\n' "$1" | awk -F: -v cache="$CACHE_PART" -v system="$SYSTEM_PART" '$1!=cache && $1!=system'
}
[ "$(protected_table "$TABLE")" = "$(protected_table "$TABLE_AFTER")" ] ||
    die 'Unexpected GPT change outside CACHE/SYSTEM. Keep recovery running.'
TABLE=$TABLE_AFTER
partition_matches "$CACHE_PART" "$CACHE_START" "$TARGET_CACHE_END" CACHE &&
    partition_matches "$SYSTEM_PART" "$TARGET_SYSTEM_START" "$SYSTEM_END" SYSTEM ||
    die 'Updated CACHE or SYSTEM geometry is wrong. Keep recovery running.'
verify_kernel_map "$TABLE_AFTER" ||
    die 'Kernel and updated GPT maps disagree. Keep recovery running and consult recovery instructions.'
mount -t ext4 "$DATA_DEVICE" /data
if [ "$FRESH_SYSTEM" = 1 ]; then
    checkpoint system-create
    say 'Creating fresh 2 GiB SYSTEM filesystem...'
    # Avoid discard on the legacy MMC/recovery stack before writing the new FS.
    mke2fs -t ext4 -b 4096 -m 0 -L system -E nodiscard -F "$SYSTEM_DEVICE"
else
    checkpoint system-restore
    say 'Restoring SYSTEM and growing its filesystem...'
    dd if="$BACKUP/system.img" of="$SYSTEM_DEVICE" bs=1048576
    sync
    fsck "$SYSTEM_DEVICE"
    resize2fs "$SYSTEM_DEVICE"
fi
fsck "$SYSTEM_DEVICE"
fsck "$CACHE_DEVICE"
check_size "$SYSTEM_DEVICE" 2147483648 || die 'SYSTEM final size mismatch.'
check_size "$CACHE_DEVICE" "$TARGET_CACHE_BYTES" || die 'CACHE final size mismatch.'
checkpoint final-checks
verify_parts=$CRITICAL_BACKUPS
if [ "$BACKUP_VENDOR" = 1 ]; then verify_parts="$verify_parts $VENDOR_PART:vendor.img"; fi
for item in $verify_parts; do
    source_hash=$(hash "/dev/block/mmcblk0p${item%%:*}") || die "Cannot hash partition ${item%%:*}"
    backup_hash=$(hash "$BACKUP/${item#*:}") || die "Cannot hash backup ${item#*:}"
    [ "$source_hash" = "$backup_hash" ] || die "Partition ${item%%:*} checksum changed. Keep recovery running."
done
printf '%s\n' "$TABLE_AFTER" >"$BACKUP/partitions-after.txt"
sync
checkpoint complete
say 'Done. SYSTEM 2048 MiB; EFS/Recovery/Modem/OTA verified unchanged; vendor boundaries preserved.'
if [ "$BACKUP_VENDOR" = 1 ]; then say 'Vendor image checksum also verified unchanged.'; fi
say "Backups: $BACKUP."
if [ "$same_session" = 1 ]; then
    if prepare_same_session_rom_install; then
        say 'ROM installation is ready in this TWRP session. Do not reboot yet.'
        say 'Return to Install and select the ROM. Internal files are under /data/media/0.'
    else
        die 'Repartition complete, but ROM device paths could not be verified. Keep TWRP running and consult the recovery instructions.'
    fi
else
    say 'Reboot recovery before installing a ROM.'
fi
