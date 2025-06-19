# scripts/archive_and_stage.py

import json
import os
import hashlib
import sys
from datetime import datetime
import logging

# --- Configure Python Logging ---
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(levelname)s - %(filename)s:%(lineno)d - %(message)s',
    stream=sys.stdout # Log to stdout, GHA will capture it
)
logger = logging.getLogger(__name__)

try:
    import boto3
    from botocore.exceptions import ClientError, NoCredentialsError, PartialCredentialsError
    BOTO3_AVAILABLE = True
    logger.info("boto3 library found and imported.")
except ImportError:
    BOTO3_AVAILABLE = False
    logger.warning("Python library 'boto3' not found. AWS S3 operations will be fully simulated with print statements only.")


def load_config(config_path="hsmr_config.json"):
    """Loads the main configuration file."""
    if not os.path.exists(config_path):
        logger.error(f"Configuration file not found at {config_path}")
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
        logger.info(f"File {filepath} not found for hash verification (might be optional or not yet created).")
        return False, "File not found", None

    hash_filepath = filepath + ".sha256"
    if not os.path.exists(hash_filepath):
        logger.warning(f"Hash file {hash_filepath} not found for {filepath}. Cannot verify integrity.")
        return False, "Hash file not found", None # Treat as unverified if hash file is missing

    with open(hash_filepath, 'r') as hf:
        expected_hash = hf.read().strip()

    calculated_hash = calculate_sha256(filepath)

    if calculated_hash == expected_hash:
        logger.info(f"Hash VERIFIED for {filepath} (Hash: {calculated_hash})")
        return True, calculated_hash, expected_hash
    else:
        logger.error(f"Hash MISMATCH for {filepath}! Expected: {expected_hash}, Calculated: {calculated_hash}")
        return False, calculated_hash, expected_hash

def upload_to_s3(s3_client, local_filepath, bucket_name, s3_object_key):
    """Uploads a file to S3."""
    if not BOTO3_AVAILABLE:
        logger.critical(f"FATAL_ERROR_SDK: Attempted S3 upload for {local_filepath} but boto3 is not available.")
        return False

    if not os.path.exists(local_filepath):
        logger.error(f"Source file for S3 upload not found: {local_filepath}")
        return False
    try:
        logger.info(f"Attempting to UPLOAD '{local_filepath}' TO S3 bucket '{bucket_name}' key '{s3_object_key}'")
        s3_client.upload_file(local_filepath, bucket_name, s3_object_key)
        logger.info(f"Successfully UPLOADED '{local_filepath}' TO S3://{bucket_name}/{s3_object_key}")
        return True
    except FileNotFoundError:
        logger.error(f"Local file not found for S3 upload during call: {local_filepath}")
    except NoCredentialsError:
        logger.error("AWS S3 credentials not found. Ensure GHA runner is configured with AWS credentials (e.g., via IAM role or actions/configure-aws-credentials).")
    except PartialCredentialsError:
        logger.error("Incomplete AWS S3 credentials found.")
    except ClientError as e:
        error_code = e.response.get("Error", {}).get("Code", "Unknown")
        logger.error(f"S3 ClientError uploading to S3 (Bucket: {bucket_name}, Key: {s3_object_key}). AWS Error Code: {error_code}. Message: {e}")
    except Exception as e:
        logger.error(f"UNEXPECTED ERROR during S3 upload of {local_filepath}: {e}")
    return False


def main():
    logger.info("Starting Output Archiving and Staging process (Production Mode - S3 Example)...")
    config = load_config()

    aws_s3_archive_bucket = os.getenv("HSMR_S3_ARCHIVE_BUCKET")
    aws_s3_tableau_bucket = os.getenv("HSMR_S3_TABLEAU_BUCKET")
    aws_region = os.getenv("AWS_DEFAULT_REGION", "eu-west-2")

    s3_client = None
    if BOTO3_AVAILABLE and (aws_s3_archive_bucket or aws_s3_tableau_bucket):
        try:
            s3_client = boto3.client("s3", region_name=aws_region)
            logger.info(f"AWS S3 client initialized for region {aws_region}.")
        except Exception as e:
            logger.error(f"Failed to initialize AWS S3 client: {e}. Archiving/Staging to S3 will be skipped.")
            s3_client = None
    elif not BOTO3_AVAILABLE and (aws_s3_archive_bucket or aws_s3_tableau_bucket):
        logger.warning("S3 bucket(s) configured, but boto3 library is not available. S3 operations will be simulated.")
    else:
        logger.info("No S3 buckets configured or boto3 not available. S3 operations will be simulated with local prints/copies.")

    date_params = config.get("date_parameters", {})
    pub_period = date_params.get("publication_reference_period", "unknown_period")
    if pub_period == "unknown_period":
        logger.critical("publication_reference_period not found in config. Cannot proceed.")
        sys.exit(1)

    archive_year = str(date_params.get("year", "YYYY"))
    archive_quarter_num = str(date_params.get("quarter", "Q"))

    paths_config = config.get("output_paths", {})
    archive_dir_template = paths_config.get("archive_dir_template", "archive/{year}/HSMR_{year}_Q{quarter}")
    s3_archive_base_prefix = archive_dir_template.format(year=archive_year, quarter=archive_quarter_num).replace("\\","/")

    s3_tableau_staging_prefix = f"tableau_staging/hsmr/{pub_period}/".replace("\\","/")

    files_to_archive_specs = []
    files_to_archive_specs.append({"path": "hsmr_config.json", "verify_hash": False, "s3_key_override": "hsmr_config.json", "s3_subdir": ""})

    def gather_files_from_dir(dir_path_key, default_dir, s3_subdir_name, period_filter_str):
        specs = []
        actual_dir = paths_config.get(dir_path_key, default_dir)
        if os.path.exists(actual_dir):
            for item in os.listdir(actual_dir):
                if period_filter_str in item:
                    specs.append({"path": os.path.join(actual_dir, item),
                                  "verify_hash": True,
                                  "s3_subdir": s3_subdir_name})
        else:
            logger.info(f"Directory for '{dir_path_key}' not found, skipping: {actual_dir}")
        return specs

    files_to_archive_specs.extend(gather_files_from_dir("raw_data_dir", "data/raw", "raw_data", pub_period))
    files_to_archive_specs.extend(gather_files_from_dir("processed_data_dir", "data/processed", "processed_data", pub_period))

    final_output_dir = paths_config.get("final_output_dir", "data/output")
    tableau_source_candidates = []
    if os.path.exists(final_output_dir):
        for item in os.listdir(final_output_dir):
            if pub_period in item:
                full_item_path = os.path.join(final_output_dir, item)
                files_to_archive_specs.append({"path": full_item_path, "verify_hash": True, "s3_subdir": "final_output_tables"})
                if item.startswith("final_hsmr_tables_") and item.endswith(".xlsx"):
                     tableau_source_candidates.append({
                         "path": full_item_path,
                         "tableau_s3_key": os.path.join(s3_tableau_staging_prefix, f"hsmr_summary_tables_{pub_period}.xlsx")
                     })
                if item.startswith("open_data_hsmr_") and item.endswith(".csv"):
                     tableau_source_candidates.append({
                         "path": full_item_path,
                         "tableau_s3_key": os.path.join(s3_tableau_staging_prefix, f"hsmr_open_data_{pub_period}.csv")
                     })
    else:
        logger.info(f"Final output directory not found, skipping: {final_output_dir}")

    publication_outputs_dir = paths_config.get("publication_outputs_dir", "publication_outputs")
    if os.path.exists(publication_outputs_dir):
        for item in os.listdir(publication_outputs_dir):
            if pub_period in item or "MANUAL_FINALIZATION_CHECKLIST" in item.upper() and pub_period in item.upper() :
                 files_to_archive_specs.append({"path": os.path.join(publication_outputs_dir, item), "verify_hash": True, "s3_subdir": "publication_documents"})
    else:
        logger.info(f"Publication outputs directory not found, skipping: {publication_outputs_dir}")

    qa_reports = ["schema_validation_report.json", "data_rules_validation_report.json", "anomaly_detection_report.json"]
    for report_name in qa_reports:
        if os.path.exists(report_name): files_to_archive_specs.append({"path": report_name, "verify_hash": False, "s3_subdir": "qa_reports"})

    rmd_dir = "markdown"
    if os.path.exists(rmd_dir):
        for item in os.listdir(rmd_dir):
            if item.endswith(".Rmd"): files_to_archive_specs.append({"path": os.path.join(rmd_dir, item), "verify_hash": False, "s3_subdir": "source_rmds"})

    logger.info(f"--- ARCHIVING OUTPUTS (Target S3 Bucket: {aws_s3_archive_bucket or 'Not Configured'}) ---")
    archive_manifest_entries = []
    any_critical_archival_failure = False
    any_hash_mismatch_in_archive_candidates = False
    local_simulation_archive_base = "temp_archive_dir"

    for file_spec in files_to_archive_specs:
        source_path = file_spec["path"]
        if not os.path.exists(source_path):
            logger.info(f"Source file for archive not found (optional or not generated this run): {source_path}")
            continue

        is_verified_status = "not_applicable"
        hash_verification_passed = True
        if file_spec.get("verify_hash", False) and not source_path.endswith(".sha256"):
            verified, _, _ = verify_hash_from_sidecar(source_path)
            is_verified_status = "VERIFIED" if verified else "VERIFICATION_FAILED"
            if not verified:
                hash_verification_passed = False
                any_hash_mismatch_in_archive_candidates = True
                logger.warning(f"Hash verification FAILED for {source_path} prior to archival attempt. This item is flagged.")

        s3_key_filename = file_spec.get("s3_key_override", os.path.basename(source_path))
        s3_subdir_path = file_spec.get("s3_subdir", "")
        s3_object_key_parts = [s3_archive_base_prefix.strip('/')] # Ensure base is clean
        if s3_subdir_path: s3_object_key_parts.append(s3_subdir_path.strip('/'))
        s3_object_key_parts.append(s3_key_filename.strip('/'))
        s3_object_key = "/".join(s3_object_key_parts) # Use forward slashes for S3 keys

        upload_this_file = True
        if not hash_verification_passed and not source_path.endswith(".sha256"): # Policy for critical files
             # For this example, we will still attempt to archive flagged files but note it.
             # A stricter policy might be: upload_this_file = False; any_critical_archival_failure = True
             logger.warning(f"Proceeding to archive {source_path} despite hash verification failure (as per current policy).")


        if upload_this_file:
            if s3_client and aws_s3_archive_bucket:
                if upload_to_s3(s3_client, source_path, aws_s3_archive_bucket, s3_object_key):
                    archive_manifest_entries.append({"source": source_path, "archived_to": f"s3://{aws_s3_archive_bucket}/{s3_object_key}", "hash_status": is_verified_status, "upload_status": "SUCCESS"})
                else:
                    any_critical_archival_failure = True # Failed S3 upload is critical for main archive
                    archive_manifest_entries.append({"source": source_path, "archived_to": f"s3://{aws_s3_archive_bucket}/{s3_object_key}", "hash_status": is_verified_status, "upload_status": "FAILED"})
            else:
                archive_target_dir_sim = os.path.join(local_simulation_archive_base, os.path.dirname(s3_object_key))
                if not os.path.exists(archive_target_dir_sim): os.makedirs(archive_target_dir_sim, exist_ok=True)
                logger.info(f"SIMULATE COPY (S3 fallback): '{source_path}' TO '{os.path.join(archive_target_dir_sim, os.path.basename(s3_object_key))}'")
                archive_manifest_entries.append({"source": source_path, "archived_to_simulated_s3_key": s3_object_key, "hash_status": is_verified_status, "upload_status": "SIMULATED"})

    local_manifest_filename = f"archive_manifest_{pub_period}.json"
    with open(local_manifest_filename, 'w') as f_manifest:
        json.dump(archive_manifest_entries, f_manifest, indent=4)
    logger.info(f"Archive manifest written locally to: {local_manifest_filename} with {len(archive_manifest_entries)} entries.")

    if os.path.exists(local_manifest_filename):
        manifest_s3_key_parts = [s3_archive_base_prefix.strip('/'), local_manifest_filename]
        manifest_s3_key = "/".join(manifest_s3_key_parts)
        if s3_client and aws_s3_archive_bucket:
            if upload_to_s3(s3_client, local_manifest_filename, aws_s3_archive_bucket, manifest_s3_key):
                logger.info(f"Archive manifest also uploaded to S3: s3://{aws_s3_archive_bucket}/{manifest_s3_key}")
            else:
                logger.error(f"Failed to upload archive manifest {local_manifest_filename} to S3.")
                any_critical_archival_failure = True # Manifest is critical
        else:
            archive_target_dir_sim_manifest = os.path.join(local_simulation_archive_base, os.path.dirname(manifest_s3_key))
            if not os.path.exists(archive_target_dir_sim_manifest): os.makedirs(archive_target_dir_sim_manifest, exist_ok=True)
            logger.info(f"SIMULATE COPY (S3 fallback for manifest): '{local_manifest_filename}' TO '{os.path.join(archive_target_dir_sim_manifest, os.path.basename(manifest_s3_key))}'")

    if any_hash_mismatch_in_archive_candidates: # This is now a post-facto warning
        logger.warning("One or more files had hash mismatches prior to archival attempt. Their upload status is in the manifest.")

    logger.info(f"--- STAGING TO TABLEAU (Target S3 Bucket/Prefix: {aws_s3_tableau_bucket or 'Not Configured'}) ---")
    staged_for_tableau_count = 0
    any_tableau_staging_failure = False
    local_tableau_sim_dir = "temp_tableau_staging_dir"

    if not (s3_client and aws_s3_tableau_bucket) and BOTO3_AVAILABLE and aws_s3_tableau_bucket: # If bucket name given but client failed (e.g. creds)
        logger.warning("Tableau S3 bucket configured, but S3 client likely had issues. Skipping actual S3 staging for Tableau.")
    elif not aws_s3_tableau_bucket:
         logger.info("Tableau S3 bucket not configured. Tableau staging to S3 will be skipped (simulation print only if applicable).")


    for candidate in tableau_source_candidates:
        source_path = candidate["path"]
        tableau_s3_object_key = candidate["tableau_s3_key"].lstrip("/")

        verified, _, _ = verify_hash_from_sidecar(source_path)
        if not verified:
            logger.critical(f"Hash verification failed for {source_path}. SKIPPING Tableau staging for this file.")
            any_tableau_staging_failure = True
            continue

        if s3_client and aws_s3_tableau_bucket:
            if upload_to_s3(s3_client, source_path, aws_s3_tableau_bucket, tableau_s3_object_key):
                staged_for_tableau_count +=1
            else:
                any_tableau_staging_failure = True
        else:
            if not os.path.exists(local_tableau_sim_dir): os.makedirs(local_tableau_sim_dir, exist_ok=True)
            sim_tableau_filename = os.path.basename(tableau_s3_object_key)
            logger.info(f"SIMULATE COPY (S3 fallback for Tableau): '{source_path}' TO '{os.path.join(local_tableau_sim_dir, sim_tableau_filename)}'")
            staged_for_tableau_count +=1

    if staged_for_tableau_count == 0 and len(tableau_source_candidates) > 0:
        logger.warning("No files were successfully staged for Tableau (either due to S3 upload failures or simulation).")
        if s3_client and aws_s3_tableau_bucket : any_tableau_staging_failure = True # If S3 was active, this is a failure
    else:
        logger.info(f"{staged_for_tableau_count} file(s) conceptually staged for Tableau.")

    logger.info("Output Archiving and Staging process completed.")

    if any_critical_archival_failure or any_tableau_staging_failure:
        logger.critical("CRITICAL ERRORS occurred during S3 archival or Tableau staging. Exiting with failure.")
        sys.exit(1)
    elif any_hash_mismatch_in_archive_candidates: # Log again if this happened but didn't cause exit
        logger.warning("Hash mismatches occurred for some archive candidates, which were flagged. Review logs and manifest.")

if __name__ == "__main__":
    main()
