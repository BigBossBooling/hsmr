# scripts/archive_and_stage.py

import json
import os
import shutil # For actual file operations (will be simulated with echo)
import hashlib
import sys
from datetime import datetime

def load_config(config_path="hsmr_config.json"):
    """Loads the main configuration file."""
    if not os.path.exists(config_path):
        print(f"ERROR: Configuration file not found at {config_path}")
        sys.exit(1)
    with open(config_path, 'r') as f:
        return json.load(f)

def calculate_sha256(filepath):
    """Calculates SHA256 hash of a file."""
    if not os.path.exists(filepath):
        return None
    sha256_hash = hashlib.sha256()
    with open(filepath, "rb") as f:
        for byte_block in iter(lambda: f.read(4096), b""):
            sha256_hash.update(byte_block)
    return sha256_hash.hexdigest()

def verify_hash_from_sidecar(filepath):
    """Verifies a file's hash using its .sha256 sidecar file."""
    if not os.path.exists(filepath):
        print(f"INFO: File {filepath} not found for hash verification (might be optional or not yet created).")
        return False, "File not found"

    hash_filepath = filepath + ".sha256"
    if not os.path.exists(hash_filepath):
        print(f"WARNING: Hash file {hash_filepath} not found for {filepath}. Cannot verify.")
        return False, "Hash file not found"

    with open(hash_filepath, 'r') as hf:
        expected_hash = hf.read().strip()

    calculated_hash = calculate_sha256(filepath)

    if calculated_hash == expected_hash:
        print(f"Hash VERIFIED for {filepath} (Hash: {calculated_hash})")
        return True, calculated_hash
    else:
        print(f"ERROR: Hash MISMATCH for {filepath}! Expected: {expected_hash}, Calculated: {calculated_hash}")
        return False, calculated_hash


def simulate_copy(source, destination_dir, destination_filename=None):
    """Simulates a file copy operation by printing intent."""
    if not os.path.exists(source):
        print(f"WARNING: Source file for copy not found: {source}")
        return False

    dest_name = destination_filename if destination_filename else os.path.basename(source)
    destination_path = os.path.join(destination_dir, dest_name)

    # In a real script, you'd ensure destination_dir exists:
    # print(f"DEBUG: Ensuring directory exists: {destination_dir}")
    # os.makedirs(destination_dir, exist_ok=True)
    # print(f"DEBUG: Copying {source} to {destination_path}")
    # shutil.copy2(source, destination_path) # copy2 preserves metadata

    print(f"SIMULATE COPY: '{source}' TO '{destination_path}'")
    return True


def main():
    print("Starting Output Archiving and Staging process...")
    config = load_config()

    date_params = config.get("date_parameters", {})
    pub_period = date_params.get("publication_reference_period", "unknown_period")

    paths_config = config.get("output_paths", {})
    archive_dir_template = paths_config.get("archive_dir_template", "archive/{year}/HSMR_{year}_Q{quarter}")

    archive_year = str(date_params.get("year", "YYYY"))
    archive_quarter = str(date_params.get("quarter", "Q"))
    archive_base_dir = archive_dir_template.format(year=archive_year, quarter=archive_quarter)

    tableau_staging_dir = "/mnt/tableau_staging/hsmr"

    files_to_archive = []

    files_to_archive.append({"path": "hsmr_config.json", "verify_hash": False})

    raw_data_dir = paths_config.get("raw_data_dir", "data/raw")
    if os.path.exists(raw_data_dir):
        for item in os.listdir(raw_data_dir):
            files_to_archive.append({"path": os.path.join(raw_data_dir, item), "verify_hash": True})

    processed_data_dir = paths_config.get("processed_data_dir", "data/processed")
    if os.path.exists(processed_data_dir):
        for item in os.listdir(processed_data_dir):
            files_to_archive.append({"path": os.path.join(processed_data_dir, item), "verify_hash": True})

    final_output_dir = paths_config.get("final_output_dir", "data/output")
    tableau_source_candidates = []
    if os.path.exists(final_output_dir):
        for item in os.listdir(final_output_dir):
            full_item_path = os.path.join(final_output_dir, item)
            files_to_archive.append({"path": full_item_path, "verify_hash": True})
            # For simulation, let's assume the main "Excel" (simulated CSV) and open data are for Tableau
            if item.startswith("final_hsmr_tables_") and item.endswith(".xlsx"): # .xlsx as per R script output name
                 tableau_source_candidates.append({
                     "path": full_item_path,
                     "tableau_staging_name": f"hsmr_summary_tables_{pub_period}.csv" # Output as CSV
                 })
            if item.startswith("open_data_hsmr_") and item.endswith(".csv"): # if open_data script creates this
                 tableau_source_candidates.append({
                     "path": full_item_path,
                     "tableau_staging_name": f"hsmr_open_data_{pub_period}.csv"
                 })


    publication_outputs_dir = paths_config.get("publication_outputs_dir", "publication_outputs")
    if os.path.exists(publication_outputs_dir):
        for item in os.listdir(publication_outputs_dir):
            files_to_archive.append({"path": os.path.join(publication_outputs_dir, item), "verify_hash": True})

    qa_reports = ["schema_validation_report.json", "data_rules_validation_report.json", "anomaly_detection_report.json"]
    for report_name in qa_reports:
        if os.path.exists(report_name):
            files_to_archive.append({"path": report_name, "verify_hash": False})

    rmd_dir = "markdown"
    if os.path.exists(rmd_dir):
        for item in os.listdir(rmd_dir):
            if item.endswith(".Rmd"):
                 files_to_archive.append({"path": os.path.join(rmd_dir, item), "verify_hash": False})

    print(f"\n--- SIMULATING ARCHIVAL TO: {archive_base_dir} ---")
    print(f"(Conceptual: os.makedirs(\"{archive_base_dir}\", exist_ok=True) would be called here)")
    archive_manifest = []
    critical_hash_failure_archival = False
    for file_spec in files_to_archive:
        source_path = file_spec["path"]
        should_verify_hash = file_spec.get("verify_hash", False)

        if not os.path.exists(source_path):
            print(f"INFO: Source file for archive not found (might be optional or not generated): {source_path}")
            continue

        is_verified_status = "not_checked"
        if should_verify_hash and not source_path.endswith(".sha256"):
            verified, _ = verify_hash_from_sidecar(source_path)
            is_verified_status = "VERIFIED" if verified else "VERIFICATION_FAILED"
            if not verified:
                print(f"CRITICAL WARNING: Hash verification failed for {source_path} during archival. Archiving flagged.")
                critical_hash_failure_archival = True

        if simulate_copy(source_path, archive_base_dir):
            archive_manifest.append({"source": source_path, "archived_to": os.path.join(archive_base_dir, os.path.basename(source_path)), "hash_status": is_verified_status})

    manifest_filename = f"archive_manifest_{pub_period}.json"
    manifest_path = os.path.join(archive_base_dir, manifest_filename)
    print(f"SIMULATE WRITE: Archive manifest to '{manifest_path}' with {len(archive_manifest)} entries.")
    # with open(manifest_path, 'w') as f_manifest:
    #    json.dump(archive_manifest, f_manifest, indent=4)
    # print(f"DEBUG: Also simulate copy of manifest itself for completeness in logs if needed")
    # simulate_copy(manifest_path, archive_base_dir) # Not really, it's already "in" archive_base_dir

    if critical_hash_failure_archival:
        print("WARNING: One or more files failed hash verification during archival process. Check logs.")


    print(f"\n--- SIMULATING STAGING TO TABLEAU: {tableau_staging_dir} ---")
    print(f"(Conceptual: os.makedirs(\"{tableau_staging_dir}\", exist_ok=True) would be called here)")
    staged_for_tableau_count = 0
    for candidate in tableau_source_candidates:
        source_path = candidate["path"]
        tableau_filename = candidate["tableau_staging_name"]

        if not os.path.exists(source_path):
            print(f"WARNING: Source file for Tableau staging not found: {source_path}")
            continue

        verified, _ = verify_hash_from_sidecar(source_path)
        if not verified:
            print(f"CRITICAL WARNING: Hash verification failed for {source_path}. SKIPPING Tableau staging for this file.")
            continue

        if simulate_copy(source_path, tableau_staging_dir, destination_filename=tableau_filename):
            staged_for_tableau_count +=1

    if staged_for_tableau_count == 0:
        print("No files were identified or successfully staged for Tableau based on current config/data and hash checks.")
    else:
        print(f"{staged_for_tableau_count} file(s) conceptually staged for Tableau.")

    print("\nOutput Archiving and Staging process completed (simulated).")

if __name__ == "__main__":
    main()
