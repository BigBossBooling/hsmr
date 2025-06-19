import json
import datetime
import hashlib
import os

def get_previous_quarter_dates():
    """
    Calculates dates for the quarter preceding the current date.
    Returns a dictionary with year, quarter, start_date, end_date (YYYY-MM-DD),
    and end_date_dmy (DDMMYYYY) for the previous quarter.
    """
    today = datetime.date.today()
    current_month = today.month
    current_year = today.year

    # Determine previous quarter
    if 1 <= current_month <= 3:  # Q1 -> previous is Q4 of last year
        prev_quarter = 4
        prev_quarter_year = current_year - 1
        prev_quarter_start_month = 10
        prev_quarter_end_month = 12
    elif 4 <= current_month <= 6:  # Q2 -> previous is Q1 of current year
        prev_quarter = 1
        prev_quarter_year = current_year
        prev_quarter_start_month = 1
        prev_quarter_end_month = 3
    elif 7 <= current_month <= 9:  # Q3 -> previous is Q2 of current year
        prev_quarter = 2
        prev_quarter_year = current_year
        prev_quarter_start_month = 4
        prev_quarter_end_month = 6
    else:  # Q4 -> previous is Q3 of current year
        prev_quarter = 3
        prev_quarter_year = current_year
        prev_quarter_start_month = 7
        prev_quarter_end_month = 9

    # Calculate start and end dates of the previous quarter
    prev_quarter_start_date = datetime.date(prev_quarter_year, prev_quarter_start_month, 1)

    # End date is the last day of the end month
    if prev_quarter_end_month == 12:
        prev_quarter_end_date = datetime.date(prev_quarter_year, prev_quarter_end_month, 31)
    else:
        # Next month's first day, then subtract one day
        prev_quarter_end_date = datetime.date(prev_quarter_year, prev_quarter_end_month + 1, 1) - datetime.timedelta(days=1)

    # prev_quarter_start_date and prev_quarter_end_date are already calculated.

    # Conceptual actual publication date (e.g., 15th day of the 3rd month after quarter ends)
    # Example: Q4 (ends Dec 31), pub month is March. Q1 (ends Mar 31), pub month is June.
    if prev_quarter_end_month == 12: # Q4
        actual_pub_month = 3
        actual_pub_year = prev_quarter_year + 1
    else: # Q1, Q2, Q3
        actual_pub_month = prev_quarter_end_month + 3
        actual_pub_year = prev_quarter_year

    # Ensure month doesn't exceed 12 (not an issue with +3 on max 9, but good practice)
    if actual_pub_month > 12: # Should not happen with current logic
        actual_pub_month -= 12
        actual_pub_year +=1

    conceptual_actual_publication_date = datetime.date(actual_pub_year, actual_pub_month, 15) # Assume 15th of the month

    # Conceptual submission deadline (e.g., 15th day of the 2nd month after quarter ends)
    if prev_quarter_end_month == 12: # Q4
        submission_deadline_month = 2
        submission_deadline_year = prev_quarter_year + 1
    else: # Q1, Q2, Q3
        submission_deadline_month = prev_quarter_end_month + 2
        submission_deadline_year = prev_quarter_year

    if submission_deadline_month > 12: # Should not happen
        submission_deadline_month -=12
        submission_deadline_year +=1

    conceptual_submission_deadline_date = datetime.date(submission_deadline_year, submission_deadline_month, 15) # Assume 15th

    return {
        "year": prev_quarter_year,
        "quarter": prev_quarter,
        "publication_reference_period": f"{prev_quarter_year}_Q{prev_quarter}",
        "start_date_iso": prev_quarter_start_date.isoformat(), # YYYY-MM-DD
        "end_date_iso": prev_quarter_end_date.isoformat(),     # YYYY-MM-DD
        "end_date_dmy": prev_quarter_end_date.strftime("%d%m%Y"), # DDMMYYYY
        "conceptual_actual_publication_date_iso": conceptual_actual_publication_date.isoformat(),
        "conceptual_submission_deadline_date_iso": conceptual_submission_deadline_date.isoformat()
    }

def generate_config_hash(config_data):
    """Generates a SHA256 hash of the configuration data."""
    config_string = json.dumps(config_data, sort_keys=True)
    return hashlib.sha256(config_string.encode('utf-8')).hexdigest()

def main():
    config_file_name = "hsmr_config.json"

    # Get dates for the previous quarter as this is typical for such publications
    date_params = get_previous_quarter_dates()

    # Add a placeholder for database connection (credentials handled by GitHub Secrets)
    # Actual connection details might vary per environment (dev/test/prod)
    db_connection_details_placeholder = {
        "db_server_placeholder": "your_server_name_or_DSN_env_var",
        "db_name_placeholder": "your_database_name_env_var"
        # Actual credentials should NOT be stored here.
    }

    config_data = {
        "date_parameters": date_params,
        "database_config": db_connection_details_placeholder,
        "reference_file_manifest": [
            {
                "name": "lookup_hospital_codes.csv",
                "path": "reference_files/lookup_hospital_codes.csv", # Path relative to project root
                "expected_hash": "f1431cfcb6d782e2d2b891df259cca29ef3884b9e1018452c82175027bd68c7a"
            },
            {
                "name": "lookup_diagnosis_groups.csv",
                "path": "reference_files/lookup_diagnosis_groups.csv", # Path relative to project root
                "expected_hash": "75c4ab3555471ed7da76b4afdd88af9d9490fc58bc75f52431da19219329a8cc"
            },
            { # New entry for the template
                "name": "hsmr_report_template.csv",
                "path": "reference_files/templates/hsmr_report_template.csv",
                "expected_hash": "efc8373e671e5d5fc2be008cd07e44bc6ba689f6106ceb70f9a86120084af270",
                "type": "template" # Optional: add a type field
            }
        ],
        "output_paths": {
            "raw_data_dir": "data/raw",
            "processed_data_dir": "data/processed",
            "final_output_dir": "data/output",
            "publication_outputs_dir": "publication_outputs",
            "archive_dir_template": "archive/{year}/HSMR_{year}_Q{quarter}" # Template
        },
        "schema_definitions": { # New section
            "smr_output_schema": "schemas/smr_output_schema.json",
            "trends_output_schema": "schemas/trends_output_schema.json"
            # Add other schemas here as they are defined
        },
        "rmd_files_config": { # New section
            "main_report": {
                "rmd_path": "markdown/HSMR_Main_Report.Rmd",
                "output_formats": ["html_document", "pdf_document"], # Desired output formats
                "output_filename_base": "HSMR_Main_Report"
            },
            "summary_report": {
                "rmd_path": "markdown/HSMR_Summary_Report.Rmd",
                "output_formats": ["html_document"],
                "output_filename_base": "HSMR_Summary_Report"
            }
            # Add other Rmd files here as needed
        }
        # Add other configurations as needed
    }

    # Calculate hash of the data to be written
    config_data_hash = generate_config_hash(config_data)
    config_data["config_hash"] = config_data_hash

    # Write to JSON file
    with open(config_file_name, 'w') as f:
        json.dump(config_data, f, indent=4)

    print(f"Successfully generated/updated {config_file_name}")
    print(f"Config data hash: {config_data_hash}")
    print(f"Reference period: {date_params['publication_reference_period']}")

if __name__ == "__main__":
    main()
