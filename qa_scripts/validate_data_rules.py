# qa_scripts/validate_data_rules.py

import json
import pandas as pd
import os
import sys
import hashlib
import logging

# --- Configure Python Logging ---
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(levelname)s - %(filename)s:%(lineno)d - %(message)s',
    stream=sys.stdout
)
logger = logging.getLogger(__name__)

def load_config(config_path="hsmr_config.json"):
    if not os.path.exists(config_path):
        logger.error(f"Configuration file not found at {config_path}")
        sys.exit(1)
    with open(config_path, 'r') as f:
        return json.load(f)

def apply_rules_to_dataframe(df, rules_config, df_name="DataFrame", global_config_for_hashes=None):
    errors = []
    if len(df.index) == 0:
        logger.info(f"DataFrame '{df_name}' has no data rows. Skipping data rule checks.")
        return errors

    for rule in rules_config:
        rule_name = rule.get("rule_name", "Unnamed Rule")
        column_name = rule.get("column")

        try:
            if rule["type"] == "range":
                if column_name not in df.columns:
                    logger.warning(f"Rule '{rule_name}' for DataFrame '{df_name}': Column '{column_name}' for range check not found.")
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
                try:
                    failing_rows_df = df.query(f"not ({expression})")
                    if not failing_rows_df.empty:
                        errors.append(
                            f"Rule '{rule_name}' for '{df_name}': Consistency check '{expression}' failed for {len(failing_rows_df)} row(s)."
                        )
                except Exception as eval_e:
                    errors.append(f"Rule '{rule_name}' for '{df_name}': Error evaluating consistency expression '{expression}': {str(eval_e)}")

            elif rule["type"] == "subset_hash_check":
                logger.info(f"Applying subset_hash_check rule: {rule_name}")
                subset_cols_config = rule.get("columns_for_subset")
                expected_hash_config_key = rule.get("expected_hash_config_key")

                if not subset_cols_config or not expected_hash_config_key or global_config_for_hashes is None:
                    errors.append(f"Rule '{rule_name}' for '{df_name}': Misconfigured. Needs 'columns_for_subset', 'expected_hash_config_key', and 'global_config_for_hashes'.")
                    continue

                # Ensure all subset columns exist in the DataFrame
                missing_subset_cols = [col for col in subset_cols_config if col not in df.columns]
                if missing_subset_cols:
                    errors.append(f"Rule '{rule_name}' for '{df_name}': Not all columns for subset hash check found. Missing: {missing_subset_cols}.")
                    continue

                expected_hash = global_config_for_hashes.get("data_subset_hashes", {}).get(expected_hash_config_key)
                if expected_hash is None:
                    errors.append(f"Rule '{rule_name}' for '{df_name}': Expected hash key '{expected_hash_config_key}' not found in config's data_subset_hashes.")
                    continue

                try:
                    # Sort columns specified in config for consistent selection order
                    sorted_subset_cols = sorted(list(subset_cols_config))
                    subset_df = df[sorted_subset_cols].copy() # Select only the specified columns in sorted order

                    # Consistent Serialization:
                    # 1. Convert all to string to avoid type ambiguities
                    for col in subset_df.columns:
                        subset_df[col] = subset_df[col].astype(str)
                    # 2. Sort rows by all columns to ensure consistent row order
                    if not subset_df.empty: # Avoid error on sorting empty df if all columns were stringified from NA
                         subset_df = subset_df.sort_values(by=list(subset_df.columns)).reset_index(drop=True)

                    # 3. Serialize to a canonical JSON string format (array of records)
                    # The column order in each record is now guaranteed by sorted_subset_cols.
                    # Row order is guaranteed by sort_values.
                    serialized_data = subset_df.to_json(orient='records', lines=False) # lines=False for compact string

                    calculated_hash = hashlib.sha256(serialized_data.encode('utf-8')).hexdigest()

                    if calculated_hash == expected_hash:
                        logger.info(f"Rule '{rule_name}' for '{df_name}': Subset hash check PASSED. (Hash: {calculated_hash})")
                    else:
                        errors.append(
                            f"Rule '{rule_name}' for '{df_name}': Subset hash check FAILED. "
                            f"Expected: {expected_hash}, Calculated: {calculated_hash}."
                        )
                except Exception as e_hash:
                    errors.append(f"Rule '{rule_name}' for '{df_name}': Error during subset hash calculation: {str(e_hash)}")

        except Exception as e:
            errors.append(f"Rule '{rule_name}' for '{df_name}': Error during execution - {str(e)}")

    return errors

def define_rules():
    rules = {
        "smr_output": [
            {"rule_name": "SMR Value Range", "type": "range", "column": "smr_value", "min_value": 0.0, "allow_na": True},
            {"rule_name": "Predicted Mortality Prob Range", "type": "range", "column": "predicted_mortality_prob", "min_value": 0.0, "max_value": 1.0, "allow_na": True},
            {"rule_name": "Comorbidity Score Non-Negative", "type": "range", "column": "comorbidity_score", "min_value": 0, "allow_na": False},
            {"rule_name": "Discharged Alive Status Valid", "type": "range", "column": "discharged_alive_status", "min_value": 0, "max_value": 1, "allow_na": False},
            {
                "rule_name": "SMR Key Fields Integrity Hash",
                "type": "subset_hash_check",
                "columns_for_subset": ["patient_id", "smr_value", "predicted_mortality_prob"],
                "expected_hash_config_key": "smr_output_key_fields_hash",
                "description": "Verifies integrity of a key subset of SMR output data."
            }
        ],
        "trends_output": [
            {"rule_name": "Crude Mortality Rate Range", "type": "range", "column": "crude_mortality_rate", "min_value": 0.0, "max_value": 1.0, "allow_na": True},
            {"rule_name": "Total Admissions Non-Negative", "type": "range", "column": "total_admissions", "min_value": 0, "allow_na": False},
            {"rule_name": "Total Deaths Non-Negative", "type": "range", "column": "total_deaths", "min_value": 0, "allow_na": False},
            {"rule_name": "Trends: Deaths <= Admissions", "type": "consistency", "expression": "total_deaths <= total_admissions"},
            {
                "rule_name": "Trends Summary Integrity Hash",
                "type": "subset_hash_check",
                "columns_for_subset": ["time_period", "total_admissions", "total_deaths", "crude_mortality_rate"],
                "expected_hash_config_key": "trends_output_summary_hash",
                "description": "Verifies integrity of the full trends output data."
            }
        ]
    }
    return rules

def main():
    logger.info("Starting Data Rules (Range, Consistency, Subset Hash) Validation Process...")
    config = load_config()
    rules_definitions = define_rules()

    date_params = config.get("date_parameters", {})
    publication_ref_period = date_params.get("publication_reference_period", "unknown_period")

    processed_data_dir = config.get("output_paths", {}).get("processed_data_dir", "data/processed")

    all_overall_passed = True
    validation_summary = {}

    files_to_validate_config = {
        "smr_output": os.path.join(processed_data_dir, f"smr_output_{publication_ref_period}.csv"),
        "trends_output": os.path.join(processed_data_dir, f"trends_output_{publication_ref_period}.csv")
    }

    for file_key, data_filepath in files_to_validate_config.items():
        logger.info(f"Validating data rules for {file_key} ({data_filepath})...")

        if not os.path.exists(data_filepath):
            logger.error(f"Data file not found: {data_filepath}. This is a critical error for rule checks.")
            validation_summary[file_key] = {"status": "ERROR_FILE_NOT_FOUND", "reason": f"Data file not found: {data_filepath}"}
            all_overall_passed = False
            continue

        try:
            df = pd.read_csv(data_filepath)
        except pd.errors.EmptyDataError:
            logger.info(f"Data file {data_filepath} is completely empty (0 bytes). Skipping data content rule checks.")
            validation_summary[file_key] = {"status": "SKIPPED_EMPTY_FILE", "reason": "Data file is 0-bytes empty"}
            continue
        except Exception as e:
            logger.error(f"Failed to read CSV {data_filepath}: {str(e)}")
            validation_summary[file_key] = {"status": "ERROR_READING_CSV", "reason": f"Failed to read CSV: {str(e)}"}
            all_overall_passed = False
            continue

        file_rules = rules_definitions.get(file_key, [])
        if not file_rules:
            logger.info(f"No specific data rules defined for {file_key}. Validation considered PASSED (no rules to fail).")
            validation_summary[file_key] = {"status": "PASSED_NO_RULES", "reason": "No rules defined for this file key"}
            continue

        errors = apply_rules_to_dataframe(df, file_rules, df_name=file_key, global_config_for_hashes=config)

        if not errors:
            logger.info(f"Data rule validation PASSED for {data_filepath}.")
            validation_summary[file_key] = {"status": "PASSED", "file": data_filepath}
        else:
            logger.error(f"Data rule validation FAILED for {data_filepath}:")
            for error in errors:
                logger.error(f"  - {error}")
            validation_summary[file_key] = {"status": "FAILED", "file": data_filepath, "errors": errors}
            all_overall_passed = False

    report_file = "data_rules_validation_report.json"
    with open(report_file, 'w') as f:
        json.dump(validation_summary, f, indent=4)
    logger.info(f"Data rules validation summary report saved to {report_file}")

    if not all_overall_passed:
        logger.error("One or more data rule validations encountered errors or failed.")
        sys.exit(1)
    else:
        logger.info("All data rule validations passed successfully (or were skipped appropriately for empty files/no rules).")

if __name__ == "__main__":
    main()
