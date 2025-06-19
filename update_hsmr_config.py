import json
import datetime
import hashlib
import os
import sys # For sys.exit in main if needed for critical errors not related to date logic itself

def get_target_period_dates():
    """
    Calculates dates for a target quarter.
    Prioritizes INPUT_TARGET_YEAR and INPUT_TARGET_QUARTER environment variables.
    If not present or invalid, defaults to the quarter preceding the current date.
    Returns a dictionary with year, quarter, start_date, end_date (YYYY-MM-DD), etc.
    """
    target_year_str = os.getenv('INPUT_TARGET_YEAR')
    target_quarter_str = os.getenv('INPUT_TARGET_QUARTER')

    target_year = None
    target_quarter = None

    if target_year_str and target_quarter_str:
        try:
            target_year = int(target_year_str)
            target_quarter = int(target_quarter_str)
            if not (1 <= target_quarter <= 4):
                print(f"WARNING: Invalid INPUT_TARGET_QUARTER '{target_quarter_str}'. Must be 1-4. Defaulting to previous quarter.")
                target_year, target_quarter = None, None # Reset to trigger default
            else:
                print(f"Using overridden target period: Year {target_year}, Quarter {target_quarter}")
        except ValueError:
            print(f"WARNING: Invalid INPUT_TARGET_YEAR ('{target_year_str}') or INPUT_TARGET_QUARTER ('{target_quarter_str}'). Must be integers. Defaulting to previous quarter.")
            target_year, target_quarter = None, None # Reset to trigger default

    current_processing_date = datetime.date.today() # Date when the script is run

    if target_year is None or target_quarter is None: # Default logic: previous quarter from current_processing_date
        print(f"No valid year/quarter override. Calculating previous quarter based on current date: {current_processing_date.isoformat()}")
        current_month = current_processing_date.month
        current_year_val = current_processing_date.year

        if 1 <= current_month <= 3:
            target_quarter = 4
            target_year = current_year_val - 1
        elif 4 <= current_month <= 6:
            target_quarter = 1
            target_year = current_year_val
        elif 7 <= current_month <= 9:
            target_quarter = 2
            target_year = current_year_val
        else: # 10 <= current_month <= 12
            target_quarter = 3
            target_year = current_year_val
        print(f"Defaulted to target period: Year {target_year}, Quarter {target_quarter}")


    # Calculate start and end months for the target_quarter
    if target_quarter == 1:
        start_month, end_month = 1, 3
    elif target_quarter == 2:
        start_month, end_month = 4, 6
    elif target_quarter == 3:
        start_month, end_month = 7, 9
    else: # target_quarter == 4
        start_month, end_month = 10, 12

    # Calculate start and end dates of the target quarter
    try:
        target_period_start_date = datetime.date(target_year, start_month, 1)
        if end_month == 12:
            target_period_end_date = datetime.date(target_year, end_month, 31)
        else:
            target_period_end_date = datetime.date(target_year, end_month + 1, 1) - datetime.timedelta(days=1)
    except ValueError as e:
        print(f"ERROR: Could not construct dates for Year {target_year}, Quarter {target_quarter}. Invalid date components? {e}")
        raise ValueError(f"Date construction failed for Y{target_year}Q{target_quarter}") from e


    # Conceptual actual publication date (e.g., 15th day of the 3rd month after quarter ends)
    # This logic now uses the determined target_year and end_month of that target quarter
    # publication_year and publication_month for the actual publication
    publication_year = target_year
    publication_month = end_month + 3
    if publication_month > 12:
        publication_month -= 12
        publication_year += 1

    conceptual_actual_publication_date = datetime.date(publication_year, publication_month, 15)

    # Conceptual submission deadline (e.g., 15th day of the 2nd month after quarter ends)
    # submission_year and submission_month for the deadline
    submission_year = target_year
    submission_month = end_month + 2
    if submission_month > 12:
        submission_month -= 12
        submission_year += 1

    conceptual_submission_deadline_date = datetime.date(submission_year, submission_month, 15)

    return {
        "year": target_year,
        "quarter": target_quarter,
        "processing_script_run_date": current_processing_date.isoformat(), # Added for clarity
        "publication_reference_period": f"{target_year}_Q{target_quarter}",
        "start_date_iso": target_period_start_date.isoformat(),
        "end_date_iso": target_period_end_date.isoformat(),
        "end_date_dmy": target_period_end_date.strftime("%d%m%Y"),
        "conceptual_actual_publication_date_iso": conceptual_actual_publication_date.isoformat(),
        "conceptual_submission_deadline_date_iso": conceptual_submission_deadline_date.isoformat()
    }

def generate_config_hash(config_data):
    """Generates a SHA256 hash of the configuration data."""
    config_string = json.dumps(config_data, sort_keys=True)
    return hashlib.sha256(config_string.encode('utf-8')).hexdigest()

def main():
    config_file_name = "hsmr_config.json"

    try:
        date_params = get_target_period_dates()
    except ValueError as e:
        print(f"CRITICAL: Could not determine target period dates. {e}")
        sys.exit(1) # Ensure GHA step fails if dates are fundamentally broken

    db_connection_details_placeholder = {
        "db_server_placeholder": "your_server_name_or_DSN_env_var",
        "db_name_placeholder": "your_database_name_env_var"
    }

    config_data = {
        "date_parameters": date_params,
        "database_config": db_connection_details_placeholder,
        "reference_file_manifest": [
            {
                "name": "lookup_hospital_codes.csv",
                "path": "reference_files/lookup_hospital_codes.csv",
                "expected_hash": "f1431cfcb6d782e2d2b891df259cca29ef3884b9e1018452c82175027bd68c7a"
            },
            {
                "name": "lookup_diagnosis_groups.csv",
                "path": "reference_files/lookup_diagnosis_groups.csv",
                "expected_hash": "75c4ab3555471ed7da76b4afdd88af9d9490fc58bc75f52431da19219329a8cc"
            },
            {
                "name": "hsmr_report_template.csv",
                "path": "reference_files/templates/hsmr_report_template.csv",
                "expected_hash": "efc8373e671e5d5fc2be008cd07e44bc6ba689f6106ceb70f9a86120084af270",
                "type": "template"
            }
        ],
        "output_paths": {
            "raw_data_dir": "data/raw",
            "processed_data_dir": "data/processed",
            "final_output_dir": "data/output",
            "publication_outputs_dir": "publication_outputs",
            "archive_dir_template": "archive/{year}/HSMR_{year}_Q{quarter}"
        },
        "schema_definitions": {
            "smr_output_schema": "schemas/smr_output_schema.json",
            "trends_output_schema": "schemas/trends_output_schema.json"
        },
        "rmd_files_config": {
            "main_report": {
                "rmd_path": "markdown/HSMR_Main_Report.Rmd",
                "output_formats": ["html_document", "pdf_document"],
                "output_filename_base": "HSMR_Main_Report"
            },
            "summary_report": {
                "rmd_path": "markdown/HSMR_Summary_Report.Rmd",
                "output_formats": ["html_document"],
                "output_filename_base": "HSMR_Summary_Report"
            }
        }
    }

    config_data_hash = generate_config_hash(config_data)
    config_data["config_hash"] = config_data_hash

    with open(config_file_name, 'w') as f:
        json.dump(config_data, f, indent=4)

    print(f"Successfully generated/updated {config_file_name}")
    print(f"Config data hash: {config_data_hash}")
    print(f"Reference period: {date_params['publication_reference_period']}")
    print(f"Processing script run date: {date_params['processing_script_run_date']}")
    if os.getenv('INPUT_TARGET_YEAR') and os.getenv('INPUT_TARGET_QUARTER'):
        print(f"Based on manual override: Year {os.getenv('INPUT_TARGET_YEAR')}, Quarter {os.getenv('INPUT_TARGET_QUARTER')}")

    # Output for GitHub Actions
    if os.getenv('GITHUB_OUTPUT'):
        print(f"Setting GITHUB_OUTPUT: publication_reference_period={date_params['publication_reference_period']}")
        with open(os.getenv('GITHUB_OUTPUT'), 'a') as gh_output:
            gh_output.write(f"publication_reference_period={date_params['publication_reference_period']}\n")
    # else:
    #     print("GITHUB_OUTPUT environment variable not found. Skipping GHA output.")


if __name__ == "__main__":
    main()
