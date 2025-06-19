#!/bin/bash
set -e # Exit on any error

echo "=== Starting 5.1: Markdown Document Knitting (Simulated) ==="

# Date parameters (consistent with previous phases)
YEAR="2025"
QUARTER="Q2"

# Input data files (validated outputs from Phase 4)
# These are the files the .Rmd scripts would conceptually load.
# We need their hashes to simulate the "Data Provenance for Documents" check.
PROCESSED_SMR_OUTPUT="data/processed/smr_output_${YEAR}_${QUARTER}.csv"
PROCESSED_TRENDS_OUTPUT="data/processed/trends_output_${YEAR}_${QUARTER}.csv"
OPEN_DATA_FILE="data/output/open_data_hsmr_${YEAR}_${QUARTER}.csv"
# Add other key data files if .Rmd scripts use them, e.g., Excel output for tables
EXCEL_TABLE_FILE="data/output/final_hsmr_tables_${YEAR}_${QUARTER}.xlsx"

INPUT_DATA_FILES=(
    "$PROCESSED_SMR_OUTPUT"
    "$PROCESSED_TRENDS_OUTPUT"
    "$OPEN_DATA_FILE"
    "$EXCEL_TABLE_FILE"
)

RMD_FILES=(
    "markdown/PHS-ACCREDITED-STATS-REPORT.Rmd"
    "markdown/PHS-ACCREDITED-STATS-SUMMARY.Rmd"
)

# Output directory
OUTPUT_DIR="publication_outputs"
LOG_FILE="knitting_log_${YEAR}_${QUARTER}.txt"
> "$LOG_FILE" # Clear previous log

# --- Helper function for hashing ---
generate_hash_for_file() {
  local filepath="$1"
  if [ -f "$filepath" ]; then
    sha256sum "$filepath" | awk '{print $1}' # Output hash to stdout
  else
    echo "ERROR_HASH_FILE_NOT_FOUND"
    return 1
  fi
}

# 1. Verify Hashes of Input Data (Data Provenance)
echo "[AUDIT] Verifying hashes of input data files (from Phase 4)..." | tee -a "$LOG_FILE"
all_data_hashes_verified=true
for data_file in "${INPUT_DATA_FILES[@]}"; do
    expected_hash_file="${data_file}.sha256" # Assumes Phase 4 created/updated these
    if [ ! -f "$expected_hash_file" ]; then
        echo "[ERROR] Hash file ${expected_hash_file} for input data ${data_file} not found!" | tee -a "$LOG_FILE"
        all_data_hashes_verified=false
        continue
    fi
    stored_hash=$(cat "$expected_hash_file")
    current_hash=$(generate_hash_for_file "$data_file")

    if [ "$current_hash" == "$stored_hash" ]; then
        echo "  - [PASS] Hash for ${data_file} matches." | tee -a "$LOG_FILE"
    else
        echo "  - [FAIL] Hash mismatch for ${data_file}!" | tee -a "$LOG_FILE"
        echo "    Expected: ${stored_hash}, Found: ${current_hash}" | tee -a "$LOG_FILE"
        all_data_hashes_verified=false
    fi
done

if [ "$all_data_hashes_verified" != true ]; then
    echo "[CRITICAL] Input data integrity check failed. Halting simulated knitting." | tee -a "$LOG_FILE"
    exit 1 # In a real pipeline, this would be a critical failure
fi
echo "[AUDIT] All input data hashes verified successfully." | tee -a "$LOG_FILE"


# 2. Simulate Knitting for each .Rmd file
echo -e "\n[PROCESS] Simulating R Markdown knitting..." | tee -a "$LOG_FILE"
for rmd_file in "${RMD_FILES[@]}"; do
    base_name=$(basename "$rmd_file" .Rmd)

    # Define placeholder output names (PDF is common, HTML also possible)
    output_pdf="${OUTPUT_DIR}/${base_name}_${YEAR}_${QUARTER}.pdf"
    output_html="${OUTPUT_DIR}/${base_name}_${YEAR}_${QUARTER}.html" # Example for HTML

    echo "  - Simulating knitting for: ${rmd_file}" | tee -a "$LOG_FILE"

    # Conceptual: Verify .Rmd file hash (optional)
    rmd_hash=$(generate_hash_for_file "$rmd_file")
    echo "    - Rmd file hash: $rmd_hash (for audit)" | tee -a "$LOG_FILE"
    echo "    - (Conceptually) Uses input data like: ${PROCESSED_SMR_OUTPUT}, etc." | tee -a "$LOG_FILE"

    # Simulate Rscript rmarkdown::render call
    # Rscript -e "rmarkdown::render('${rmd_file}', output_format='pdf_document', output_file='${output_pdf}')"
    # Rscript -e "rmarkdown::render('${rmd_file}', output_format='html_document', output_file='${output_html}')"

    # Create placeholder output files
    touch "$output_pdf"
    touch "$output_html"
    echo "    - Created placeholder PDF: ${output_pdf}" | tee -a "$LOG_FILE"
    echo "    - Created placeholder HTML: ${output_html}" | tee -a "$LOG_FILE"

    # Generate and log hashes for output documents
    pdf_hash=$(generate_hash_for_file "$output_pdf")
    html_hash=$(generate_hash_for_file "$output_html")
    echo "$pdf_hash" > "${output_pdf}.sha256"
    echo "$html_hash" > "${output_html}.sha256"
    echo "    - PDF Hash: ${pdf_hash} (saved to ${output_pdf}.sha256)" | tee -a "$LOG_FILE"
    echo "    - HTML Hash: ${html_hash} (saved to ${output_html}.sha256)" | tee -a "$LOG_FILE"

    echo "  - Finished simulated knitting for ${rmd_file}." | tee -a "$LOG_FILE"
done

echo -e "\n[SUMMARY] Simulated R Markdown Knitting Summary:" | tee -a "$LOG_FILE"
echo "  - Log file: ${LOG_FILE}" | tee -a "$LOG_FILE"
echo "  - Placeholder documents created in: ${OUTPUT_DIR}/" | tee -a "$LOG_FILE"
ls -l "${OUTPUT_DIR}/" | sed 's/^/    /' >> "$LOG_FILE" # Add output of ls to log

echo "=== 5.1: Markdown Document Knitting (Simulated) Complete ==="
