#!/bin/bash
set -e # Exit on any error

# Function for timestamped logging
log_message() {
    local type="$1" # e.g., INFO, ERROR, USER_ACTION_REQUIRED
    local message="$2"
    echo "[$(date +'%Y-%m-%dT%H:%M:%SZ')] [${type}] ${message}" | tee -a "${PHASE5_LOG_FILE}"
}

YEAR="2025" # Ensure consistent year/quarter
QUARTER="Q2"
PHASE5_LOG_FILE="phase5_main_log_${YEAR}_${QUARTER}.txt"
# Clear previous log, but first log that we are starting
echo "[$(date +'%Y-%m-%dT%H:%M:%SZ')] [SYSTEM] Initializing Phase 5 log file: ${PHASE5_LOG_FILE}" > "${PHASE5_LOG_FILE}"


log_message "SYSTEM" "========= Starting Phase 5: Publication Document Generation & Finalization (Simulated) ========="

# --- 5.1 Markdown Document Knitting (Simulated) ---
log_message "INFO" "Executing 5.1 Markdown Document Knitting (Simulated)..."
chmod +x simulate_rmd_knitting.sh # Ensure executable
# Capture stdout and stderr, append to main log, and also display to console
./simulate_rmd_knitting.sh >> "${PHASE5_LOG_FILE}" 2>&1
if [ ${PIPESTATUS[0]} -ne 0 ]; then # PIPESTATUS[0] gets exit code of first command in pipe if tee is used, or just $? if not.
    log_message "CRITICAL_ERROR" "simulate_rmd_knitting.sh failed. Halting Phase 5."
    exit 1
fi
log_message "INFO" "5.1 Markdown Document Knitting (Simulated) completed."
log_message "INFO" "---------------------------------------------------------------------"


# --- 5.2 Manual Finalization Reporting ---
log_message "INFO" "Starting 5.2 Manual Finalization Reporting..."

REPORT_PDF="publication_outputs/PHS-ACCREDITED-STATS-REPORT_${YEAR}_${QUARTER}.pdf"
SUMMARY_PDF="publication_outputs/PHS-ACCREDITED-STATS-SUMMARY_${YEAR}_${QUARTER}.pdf"
REPORT_HTML="publication_outputs/PHS-ACCREDITED-STATS-REPORT_${YEAR}_${QUARTER}.html"
SUMMARY_HTML="publication_outputs/PHS-ACCREDITED-STATS-SUMMARY_${YEAR}_${QUARTER}.html"

log_message "USER_ACTION_REQUIRED" "The following documents have been generated (as placeholders):"
log_message "USER_ACTION_REQUIRED" "  - Main Report PDF: ${REPORT_PDF} (Hash: $(cat ${REPORT_PDF}.sha256 2>/dev/null || echo N/A))"
log_message "USER_ACTION_REQUIRED" "  - Main Report HTML: ${REPORT_HTML} (Hash: $(cat ${REPORT_HTML}.sha256 2>/dev/null || echo N/A))"
log_message "USER_ACTION_REQUIRED" "  - Summary PDF: ${SUMMARY_PDF} (Hash: $(cat ${SUMMARY_PDF}.sha256 2>/dev/null || echo N/A))"
log_message "USER_ACTION_REQUIRED" "  - Summary HTML: ${SUMMARY_HTML} (Hash: $(cat ${SUMMARY_HTML}.sha256 2>/dev/null || echo N/A))"
echo "" | tee -a "${PHASE5_LOG_FILE}" # Keep one direct echo for spacing in console, also logged
log_message "USER_ACTION_REQUIRED" "Please perform the following MANUAL finalization steps based on 'National Statistics Publication Templates repository readme':"
log_message "USER_ACTION_REQUIRED" "  1. Add official PHS cover page to PDF documents."
log_message "USER_ACTION_REQUIRED" "  2. Verify/regenerate Table of Contents for PDF documents."
log_message "USER_ACTION_REQUIRED" "  3. Review all tables and charts for correct formatting and accessibility."
log_message "USER_ACTION_REQUIRED" "  4. Check for consistent branding and statistical disclosure control."
log_message "USER_ACTION_REQUIRED" "  5. Perform a final read-through for clarity, grammar, and any textual errors."
log_message "USER_ACTION_REQUIRED" "  6. Confirm all links in HTML documents are working."
echo "" | tee -a "${PHASE5_LOG_FILE}"
log_message "INFO" "For this simulation, we assume manual steps are noted and will be handled outside the script."
log_message "INFO" "In a more advanced workflow, the pipeline might pause here for explicit human confirmation."
log_message "INFO" "5.2 Manual Finalization Reporting completed."
log_message "INFO" "---------------------------------------------------------------------"


# --- 5.3 Output Archiving & Distribution Preparation (Simulated) ---
log_message "INFO" "Executing 5.3 Output Archiving & Distribution Preparation (Simulated)..."
chmod +x archive_and_stage_outputs.sh # Ensure executable
./archive_and_stage_outputs.sh >> "${PHASE5_LOG_FILE}" 2>&1
if [ ${PIPESTATUS[0]} -ne 0 ]; then
    log_message "CRITICAL_ERROR" "archive_and_stage_outputs.sh failed. Halting Phase 5."
    exit 1
fi
log_message "INFO" "5.3 Output Archiving & Distribution Preparation (Simulated) completed."
log_message "INFO" "---------------------------------------------------------------------"

log_message "SYSTEM" "========= Phase 5: Publication Document Generation & Finalization (Simulated) Complete ========="
log_message "SYSTEM" "Main log for Phase 5: ${PHASE5_LOG_FILE}"
# Display final log location to console without timestamp/type from function
echo "Final Phase 5 log is available at: ${PHASE5_LOG_FILE}"
