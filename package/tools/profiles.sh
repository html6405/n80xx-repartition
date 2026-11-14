# Exact observed layouts only. Sourcing this file performs no device access.
partition_line() { printf '%s\n' "$TABLE" | sed -n "/^$1:/p"; }
partition_matches() {
    partition_line "$1" | awk -F: -v start="$2"s -v end="$3"s -v name="$4" '
        $2==start && $3==end && $6==name {ok=1} END {exit !ok}'
}
select_profile() {
    case "$DEVICE" in
        p4noterf|p4noterfxx|n8000|GT-N8000)
            PROFILE=n8000-observed
            SYSTEM_END=4685823
            HIDDEN_START=4685824; HIDDEN_END=5709823
            OTA_START=5709824; OTA_END=5726207; DATA_START=5726208 ;;
        p4notewifi|p4notewifiww|n8010|GT-N8010)
            PROFILE=n8010-observed-16gb
            SYSTEM_END=5818359
            HIDDEN_START=5818360; HIDDEN_END=6843750
            OTA_START=6843751; OTA_END=6860134; DATA_START=6860135 ;;
        *) return 1 ;;
    esac
    for spec in '1 8192 16383 BOTA0' '2 16384 24575 BOTA1' '3 24576 65535 EFS' '4 65536 81919 PARAM' '5 81920 98303 BOOT' '6 98304 114687 RECOVERY' '7 114688 180223 RADIO'; do
        set -- $spec
        partition_matches "$1" "$2" "$3" "$4" || return 1
    done
    partition_matches 10 "$HIDDEN_START" "$HIDDEN_END" HIDDEN || return 1
    partition_matches 11 "$OTA_START" "$OTA_END" OTA || return 1
    partition_line 12 | awk -F: -v start="${DATA_START}s" '
        $2==start && $6=="USERDATA" {ok=1} END {exit !ok}' || return 1
    [ "$(printf '%s\n' "$TABLE" | awk -F: '$1 ~ /^[0-9]+$/ {n++} END {print n}')" = 12 ] || return 1
    TARGET_SYSTEM_START=$((SYSTEM_END + 1 - 4194304))
    TARGET_CACHE_END=$((TARGET_SYSTEM_START - 1))
    TARGET_CACHE_SECTORS=$((TARGET_SYSTEM_START - 180224))
    [ "$TARGET_CACHE_SECTORS" -gt 0 ] && [ "$((TARGET_CACHE_SECTORS % 8))" = 0 ] || return 1
    TARGET_CACHE_KIB=$((TARGET_CACHE_SECTORS / 2))
    TARGET_CACHE_BYTES=$((TARGET_CACHE_SECTORS * 512))
    if partition_matches 8 180224 1818623 CACHE && partition_matches 9 1818624 "$SYSTEM_END" SYSTEM; then
        STATE=original
    elif partition_matches 8 180224 "$TARGET_CACHE_END" CACHE && partition_matches 9 "$TARGET_SYSTEM_START" "$SYSTEM_END" SYSTEM; then
        STATE=resized
    else
        return 1
    fi
    # Actual images plus two 4 MiB GPT ranges and 256 MiB reserve, rounded up.
    REQUIRED_KIB=$(printf '%s\n' "$TABLE" | awk -F: -v fresh="${FRESH_SYSTEM:-1}" -v vendor="${BACKUP_VENDOR:-0}" -v cache="${BACKUP_CACHE:-0}" '
        $1==3 || $1==6 || $1==7 || $1==11 || ($1==8 && cache==1) || ($1==9 && fresh==0) || ($1==10 && vendor==1) {sum+=$4+0}
        END {printf "%.0f\n", int((sum+1)/2)+8192+262144}')
}
