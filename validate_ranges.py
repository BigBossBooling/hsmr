#!/usr/bin/env python3
import csv
import json
import sys

# Define range rules here (column_name: {min_val: x, max_val: y, allow_null: False})
RANGE_RULES = {
    "smr_output.csv": {
        "smr_value": {"min_val": 0, "max_val": 10, "allow_null": False},
        "predicted_deaths": {"min_val": 0, "allow_null": False},
        "actual_deaths": {"min_val": 0, "allow_null": False},
        "year": {"min_val": 2000, "max_val": 2050, "allow_null": False}
    },
    "trends_output.csv": {
        "metric_value": {"min_val": 0, "allow_null": True}
    },
    "open_data_hsmr.csv": {
        "smr": {"min_val": 0, "max_val": 10, "allow_null": True},
        "crude_rate_deaths_per_100_episodes": {"min_val": 0, "max_val": 100, "allow_null": True}
    }
}

def validate_csv_ranges(file_path, schema_name_base, dummy_run=True):
    validation_results = {
        "file": file_path,
        "check_type": "range_validation",
        "schema_name": schema_name_base,
        "status": "FAIL",
        "findings": []
    }

    if schema_name_base not in RANGE_RULES:
        validation_results["findings"].append(f"No range rule definition found for '{schema_name_base}'.")
        return validation_results

    rules = RANGE_RULES[schema_name_base]

    if dummy_run:
        validation_results["status"] = "PASS_DUMMY"
        validation_results["findings"].append("Range checks are conceptual (dummy run on placeholder file).")
        for col_name, rule in rules.items():
            validation_results["findings"].append(f"  - Conceptual check for column '{col_name}': min={rule.get('min_val')}, max={rule.get('max_val')}, null_ok={rule.get('allow_null')}")
        return validation_results

    # --- Actual logic if dummy_run is False and file has data ---
    # Conditional import of pandas
    try:
        import pandas as pd
    except ImportError:
        validation_results["findings"].append("Pandas library not found. Cannot perform actual range check.")
        validation_results["status"] = "ERROR_DEPENDENCY"
        return validation_results

    try:
        df = pd.read_csv(file_path)
        if df.empty: # Checks if DataFrame is empty (no data rows beyond header)
            validation_results["status"] = "PASS_EMPTY"
            validation_results["findings"].append("File has header but no data rows. No data to range check.")
            return validation_results

        # Check if the file only contains a header and no actual data rows,
        # which might not make df.empty true if columns are typed by header.
        # A more robust check for "header only" if pandas reads columns but finds no data lines:
        if len(df.index) == 0:
            validation_results["status"] = "PASS_EMPTY"
            validation_results["findings"].append("File has header but no data rows (checked by index length). No data to range check.")
            return validation_results


        all_checks_passed = True
        for col_name, rule in rules.items():
            if col_name not in df.columns:
                validation_results["findings"].append(f"Column '{col_name}' for range check not found in file.")
                all_checks_passed = False
                continue

            if not rule.get("allow_null", False) and df[col_name].isnull().any():
                validation_results["findings"].append(f"Column '{col_name}' contains unexpected NULL values.")
                all_checks_passed = False

            col_data = df[col_name].dropna()
            if not col_data.empty:
                try:
                    col_data_numeric = pd.to_numeric(col_data)
                    if "min_val" in rule and (col_data_numeric < rule["min_val"]).any():
                        validation_results["findings"].append(f"Column '{col_name}' has values below minimum {rule['min_val']}.")
                        all_checks_passed = False
                    if "max_val" in rule and (col_data_numeric > rule["max_val"]).any():
                        validation_results["findings"].append(f"Column '{col_name}' has values above maximum {rule['max_val']}.")
                        all_checks_passed = False
                except ValueError: # Raised by pd.to_numeric if conversion fails
                    validation_results["findings"].append(f"Column '{col_name}' contains non-numeric values where numeric expected for range check.")
                    all_checks_passed = False

        if all_checks_passed:
            validation_results["status"] = "PASS"
            validation_results["findings"].append("All range checks passed on available data.")
        else:
            validation_results["status"] = "FAIL"

    except FileNotFoundError:
        validation_results["findings"].append("File not found.")
    except pd.errors.EmptyDataError: # Pandas specific error for truly empty file (no header)
        validation_results["status"] = "ERROR_EMPTY_FILE" # Different from PASS_EMPTY (header but no data)
        validation_results["findings"].append("File is completely empty (no header). Cannot perform range check.")
    except Exception as e:
        validation_results["findings"].append(f"An error occurred during actual run: {str(e)}")

    return validation_results

if __name__ == "__main__":
    if len(sys.argv) not in [3, 4]:
        print("Usage: python validate_ranges.py <file_path> <schema_name_base> [--actual-run]")
        sys.exit(1)

    file_path_arg = sys.argv[1]
    schema_name_arg = sys.argv[2]

    is_dummy_run = True
    if len(sys.argv) == 4 and sys.argv[3] == "--actual-run":
        is_dummy_run = False

    result = validate_csv_ranges(file_path_arg, schema_name_arg, dummy_run=is_dummy_run)

    print(json.dumps(result))
