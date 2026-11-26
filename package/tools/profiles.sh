# Exact observed layouts only. Sourcing this file performs no device access.
partition_line() { printf '%s\n' "$TABLE" | sed -n "/^$1:/p"; }
partition_name() {
    name_index=$1
    set -- $PARTITION_NAMES
    for profile_name in "$@"; do
        if [ "$name_index" -eq 1 ]; then printf '%s\n' "$profile_name"; return; fi
        name_index=$((name_index - 1))
    done
    return 1
}
partition_matches() {
    partition_line "$1" | awk -F: -v first="$2" -v last="$3" -v name="$4" '
        $2==first "s" && $3==last "s" && $4==(last-first+1) "s" && $6==name {n++}
        END {exit !(n==1)}'
}
select_profile() {
    CACHE_PART=8; SYSTEM_PART=9; VENDOR_PART=10; OTA_PART=11; DATA_PART=12
    CACHE_START=180224; ORIGINAL_CACHE_END=1818623; SYSTEM_END=4685823
    HIDDEN_START=4685824; HIDDEN_END=5709823
    OTA_START=5709824; OTA_END=5726207; DATA_START=5726208
    PARTITION_COUNT=12
    PARTITION_NAMES='BOTA0 BOTA1 EFS PARAM BOOT RECOVERY RADIO CACHE SYSTEM HIDDEN OTA USERDATA'
    FIXED_PARTITIONS='1:8192:16383 2:16384:24575 3:24576:65535 4:65536:81919 5:81920:98303 6:98304:114687 7:114688:180223'
    CRITICAL_BACKUPS='3:efs.img 6:recovery.img 7:modem.img 11:ota.img'
    EXTRA_UNMOUNTS=
    DATA_END=
    EXPECTED_DISK_SECTORS=
    case "$DEVICE" in
        p4noterf|p4noterfxx|n8000|GT-N8000)
            PROFILE=n8000-observed ;;
        p4notewifi|p4notewifiww|n8010|GT-N8010)
            PROFILE=n8010-stock
            # The original and resized states both retain their HIDDEN
            # boundaries. All fixed entries and CACHE/SYSTEM are checked below.
            if partition_matches "$VENDOR_PART" 5818360 6843750 HIDDEN; then
                PROFILE=n8010-observed-16gb
                SYSTEM_END=5818359
                HIDDEN_START=5818360; HIDDEN_END=6843750
                OTA_START=6843751; OTA_END=6860134; DATA_START=6860135
            fi ;;
        p4notelte|n8020|GT-N8020)
            PROFILE=n8020-observed-16gb
            CACHE_PART=12; SYSTEM_PART=13; VENDOR_PART=14; OTA_PART=15; DATA_PART=16
            CACHE_START=843776; ORIGINAL_CACHE_END=2940927; SYSTEM_END=6086655
            HIDDEN_START=6086656; HIDDEN_END=7233535
            OTA_START=7233536; OTA_END=7249919; DATA_START=7249920; DATA_END=30769151
            EXPECTED_DISK_SECTORS=30777344
            PARTITION_COUNT=16
            EXTRA_UNMOUNTS="/firmware /tombstones"
            # Recovered from the physical device's by-name links and sysfs
            # geometry. Require the exact same names in the on-device GPT.
            PARTITION_NAMES='BOTA0 BOTA1 EFS m9kefs1 m9kefs2 m9kefs3 PARAM BOOT RECOVERY RADIO TOMBSTONES CACHE SYSTEM HIDDEN OTA USERDATA'
            FIXED_PARTITIONS='1:8192:16383 2:16384:24575 3:24576:65535 4:65536:73727 5:73728:81919 6:81920:90111 7:90112:106495 8:106496:122879 9:122880:139263 10:139264:319487 11:319488:843775'
            CRITICAL_BACKUPS='3:efs.img 4:m9kefs1.img 5:m9kefs2.img 6:m9kefs3.img 7:param.img 8:boot.img 9:recovery.img 10:modem.img 15:ota.img' ;;
        *) return 1 ;;
    esac

    if [ -n "$EXPECTED_DISK_SECTORS" ]; then
        [ "$(printf '%s\n' "$TABLE" | awk -F: 'NR==2 {print $2}')" = "${EXPECTED_DISK_SECTORS}s" ] || return 1
    fi
    for fixed in $FIXED_PARTITIONS; do
        fixed_part=${fixed%%:*}
        fixed_bounds=${fixed#*:}
        partition_matches "$fixed_part" "${fixed_bounds%:*}" "${fixed_bounds#*:}" "$(partition_name "$fixed_part")" || return 1
    done
    partition_matches "$VENDOR_PART" "$HIDDEN_START" "$HIDDEN_END" HIDDEN || return 1
    partition_matches "$OTA_PART" "$OTA_START" "$OTA_END" OTA || return 1
    if [ -n "$DATA_END" ]; then
        partition_matches "$DATA_PART" "$DATA_START" "$DATA_END" USERDATA || return 1
    else
        partition_line "$DATA_PART" | awk -F: -v start="${DATA_START}s" '
            $2==start && $6=="USERDATA" {ok=1} END {exit !ok}' || return 1
    fi
    [ "$(printf '%s\n' "$TABLE" | awk -F: '$1 ~ /^[0-9]+$/ {n++} END {print n}')" = "$PARTITION_COUNT" ] || return 1

    TARGET_SYSTEM_SECTORS=4194304
    ORIGINAL_SYSTEM_START=$((ORIGINAL_CACHE_END + 1))
    TARGET_SYSTEM_START=$((SYSTEM_END + 1 - TARGET_SYSTEM_SECTORS))
    TARGET_CACHE_END=$((TARGET_SYSTEM_START - 1))
    TARGET_CACHE_SECTORS=$((TARGET_SYSTEM_START - CACHE_START))
    [ "$TARGET_CACHE_SECTORS" -gt 0 ] && [ "$((TARGET_CACHE_SECTORS % 8))" = 0 ] || return 1
    TARGET_CACHE_KIB=$((TARGET_CACHE_SECTORS / 2))
    TARGET_CACHE_BYTES=$((TARGET_CACHE_SECTORS * 512))
    if partition_matches "$CACHE_PART" "$CACHE_START" "$ORIGINAL_CACHE_END" CACHE &&
       partition_matches "$SYSTEM_PART" "$ORIGINAL_SYSTEM_START" "$SYSTEM_END" SYSTEM; then
        STATE=original
    elif partition_matches "$CACHE_PART" "$CACHE_START" "$TARGET_CACHE_END" CACHE &&
         partition_matches "$SYSTEM_PART" "$TARGET_SYSTEM_START" "$SYSTEM_END" SYSTEM; then
        STATE=resized
    else
        return 1
    fi

    # Actual images plus two 4 MiB GPT ranges and 256 MiB reserve, rounded up.
    backup_parts=$CRITICAL_BACKUPS
    if [ "${BACKUP_CACHE:-0}" = 1 ]; then backup_parts="$backup_parts $CACHE_PART:cache.img"; fi
    if [ "${BACKUP_VENDOR:-0}" = 1 ]; then backup_parts="$backup_parts $VENDOR_PART:vendor.img"; fi
    if [ "${FRESH_SYSTEM:-1}" = 0 ]; then backup_parts="$backup_parts $SYSTEM_PART:system.img"; fi
    REQUIRED_KIB=$(printf '%s\n' "$TABLE" | awk -F: -v plan="$backup_parts" '
        BEGIN {
            n=split(plan, pairs, " ")
            for (i=1; i<=n; i++) {split(pairs[i], fields, ":"); save[fields[1]]=1}
        }
        $1 in save {sum+=$4+0}
        END {printf "%.0f\n", int((sum+1)/2)+8192+262144}')
}
