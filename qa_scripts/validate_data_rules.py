# qa_scripts/validate_data_rules.py

import json
import pandas as pd
import os
import sys

def load_config(config_path="hsmr_config.json"):
    """Loads the main configuration file."""
    if not os.path.exists(config_path):
        print(f"ERROR: Configuration file not found at {config_path}")
        sys.exit(1) # Critical error if config is missing
    with open(config_path, 'r') as f:
        return json.load(f)

def apply_rules_to_dataframe(df, rules_config, df_name="DataFrame"):
    """
    Applies a set of validation rules to a Pandas DataFrame.
    'rules_config' is a list of dictionaries, each defining a rule.
    Example rule:
    {
        "rule_name": "SMR Value Positive",
        "type": "range",
        "column": "smr_value",
        "min_value": 0, # Can be exclusive by adding "min_exclusive": True
        "max_value": None, # No upper bound
        "allow_na": False
    }
    {
        "rule_name": "Mortality Rate Range",
        "type": "range",
        "column": "crude_mortality_rate",
        "min_value": 0,
        "max_value": 1, # If it's a rate between 0 and 1
        "allow_na": True # e.g., if admissions is 0, rate might be NA
    }
    {
        "rule_name": "Deaths <= Admissions",
        "type": "consistency",
        "expression": "total_deaths <= total_admissions"
        # 'expression' will be evaluated by df.eval() or df.query()
        # Ensure columns exist before applying.
    }
    Returns a list of error messages. Empty list means all rules passed.
    """
    errors = []
    if df.empty:
        # Check if it's truly empty or just header-only (which pandas might read as empty if no data rows)
        # This check is more about whether there's data to validate.
        # If a file has only a header, df.empty might be true or false depending on how it's read.
        # Let's assume if df.index is empty, there are no data rows.
        if len(df.index) == 0:
            print(f"INFO: DataFrame '{df_name}' has no data rows. Skipping data rule checks.")
            return errors # No data to check rules against

    for rule in rules_config:
        rule_name = rule.get("rule_name", "Unnamed Rule")
        column_name = rule.get("column") # Used in 'range', might be used to check existence for 'consistency'

        # Ensure column exists before applying column-specific rules
        if rule["type"] == "range" and column_name not in df.columns:
            msg = f"Rule '{rule_name}' for DataFrame '{df_name}': Column '{column_name}' for range check not found."
            print(f"WARNING: {msg}")
            # errors.append(msg) # Decide if this is a warning or error if column for rule is missing
            continue # Skip this rule

        try:
            if rule["type"] == "range":
                series = df[column_name]
                # Attempt to convert to numeric, coercing errors to NaT/NaN for checking
                # This helps if a column defined as numeric in schema was read as object due to mixed types or all strings
                series_numeric = pd.to_numeric(series, errors='coerce')

                if not rule.get("allow_na", False) and series_numeric.isnull().any():
                    # This check also catches original strings that couldn't be converted to numeric
                    errors.append(f"Rule '{rule_name}' for '{df_name}': Column '{column_name}' contains NA/NaN or non-numeric values where not allowed.")

                series_no_na = series_numeric.dropna()
                if series_no_na.empty:
                    continue

                min_val = rule.get("min_value")
                max_val = rule.get("max_value")
                min_exclusive = rule.get("min_exclusive", False)
                max_exclusive = rule.get("max_exclusive", False)

                condition = pd.Series(True, index=series_no_na.index) # Start with all true
                if min_val is not None:
                    if min_exclusive:
                        condition = condition & (series_no_na > min_val)
                    else:
                        condition = condition & (series_no_na >= min_val)
                if max_val is not None:
                    if max_exclusive:
                        condition = condition & (series_no_na < max_val)
                    else:
                        condition = condition & (series_no_na <= max_val)

                if not condition.all():
                    invalid_rows = series_no_na[~condition]
                    errors.append(
                        f"Rule '{rule_name}' for '{df_name}': Column '{column_name}' failed range check. "
                        f"Min: {min_val}, Max: {max_val}. Found {len(invalid_rows)} invalid row(s). "
                        f"Example invalid values: {list(invalid_rows.head(3))}"
                    )

            elif rule["type"] == "consistency":
                expression = rule.get("expression")

                # Basic check for column existence in expression (very simplified)
                # This is a placeholder for a more robust mechanism to parse columns from expression
                required_cols_in_expr_approx = [col for col in df.columns if col in expression]
                all_cols_present = all(c in df.columns for c in required_cols_in_expr_approx)

                if not all_cols_present and required_cols_in_expr_approx:
                     actual_missing_cols = [c for c in required_cols_in_expr_approx if c not in df.columns]
                     if actual_missing_cols: # if the simplistic check found columns that are indeed missing
                        errors.append(f"Rule '{rule_name}' for '{df_name}': Not all columns for expression '{expression}' found. Missing: {actual_missing_cols}.")
                        continue

                # Attempt to evaluate the expression using df.query() for boolean conditions
                # df.eval() is for assigning results or more complex ops. df.query() is good for filtering.
                # We want to find rows where the consistency expression is FALSE.
                try:
                    # We expect the expression to be something that evaluates to True for valid rows.
                    # So, query for the inverse to find failing rows.
                    failing_rows_df = df.query(f"not ({expression})")
                    if not failing_rows_df.empty:
                        errors.append(
                            f"Rule '{rule_name}' for '{df_name}': Consistency check '{expression}' failed for {len(failing_rows_df)} row(s)."
                        )
                except Exception as eval_e:
                    errors.append(f"Rule '{rule_name}' for '{df_name}': Error evaluating consistency expression '{expression}': {str(eval_e)}")

        except Exception as e:
            errors.append(f"Rule '{rule_name}' for '{df_name}': Error during execution - {str(e)}")

    return errors

def define_rules():
    """Defines validation rules for different data files."""
    rules = {
        "smr_output": [
            {"rule_name": "SMR Value Range", "type": "range", "column": "smr_value", "min_value": 0.0, "allow_na": True}, # SMR can be NA if calculated for small numbers
            {"rule_name": "Predicted Mortality Prob Range", "type": "range", "column": "predicted_mortality_prob", "min_value": 0.0, "max_value": 1.0, "allow_na": True}, # Probs can be NA
            {"rule_name": "Comorbidity Score Non-Negative", "type": "range", "column": "comorbidity_score", "min_value": 0, "allow_na": False}, # Assuming score is always calculated
            {"rule_name": "Actual Deaths Non-Negative", "type": "range", "column": "actual_deaths", "min_value": 0, "allow_na": False},
            {"rule_name": "Predicted Deaths Non-Negative", "type": "range", "column": "predicted_deaths", "min_value": 0, "allow_na": False},
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

    all_rules_passed = True
    validation_summary = {}

    files_to_validate_config = {
        "smr_output": os.path.join(processed_data_dir, f"smr_output_{publication_ref_period}.csv"),
        "trends_output": os.path.join(processed_data_dir, f"trends_output_{publication_ref_period}.csv")
    }

    for file_key, data_filepath in files_to_validate_config.items():
        print(f"\nValidating data rules for {file_key} ({data_filepath})...")

        if not os.path.exists(data_filepath):
            print(f"WARNING: Data file not found: {data_filepath}. Skipping rule checks.")
            validation_summary[file_key] = {"status": "SKIPPED", "reason": "Data file not found"}
            continue

        try:
            # For header-only files, this will create a DataFrame with columns but 0 rows.
            df = pd.read_csv(data_filepath)
        except pd.errors.EmptyDataError: # If file is 0-bytes (no header, no data)
            print(f"INFO: Data file {data_filepath} is completely empty. Skipping rule checks.")
            validation_summary[file_key] = {"status": "SKIPPED", "reason": "Data file is 0-bytes empty"}
            continue
        except Exception as e:
            print(f"ERROR: Failed to read CSV {data_filepath}: {str(e)}")
            validation_summary[file_key] = {"status": "ERROR", "reason": f"Failed to read CSV: {str(e)}"}
            all_rules_passed = False
            continue

        file_rules = rules_definitions.get(file_key, [])
        if not file_rules:
            print(f"INFO: No specific rules defined for {file_key}. Skipping.")
            validation_summary[file_key] = {"status": "SKIPPED", "reason": "No rules defined"}
            continue # Not necessarily a failure, just no rules to apply

        errors = apply_rules_to_dataframe(df, file_rules, df_name=file_key)

        if not errors:
            print(f"Data rule validation PASSED for {data_filepath}.")
            validation_summary[file_key] = {"status": "PASSED", "file": data_filepath}
        else:
            print(f"Data rule validation FAILED for {data_filepath}:")
            for error in errors:
                print(f"  - {error}")
            validation_summary[file_key] = {"status": "FAILED", "file": data_filepath, "errors": errors}
            all_rules_passed = False

    report_file = "data_rules_validation_report.json"
    with open(report_file, 'w') as f:
        json.dump(validation_summary, f, indent=4)
    print(f"\nData rules validation summary report saved to {report_file}")

    if not all_rules_passed:
        print("\nOne or more data rule validations failed.")
        sys.exit(1)
    else:
        print("\nAll data rule validations passed successfully!")

if __name__ == "__main__":
    main()
