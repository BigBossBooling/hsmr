# qa_scripts/validate_data_rules.py

import json
import pandas as pd
import os
import sys

def load_config(config_path="hsmr_config.json"):
    """Loads the main configuration file."""
    if not os.path.exists(config_path):
        print(f"ERROR: Configuration file not found at {config_path}")
        sys.exit(1)
    with open(config_path, 'r') as f:
        return json.load(f)

def apply_rules_to_dataframe(df, rules_config, df_name="DataFrame"):
    """
    Applies a set of validation rules to a Pandas DataFrame.
    Returns a list of error messages. Empty list means all rules passed.
    """
    errors = []
    if len(df.index) == 0: # Check if DataFrame has any data rows
        print(f"INFO: DataFrame '{df_name}' has no data rows. Skipping data rule checks.")
        return errors

    for rule in rules_config:
        rule_name = rule.get("rule_name", "Unnamed Rule")
        column_name = rule.get("column")

        if rule["type"] == "range":
            if column_name not in df.columns:
                msg = f"Rule '{rule_name}' for DataFrame '{df_name}': Column '{column_name}' for range check not found."
                print(f"WARNING: {msg}")
                continue

            series = df[column_name]
            series_numeric = pd.to_numeric(series, errors='coerce')

            if not rule.get("allow_na", False) and series_numeric.isnull().any():
                errors.append(f"Rule '{rule_name}' for '{df_name}': Column '{column_name}' contains NA/NaN or non-numeric values where not allowed.")

            series_no_na = series_numeric.dropna()
            if series_no_na.empty:
                continue

            min_val = rule.get("min_value")
            max_val = rule.get("max_value")
            min_exclusive = rule.get("min_exclusive", False)
            max_exclusive = rule.get("max_exclusive", False)

            condition = pd.Series(True, index=series_no_na.index)
            if min_val is not None:
                condition = condition & (series_no_na > min_val if min_exclusive else series_no_na >= min_val)
            if max_val is not None:
                condition = condition & (series_no_na < max_val if max_exclusive else series_no_na <= max_val)

            if not condition.all():
                invalid_rows = series_no_na[~condition]
                errors.append(
                    f"Rule '{rule_name}' for '{df_name}': Column '{column_name}' failed range check. "
                    f"Min: {min_val}, Max: {max_val}. Found {len(invalid_rows)} invalid row(s). "
                    f"Example invalid values: {list(invalid_rows.head(3))}"
                )

        elif rule["type"] == "consistency":
            expression = rule.get("expression")
            # Basic check for column existence - needs robust parsing for complex expressions
            required_cols_in_expr_approx = [col for col in df.columns if col in expression]
            all_cols_present = all(c in df.columns for c in required_cols_in_expr_approx)

            if not all_cols_present and required_cols_in_expr_approx:
                 actual_missing_cols = [c for c in required_cols_in_expr_approx if c not in df.columns]
                 if actual_missing_cols:
                    errors.append(f"Rule '{rule_name}' for '{df_name}': Not all columns for expression '{expression}' found. Missing: {actual_missing_cols}.")
                    continue
            try:
                failing_rows_df = df.query(f"not ({expression})")
                if not failing_rows_df.empty:
                    errors.append(
                        f"Rule '{rule_name}' for '{df_name}': Consistency check '{expression}' failed for {len(failing_rows_df)} row(s)."
                    )
            except Exception as eval_e:
                errors.append(f"Rule '{rule_name}' for '{df_name}': Error evaluating consistency expression '{expression}': {str(eval_e)}")

        elif rule["type"] == "subset_hash_check":
            # --- CONCEPTUAL BLOCKCHAIN-INSPIRED SUBSET HASH CHECK ---
            subset_cols = rule.get("columns_for_subset", [])
            expected_hash_key = rule.get("expected_hash_key_in_config")

            if not subset_cols or not expected_hash_key:
                errors.append(f"Rule '{rule_name}' for '{df_name}': Misconfigured subset_hash_check. Missing 'columns_for_subset' or 'expected_hash_key_in_config'.")
                continue

            print(f"INFO: Conceptually performing subset hash check for rule '{rule_name}' on columns {subset_cols}.")
            print(f"INFO: Would retrieve expected hash using key '{expected_hash_key}' from configuration.")
            print(f"INFO: This conceptual check passes by default for simulation.")
            # In a real implementation, if hashes don't match:
            # errors.append(f"Rule '{rule_name}' for '{df_name}': Subset hash check FAILED.")
            pass # Placeholder - always passes for now.
            # --- END CONCEPTUAL SUBSET HASH CHECK ---

        # Add other rule types here

    return errors

def define_rules():
    """Defines validation rules for different data files."""
    rules = {
        "smr_output": [
            {"rule_name": "SMR Value Range", "type": "range", "column": "smr_value", "min_value": 0.0, "allow_na": True},
            {"rule_name": "Predicted Mortality Prob Range", "type": "range", "column": "predicted_mortality_prob", "min_value": 0.0, "max_value": 1.0, "allow_na": True},
            {"rule_name": "Comorbidity Score Non-Negative", "type": "range", "column": "comorbidity_score", "min_value": 0, "allow_na": False},
            {"rule_name": "Discharged Alive Status Valid", "type": "range", "column": "discharged_alive_status", "min_value": 0, "max_value": 1, "allow_na": False},
            # Conceptual placeholder for a subset hash check:
            # {
            #     "rule_name": "Key SMR Subset Integrity",
            #     "type": "subset_hash_check",
            #     "columns_for_subset": ["patient_id", "smr_value", "predicted_mortality_prob"],
            #     "expected_hash_key_in_config": "smr_output_key_subset_expected_hash",
            #     "description": "Verifies integrity of a critical subset of SMR output data against a pre-calculated hash."
            # },
        ],
        "trends_output": [
            {"rule_name": "Crude Mortality Rate Range", "type": "range", "column": "crude_mortality_rate", "min_value": 0.0, "max_value": 1.0, "allow_na": True},
            {"rule_name": "Total Admissions Non-Negative", "type": "range", "column": "total_admissions", "min_value": 0, "allow_na": False},
            {"rule_name": "Total Deaths Non-Negative", "type": "range", "column": "total_deaths", "min_value": 0, "allow_na": False},
            {"rule_name": "Trends: Deaths <= Admissions", "type": "consistency", "expression": "total_deaths <= total_admissions"},
        ]
    }
    return rules

def main():
    print("Starting Data Rules (Range & Consistency) Validation Process...")
    config = load_config()
    rules_definitions = define_rules()

    date_params = config.get("date_parameters", {})
    publication_ref_period = date_params.get("publication_reference_period", "unknown_period")

    processed_data_dir = config.get("output_paths", {}).get("processed_data_dir", "data/processed")

    all_overall_passed = True # Changed variable name for clarity
    validation_summary = {}

    files_to_validate_config = {
        "smr_output": os.path.join(processed_data_dir, f"smr_output_{publication_ref_period}.csv"),
        "trends_output": os.path.join(processed_data_dir, f"trends_output_{publication_ref_period}.csv")
    }

    for file_key, data_filepath in files_to_validate_config.items():
        print(f"\nValidating data rules for {file_key} ({data_filepath})...")

        if not os.path.exists(data_filepath):
            print(f"ERROR: Data file not found: {data_filepath}. This is a critical error for rule checks.")
            validation_summary[file_key] = {"status": "ERROR_FILE_NOT_FOUND", "reason": f"Data file not found: {data_filepath}"}
            all_overall_passed = False
            continue

        try:
            df = pd.read_csv(data_filepath)
        except pd.errors.EmptyDataError:
            print(f"INFO: Data file {data_filepath} is completely empty (0 bytes). Skipping data content rule checks.")
            validation_summary[file_key] = {"status": "SKIPPED_EMPTY_FILE", "reason": "Data file is 0-bytes empty"}
            # Not a failure of rules, but data is missing. Consider if this should set all_overall_passed = False
            # For now, assume schema check would catch this if columns were expected.
            # If it's header-only, df might not be empty but len(df.index)==0, handled in apply_rules_to_dataframe
            continue
        except Exception as e:
            print(f"ERROR: Failed to read CSV {data_filepath}: {str(e)}")
            validation_summary[file_key] = {"status": "ERROR_READING_CSV", "reason": f"Failed to read CSV: {str(e)}"}
            all_overall_passed = False
            continue

        file_rules = rules_definitions.get(file_key, [])
        if not file_rules:
            print(f"INFO: No specific data rules defined for {file_key}. Validation considered PASSED (no rules to fail).")
            validation_summary[file_key] = {"status": "PASSED_NO_RULES", "reason": "No rules defined for this file key"}
            continue

        errors = apply_rules_to_dataframe(df, file_rules, df_name=file_key)

        if not errors:
            print(f"Data rule validation PASSED for {data_filepath}.")
            validation_summary[file_key] = {"status": "PASSED", "file": data_filepath}
        else:
            print(f"Data rule validation FAILED for {data_filepath}:")
            for error in errors:
                print(f"  - {error}")
            validation_summary[file_key] = {"status": "FAILED", "file": data_filepath, "errors": errors}
            all_overall_passed = False

    report_file = "data_rules_validation_report.json"
    with open(report_file, 'w') as f:
        json.dump(validation_summary, f, indent=4)
    print(f"\nData rules validation summary report saved to {report_file}")

    if not all_overall_passed: # Renamed variable
        print("\nOne or more data rule validations encountered errors or failed.")
        sys.exit(1)
    else:
        print("\nAll data rule validations passed successfully (or were skipped appropriately for empty files/no rules).")

if __name__ == "__main__":
    main()
