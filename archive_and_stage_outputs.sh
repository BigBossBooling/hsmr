#!/bin/bash
set -e # Exit on any error

echo "=== Starting 5.3: Output Archiving & Distribution Preparation (Simulated) ==="

# Date parameters
YEAR="2025"
QUARTER="Q2"

# --- Define conceptual paths ---
# These would be configured externally in a real system (e.g., hsmr_config.json)
ARCHIVE_BASE_DIR="/mnt/hsmr_archive" # Conceptual
TABLEAU_STAGING_DIR="/mnt/tableau_staging/hsmr" # Conceptual

# Create a specific archive directory for this publication run
CURRENT_ARCHIVE_DIR="${ARCHIVE_BASE_DIR}/${YEAR}/HSMR_${YEAR}_${QUARTER}"
echo "[SETUP] Conceptual archive directory for this run: ${CURRENT_ARCHIVE_DIR}"
echo "        (Simulating mkdir -p ${CURRENT_ARCHIVE_DIR})"

echo "[SETUP] Conceptual Tableau staging directory: ${TABLEAU_STAGING_DIR}"
echo "        (Simulating mkdir -p ${TABLEAU_STAGING_DIR})"


# --- Files to Archive/Stage ---
# Publication Documents (from publication_outputs/)
# Assuming PDF is the primary format for archive, HTML for web if used
REPORT_PDF="publication_outputs/PHS-ACCREDITED-STATS-REPORT_${YEAR}_${QUARTER}.pdf"
REPORT_HTML="publication_outputs/PHS-ACCREDITED-STATS-REPORT_${YEAR}_${QUARTER}.html"
SUMMARY_PDF="publication_outputs/PHS-ACCREDITED-STATS-SUMMARY_${YEAR}_${QUARTER}.pdf"
SUMMARY_HTML="publication_outputs/PHS-ACCREDITED-STATS-SUMMARY_${YEAR}_${QUARTER}.html"

# Key Data Outputs (validated versions from Phase 4)
# These are the files whose hashes were checked before knitting
SMR_OUTPUT_DATA="data/processed/smr_output_${YEAR}_${QUARTER}.csv"
TRENDS_OUTPUT_DATA="data/processed/trends_output_${YEAR}_${QUARTER}.csv"
OPEN_DATA_OUTPUT="data/output/open_data_hsmr_${YEAR}_${QUARTER}.csv" # For public use
EXCEL_TABLES_OUTPUT="data/output/final_hsmr_tables_${YEAR}_${QUARTER}.xlsx" # Can be for archive & review

# Source .Rmd files and other critical logs/reports
RMD_REPORT_FILE="markdown/PHS-ACCREDITED-STATS-REPORT.Rmd"
RMD_SUMMARY_FILE="markdown/PHS-ACCREDITED-STATS-SUMMARY.Rmd"
VALIDATION_REPORT_PH4="validation_summary_report_${YEAR}_${QUARTER}.txt" # From Phase 4
KNITTING_LOG_PH5_1="knitting_log_${YEAR}_${QUARTER}.txt" # From step 5.1

FILES_FOR_ARCHIVE=(
    "$REPORT_PDF" "$REPORT_PDF.sha256"
    "$REPORT_HTML" "$REPORT_HTML.sha256"
    "$SUMMARY_PDF" "$SUMMARY_PDF.sha256"
    "$SUMMARY_HTML" "$SUMMARY_HTML.sha256"
    "$SMR_OUTPUT_DATA" "$SMR_OUTPUT_DATA.sha256"
    "$TRENDS_OUTPUT_DATA" "$TRENDS_OUTPUT_DATA.sha256"
    "$OPEN_DATA_OUTPUT" "$OPEN_DATA_OUTPUT.sha256"
    "$EXCEL_TABLES_OUTPUT" "$EXCEL_TABLES_OUTPUT.sha256"
    "$RMD_REPORT_FILE" # Archive the source Rmds
    "$RMD_SUMMARY_FILE"
    "$VALIDATION_REPORT_PH4"
    "$KNITTING_LOG_PH5_1"
    # Also include:
    # - run_phase3_analysis.sh output log
    # - run_phase4_validation.sh output log (which is VALIDATION_REPORT_PH4)
    # - Hashes of the .Rmd files themselves (could be generated here or taken from knitting_log)
)

# Files specifically for Tableau staging (usually a subset, often just data)
FILES_FOR_TABLEAU=(
    "$OPEN_DATA_OUTPUT" # Open data is a good candidate for Tableau
    # Potentially other specific CSVs if Tableau dashboards are built on them
    # For example, if Tableau uses the main SMR output:
    # "$SMR_OUTPUT_DATA"
)

# --- Helper function for hash verification ---
verify_file_hash() {
    local file_to_check="$1"
    local hash_file="${file_to_check}.sha256"

    if [ ! -f "$file_to_check" ]; then
        echo "[ERROR] File to archive/stage not found: $file_to_check"
        return 1
    fi
    if [ ! -f "$hash_file" ]; then
        echo "[WARN] Hash file not found for ${file_to_check}. Cannot verify integrity before archiving."
        # In a strict mode, this could be a failure: return 1
        return 0 # For simulation, allow proceeding with a warning
    fi

    current_hash=$(sha256sum "$file_to_check" | awk '{print $1}')
    stored_hash=$(cat "$hash_file")

    if [ "$current_hash" == "$stored_hash" ]; then
        echo "  - [PASS] Hash verified for ${file_to_check}."
        return 0
    else
        echo "  - [FAIL] Hash MISMTACH for ${file_to_check} before archiving! Expected ${stored_hash}, got ${current_hash}."
        return 1 # Critical error
    fi
}


# 1. Archive Files
echo -e "\n[PROCESS] Archiving files to ${CURRENT_ARCHIVE_DIR} (Simulated)..."
for item in "${FILES_FOR_ARCHIVE[@]}"; do
    # Skip .sha256 files in the main loop if we are verifying the primary file against its .sha256
    [[ "$item" == *.sha256 ]] && continue

    echo "Preparing to archive: $item"
    if verify_file_hash "$item"; then
        echo "  (Simulating) cp \"$item\" \"${CURRENT_ARCHIVE_DIR}/\""
        # Also copy its hash file if it exists
        if [ -f "${item}.sha256" ]; then
            echo "  (Simulating) cp \"${item}.sha256\" \"${CURRENT_ARCHIVE_DIR}/\""
        fi
    else
        echo "[CRITICAL] Halting archive due to hash mismatch or missing file for $item."
        exit 1
    fi
done
echo "[SUCCESS] All specified files (conceptually) archived."


# 2. Stage Files for Tableau
echo -e "\n[PROCESS] Staging files for Tableau at ${TABLEAU_STAGING_DIR} (Simulated)..."
for item in "${FILES_FOR_TABLEAU[@]}";
do
    echo "Preparing to stage for Tableau: $item"
    if verify_file_hash "$item"; then
        # Tableau files might need specific naming conventions including date
        tableau_filename=$(basename "$item" .csv)_${YEAR}_${QUARTER}.csv # Example renaming
        echo "  (Simulating) cp \"$item\" \"${TABLEAU_STAGING_DIR}/${tableau_filename}\""
        # Hash for Tableau file also? Optional, depends on Tableau process.
        # echo "  (Simulating) Hash for Tableau file: $(sha256sum $item | awk '{print $1}')"
    else
        echo "[CRITICAL] Halting Tableau staging due to hash mismatch or missing file for $item."
        exit 1
    fi
done
echo "[SUCCESS] All specified files (conceptually) staged for Tableau."

echo -e "\n=== 5.3: Output Archiving & Distribution Preparation (Simulated) Complete ==="
