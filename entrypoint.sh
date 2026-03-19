#!/bin/sh

# PID of the currently running child process (python or sleep), for clean signal handling
CHILD_PID=""

# Signal handler for graceful shutdown
cleanup() {
    echo "Received shutdown signal, exiting gracefully..."
    if [ -n "$CHILD_PID" ]; then
        kill "$CHILD_PID" 2>/dev/null
        wait "$CHILD_PID" 2>/dev/null
    fi
    exit 0
}

# Set up signal handlers (SIGTERM=15, SIGINT=2)
trap 'cleanup' 15 2

# Run a python command as a tracked child process so signals can interrupt it
run_python() {
    python "$@" &
    CHILD_PID=$!
    wait $CHILD_PID
    EXIT_CODE=$?
    CHILD_PID=""
    return $EXIT_CODE
}

# Print Ace-Pace header (release date = mtime of acepace.py, no repo commits)
print_header() {
    RELEASE_DATE=$(stat -c %y /app/acepace.py 2>/dev/null | cut -d' ' -f1 || true)
    echo "============================================================"
    echo "                    Ace-Pace"
    echo "            One Pace Library Manager"
    if [ -n "$RELEASE_DATE" ]; then echo "                  Release $RELEASE_DATE"; fi
    echo "============================================================"
    echo "Running in Docker mode (non-interactive)"
    echo "------------------------------------------------------------"
    echo ""
}

# All operations for a single run
run_once() {
    # Media folder: ACEPACE_MEDIA_DIR_DOCKER (default /media)
    MEDIA_DIR="${ACEPACE_MEDIA_DIR_DOCKER:-/media}"

    # Run episodes update if requested
    if [ "$EPISODES_UPDATE" = "true" ]; then
        run_python /app/acepace.py --episodes_update ${NYAA_URL:+--url "$NYAA_URL"}
        if [ $? -ne 0 ]; then
            echo "Episodes update failed with exit code $?"
            return 1
        fi
    fi

    # Export database if requested
    if [ "$DB" = "true" ]; then
        run_python /app/acepace.py --db
        if [ $? -ne 0 ]; then
            echo "Database export failed with exit code $?"
            return 1
        fi
    fi

    # Run missing episodes report (unless already done by --episodes_update above)
    # When EPISODES_UPDATE=true, the report was already run in step 1 (--episodes_update does both)
    # Skip when only exporting DB (DB=true and no other operations)
    if [ "$EPISODES_UPDATE" != "true" ] && { [ "$DB" != "true" ] || [ "$DOWNLOAD" = "true" ]; }; then
        run_python /app/acepace.py \
            --folder "$MEDIA_DIR" \
            ${NYAA_URL:+--url "$NYAA_URL"}
        if [ $? -ne 0 ]; then
            echo "Missing episodes report failed with exit code $?"
            return 1
        fi
    fi

    # Run rename if requested (non-interactive: dry-run simulates, otherwise renames without confirmation)
    if [ "$RENAME" = "true" ]; then
        DRY_RUN_RENAME_ARG=""
        [ "$DRY_RUN" = "true" ] || [ "$DRY_RUN" = "1" ] || [ "$DRY_RUN" = "yes" ] || [ "$DRY_RUN" = "on" ] && DRY_RUN_RENAME_ARG="--dry-run"
        run_python /app/acepace.py \
            --folder "$MEDIA_DIR" \
            --rename \
            ${NYAA_URL:+--url "$NYAA_URL"} \
            ${DRY_RUN_RENAME_ARG:+$DRY_RUN_RENAME_ARG}
        if [ $? -ne 0 ]; then
            echo "Rename failed with exit code $?"
            return 1
        fi
    fi

    # Build DRY_RUN_ARG
    DRY_RUN_ARG=""
    [ "$DRY_RUN" = "true" ] || [ "$DRY_RUN" = "1" ] || [ "$DRY_RUN" = "yes" ] || [ "$DRY_RUN" = "on" ] && DRY_RUN_ARG="--dry-run"

    # If DOWNLOAD is set to true, download missing episodes after generating report
    if [ "$DOWNLOAD" = "true" ]; then
        run_python /app/acepace.py \
            --folder "$MEDIA_DIR" \
            ${NYAA_URL:+--url "$NYAA_URL"} \
            --download \
            ${DRY_RUN_ARG:+$DRY_RUN_ARG} \
            ${TORRENT_CLIENT:+--client "$TORRENT_CLIENT"} \
            ${TORRENT_HOST:+--host "$TORRENT_HOST"} \
            ${TORRENT_PORT:+--port "$TORRENT_PORT"} \
            ${TORRENT_USER:+--username "$TORRENT_USER"} \
            ${TORRENT_PASSWORD:+--password "$TORRENT_PASSWORD"} \
            ${TORRENT_CATEGORY:+--category "$TORRENT_CATEGORY"}
        if [ $? -ne 0 ]; then
            echo "Download failed with exit code $?"
            return 1
        fi
    fi

    # If FETCH is set to true, fetch completed torrents and place video files in the media folder
    if [ "$FETCH" = "true" ]; then
        FETCH_METHOD_ARG=""
        [ -n "$FETCH_METHOD" ] && FETCH_METHOD_ARG="--fetch-method $FETCH_METHOD"
        run_python /app/acepace.py \
            --folder "$MEDIA_DIR" \
            --fetch \
            ${FETCH_METHOD_ARG:+$FETCH_METHOD_ARG} \
            ${DRY_RUN_ARG:+$DRY_RUN_ARG} \
            ${TORRENT_CLIENT:+--client "$TORRENT_CLIENT"} \
            ${TORRENT_HOST:+--host "$TORRENT_HOST"} \
            ${TORRENT_PORT:+--port "$TORRENT_PORT"} \
            ${TORRENT_USER:+--username "$TORRENT_USER"} \
            ${TORRENT_PASSWORD:+--password "$TORRENT_PASSWORD"} \
            ${TORRENT_CATEGORY:+--category "$TORRENT_CATEGORY"}
        if [ $? -ne 0 ]; then
            echo "Fetch failed with exit code $?"
            return 1
        fi
    fi

    return 0
}

# ── Scheduling ────────────────────────────────────────────────────────────────
# SCHEDULE: interval in seconds between runs (default: 0 = run once and exit)
SCHEDULE="${SCHEDULE:-0}"

print_header

if [ "$SCHEDULE" = "0" ] || [ -z "$SCHEDULE" ]; then
    run_once
    exit $?
fi

echo "Schedule: running every ${SCHEDULE}s. Set SCHEDULE=0 to run once."
echo ""

while true; do
    RUN_START=$(date +%s)
    run_once
    RUN_END=$(date +%s)
    ELAPSED=$(( RUN_END - RUN_START ))
    WAIT=$(( SCHEDULE - ELAPSED ))

    if [ $WAIT -le 0 ]; then
        echo "Run took ${ELAPSED}s (longer than interval ${SCHEDULE}s), starting next run immediately."
    else
        NEXT=$(date -d "@$(( RUN_END + WAIT ))" "+%Y-%m-%d %H:%M:%S" 2>/dev/null \
               || date -r  "$(( RUN_END + WAIT ))" "+%Y-%m-%d %H:%M:%S" 2>/dev/null \
               || echo "in ${WAIT}s")
        echo "Next run at: ${NEXT} (sleeping ${WAIT}s)"
        sleep "$WAIT" &
        CHILD_PID=$!
        wait $CHILD_PID
        CHILD_PID=""
    fi
    echo ""
done
