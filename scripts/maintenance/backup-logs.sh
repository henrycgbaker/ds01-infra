#!/bin/bash
# /opt/ds01-infra/scripts/maintenance/backup-logs.sh
# DS01 Log Backup and Archive Script
#
# Archives old logs and manages retention.
#
# Usage:
#   backup-logs.sh                    # Archive logs older than 30 days
#   backup-logs.sh --clean            # Remove archives older than 1 year
#   backup-logs.sh --verify           # Verify archive integrity
#   backup-logs.sh --status           # Show archive status

set -e

# Configuration
LOG_DIR="/var/log/ds01"
ARCHIVE_DIR="/var/lib/ds01/log-archives"
RETENTION_DAYS=${DS01_LOG_RETENTION_DAYS:-30}
ARCHIVE_RETENTION_DAYS=${DS01_ARCHIVE_RETENTION_DAYS:-365}

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1"; }
log_success() { echo -e "${GREEN}[OK]${NC} $1"; }
log_warning() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

# Ensure directories exist
mkdir -p "$ARCHIVE_DIR"
mkdir -p "$LOG_DIR"

# Archive old logs
archive_logs() {
    log "Starting log archive (retention: ${RETENTION_DAYS} days)"

    local archived_count=0
    local archive_date=$(date +%Y%m%d)
    local archive_file="$ARCHIVE_DIR/ds01-logs-${archive_date}.tar.gz"

    # Find logs older than retention period
    local old_logs=$(find "$LOG_DIR" -name "*.log.*" -o -name "*.jsonl.*" -mtime +${RETENTION_DAYS} 2>/dev/null || true)

    if [ -z "$old_logs" ]; then
        log "No logs older than ${RETENTION_DAYS} days to archive"
        return 0
    fi

    # Create temporary list of files to archive
    local file_list=$(mktemp)
    echo "$old_logs" > "$file_list"

    # Create archive
    if tar -czf "$archive_file" -T "$file_list" 2>/dev/null; then
        archived_count=$(wc -l < "$file_list")
        log_success "Created archive: $archive_file ($archived_count files)"

        # Verify archive
        if tar -tzf "$archive_file" >/dev/null 2>&1; then
            # Remove archived files
            while IFS= read -r file; do
                rm -f "$file" && log "Removed: $file"
            done < "$file_list"
        else
            log_error "Archive verification failed! Not removing original files."
            rm -f "$archive_file"
        fi
    else
        log_error "Failed to create archive"
    fi

    rm -f "$file_list"

    log "Archive complete: $archived_count files archived"
}

# Clean old archives
clean_archives() {
    log "Cleaning archives older than ${ARCHIVE_RETENTION_DAYS} days"

    local removed_count=0
    local old_archives=$(find "$ARCHIVE_DIR" -name "ds01-logs-*.tar.gz" -mtime +${ARCHIVE_RETENTION_DAYS} 2>/dev/null || true)

    if [ -z "$old_archives" ]; then
        log "No archives older than ${ARCHIVE_RETENTION_DAYS} days"
        return 0
    fi

    while IFS= read -r archive; do
        if rm -f "$archive"; then
            log "Removed old archive: $archive"
            ((removed_count++))
        fi
    done <<< "$old_archives"

    log_success "Removed $removed_count old archive(s)"
}

# Verify archives
verify_archives() {
    log "Verifying archive integrity"

    local total=0
    local valid=0
    local invalid=0

    for archive in "$ARCHIVE_DIR"/ds01-logs-*.tar.gz; do
        [ -f "$archive" ] || continue
        ((total++))

        if tar -tzf "$archive" >/dev/null 2>&1; then
            log_success "$(basename "$archive") - OK"
            ((valid++))
        else
            log_error "$(basename "$archive") - CORRUPTED"
            ((invalid++))
        fi
    done

    echo ""
    echo "Archive Verification Summary"
    echo "============================"
    echo "Total:   $total"
    echo -e "Valid:   ${GREEN}$valid${NC}"
    echo -e "Invalid: ${RED}$invalid${NC}"

    [ $invalid -eq 0 ] && return 0 || return 1
}

# Show status
show_status() {
    echo "DS01 Log Archive Status"
    echo "======================="
    echo ""

    echo "Log Directory: $LOG_DIR"
    if [ -d "$LOG_DIR" ]; then
        local log_size=$(du -sh "$LOG_DIR" 2>/dev/null | cut -f1)
        local log_count=$(find "$LOG_DIR" -type f 2>/dev/null | wc -l)
        echo "  Size: $log_size"
        echo "  Files: $log_count"
    else
        echo "  (directory does not exist)"
    fi

    echo ""
    echo "Archive Directory: $ARCHIVE_DIR"
    if [ -d "$ARCHIVE_DIR" ]; then
        local archive_size=$(du -sh "$ARCHIVE_DIR" 2>/dev/null | cut -f1)
        local archive_count=$(find "$ARCHIVE_DIR" -name "*.tar.gz" 2>/dev/null | wc -l)
        echo "  Size: $archive_size"
        echo "  Archives: $archive_count"

        if [ $archive_count -gt 0 ]; then
            echo ""
            echo "Recent Archives:"
            ls -lh "$ARCHIVE_DIR"/*.tar.gz 2>/dev/null | tail -5 | awk '{print "  " $9 " (" $5 ")"}'
        fi
    else
        echo "  (directory does not exist)"
    fi

    echo ""
    echo "Configuration:"
    echo "  Log Retention: ${RETENTION_DAYS} days"
    echo "  Archive Retention: ${ARCHIVE_RETENTION_DAYS} days"
}

# Main
case "${1:-}" in
    --clean)
        clean_archives
        ;;
    --verify)
        verify_archives
        ;;
    --status)
        show_status
        ;;
    --help|-h)
        echo "Usage: $0 [--clean|--verify|--status]"
        echo ""
        echo "Options:"
        echo "  (no args)  Archive logs older than ${RETENTION_DAYS} days"
        echo "  --clean    Remove archives older than ${ARCHIVE_RETENTION_DAYS} days"
        echo "  --verify   Verify archive integrity"
        echo "  --status   Show archive status"
        echo ""
        echo "Environment Variables:"
        echo "  DS01_LOG_RETENTION_DAYS     Days to keep logs (default: 30)"
        echo "  DS01_ARCHIVE_RETENTION_DAYS Days to keep archives (default: 365)"
        ;;
    *)
        archive_logs
        ;;
esac
