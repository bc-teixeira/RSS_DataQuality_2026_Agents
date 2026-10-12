#!/bin/bash
################################################################################
# RUN R SCRIPT WITH LOG MANAGEMENT
# Purpose: Execute a single R script and manage logs in 6_Logs folder
# Usage: bash .claude/scripts/run_r.sh <path_to_r_script>
# Example: bash .claude/scripts/run_r.sh 2_Code/01_Cohort.R
################################################################################

# Set strict error handling
set -e  # Exit on error
set -u  # Exit on undefined variable
set -o pipefail  # Exit on pipe failure

# Prevent duplicate logging when sourced R scripts trigger run_r.sh
# If already in an active logging session, skip to avoid duplicate logs
if [ "${RUN_R_LOGGING_ACTIVE:-}" = "1" ]; then
    # Already in a logging session - skip to prevent duplicate logs for sourced scripts
    exit 0
fi

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORKSPACE_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
LOG_DIR="${WORKSPACE_ROOT}/6_Logs"
ARCHIVE_DIR="${LOG_DIR}/archive"
TIMESTAMP=$(date +"%Y%m%d_%H%M%S")

# Validate parameter
if [ $# -eq 0 ]; then
    echo -e "${RED}[ERROR]${NC} No R script provided" >&2
    echo "Usage: bash .claude/scripts/run_r.sh <path_to_r_script>" >&2
    echo "Example: bash .claude/scripts/run_r.sh 2_Code/01_Cohort.R" >&2
    exit 1
fi

R_SCRIPT="$1"

# Validate R script exists
if [ ! -f "${R_SCRIPT}" ]; then
    echo -e "${RED}[ERROR]${NC} R script not found: ${R_SCRIPT}" >&2
    exit 1
fi

# Extract base name (without path and .R extension)
SCRIPT_BASENAME=$(basename "${R_SCRIPT}" .R)

# Create log directories if they don't exist
mkdir -p "${LOG_DIR}"
mkdir -p "${ARCHIVE_DIR}"

# Archive old logs for this script
echo -e "${BLUE}[$(date +'%H:%M:%S')]${NC} Preparing to run: ${SCRIPT_BASENAME}.R"

# Find and archive existing logs for this script
if ls "${LOG_DIR}/${SCRIPT_BASENAME}_"*.log 1> /dev/null 2>&1; then
    echo -e "${YELLOW}[ARCHIVE]${NC} Moving previous logs to archive..."
    for old_log in "${LOG_DIR}/${SCRIPT_BASENAME}_"*.log; do
        if [ -f "${old_log}" ]; then
            mv "${old_log}" "${ARCHIVE_DIR}/"
            echo "  → Archived: $(basename "${old_log}")"
        fi
    done
fi

# Define new log file
LOG_FILE="${LOG_DIR}/${SCRIPT_BASENAME}_${TIMESTAMP}.log"

# Run R script and capture output
echo -e "${BLUE}[$(date +'%H:%M:%S')]${NC} Executing: ${R_SCRIPT}"
echo "  → Log file: ${LOG_FILE}"
echo ""
echo "────────────────────────────────────────────────────────────────────────────────"

START_TIME=$(date +%s)

# Set logging guard to prevent duplicate logs for sourced scripts
export RUN_R_LOGGING_ACTIVE=1

if Rscript "${R_SCRIPT}" 2>&1 | tee "${LOG_FILE}"; then
    END_TIME=$(date +%s)
    DURATION=$((END_TIME - START_TIME))
    
    echo ""
    echo -e "${GREEN}════════════════════════════════════════════════════════════════════════════════${NC}"
    echo -e "${GREEN}✓ SUCCESS${NC}"
    echo -e "${GREEN}════════════════════════════════════════════════════════════════════════════════${NC}"
    echo ""
    echo "Script:     ${SCRIPT_BASENAME}.R"
    echo "Duration:   ${DURATION}s"
    echo "Log:        ${LOG_FILE}"
    echo ""
    echo "To view log: cat ${LOG_FILE}"
    echo ""
    exit 0
else
    END_TIME=$(date +%s)
    DURATION=$((END_TIME - START_TIME))
    
    echo ""
    echo -e "${RED}════════════════════════════════════════════════════════════════════════════════${NC}"
    echo -e "${RED}✗ FAILED${NC}"
    echo -e "${RED}════════════════════════════════════════════════════════════════════════════════${NC}"
    echo ""
    echo "Script:     ${SCRIPT_BASENAME}.R"
    echo "Duration:   ${DURATION}s"
    echo "Log:        ${LOG_FILE}"
    echo ""
    echo "Last 30 lines of error log:"
    echo "────────────────────────────────────────────────────────────────────────────────"
    tail -30 "${LOG_FILE}" | sed 's/^/  /'
    echo "────────────────────────────────────────────────────────────────────────────────"
    echo ""
    echo "Full log: cat ${LOG_FILE}"
    echo ""
    exit 1
fi
