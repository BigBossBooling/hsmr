# qa_scripts/validate_schema.py

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

def load_schema(schema_path):
    """Loads a JSON schema definition file."""
    if not os.path.exists(schema_path):
        print(f"ERROR: Schema file not found at {schema_path}")
        return None
    with open(schema_path, 'r') as f:
        return json.load(f)

def validate_csv_schema(csv_filepath, schema_definition):
    """
    Validates a CSV file against a schema definition.
    Returns a list of validation errors. Empty list means success.
    """
    errors = []

    if not os.path.exists(csv_filepath):
        errors.append(f"CSV file not found: {csv_filepath}")
        return errors

    try:
        if os.path.getsize(csv_filepath) == 0:
            # If schema expects columns, an empty file is a failure.
            # If schema allows empty (e.g. no required columns and data not mandatory), could be PASS.
            # For now, let's assume if a schema is defined, some columns are expected.
            if schema_definition.get('columns'):
                 errors.append(f"CSV file is empty (0 bytes): {csv_filepath}. Schema expects columns.")
            # else, if schema has no columns defined, it could be a pass for an empty file.
            return errors
        df = pd.read_csv(csv_filepath)
        # If read_csv results in an empty DataFrame (e.g. header only, or truly empty parsed as such)
        if df.empty and schema_definition.get('columns'):
            # Check if it was just a header row that pandas consumed
            with open(csv_filepath, 'r') as f_check_header:
                first_line = f_check_header.readline().strip()
                if not first_line: # Truly empty or blank first line
                    errors.append(f"CSV file appears empty or has no header: {csv_filepath}")
                    return errors
                # If first_line exists but df is empty, it means it was header-only.
                # This is a valid state for some checks (e.g. column names) but means no data for type checks.
                # This function's purpose is schema + type checks, so data is implicitly needed.
                # However, the current logic below will handle column name checks correctly for header-only.
                # Type checks will effectively be skipped or might fail if dtype is 'object' for all.
                pass # Proceed to column name and type checks with the header-only df

    except pd.errors.EmptyDataError: # This error means no columns, completely empty.
        if schema_definition.get('columns'): # If schema expects columns, this is an error.
            errors.append(f"CSV file is completely empty (no columns to parse): {csv_filepath}")
        # If schema defines no columns (unlikely for us), then it's a PASS.
        return errors
    except Exception as e:
        errors.append(f"Failed to read CSV {csv_filepath}: {str(e)}")
        return errors

    expected_cols = schema_definition.get('columns', [])
    schema_col_names = [col['name'] for col in expected_cols]

    if not schema_definition.get('allow_extra_columns', False):
        if len(df.columns) != len(expected_cols):
             errors.append(
                 f"Column count mismatch (allow_extra_columns=false). Expected {len(expected_cols)}, got {len(df.columns)}."
             )

    if schema_definition.get('strict_column_order', False):
        if list(df.columns) != schema_col_names:
            errors.append(
                f"Column order or names mismatch (strict order). Expected {schema_col_names}, got {list(df.columns)}."
            )
        for i, col_name in enumerate(df.columns):
            if i < len(expected_cols) and col_name == expected_cols[i]['name']:
                col_schema = expected_cols[i]
                expected_type_str = col_schema.get('type')
                actual_type_str = str(df[col_name].dtype)
                if expected_type_str and actual_type_str != expected_type_str:
                    # For header-only files, pandas reads all as 'object'. This check will likely fail for numeric/bool.
                    # This is correct behavior if data rows are expected for type validation.
                    if not df.empty: # Only do strict type check if there's data
                        errors.append(
                            f"Column '{col_name}' type mismatch. Expected '{expected_type_str}', got '{actual_type_str}'."
                        )
                    elif expected_type_str != 'object': # If header-only, and expected isn't object, it's a potential mismatch
                        errors.append(
                            f"Column '{col_name}' type is '{actual_type_str}' (header-only read), schema expects '{expected_type_str}'. Data rows needed for full type check."
                        )
    else:
        for col_schema in expected_cols:
            col_name = col_schema['name']
            if col_name not in df.columns:
                if col_schema.get('required', True):
                    errors.append(f"Required column '{col_name}' not found.")
            else:
                expected_type_str = col_schema.get('type')
                actual_type_str = str(df[col_name].dtype)
                if expected_type_str and actual_type_str != expected_type_str:
                    if not df.empty: # Only do strict type check if there's data
                        errors.append(
                            f"Column '{col_name}' type mismatch. Expected '{expected_type_str}', got '{actual_type_str}'."
                        )
                    elif expected_type_str != 'object': # If header-only, and expected isn't object, it's a potential mismatch
                         errors.append(
                            f"Column '{col_name}' type is '{actual_type_str}' (header-only read), schema expects '{expected_type_str}'. Data rows needed for full type check."
                        )

    if not schema_definition.get('allow_extra_columns', False):
        extra_columns = set(df.columns) - set(schema_col_names)
        if extra_columns:
            errors.append(f"Found unexpected extra columns: {list(extra_columns)}.")

    return errors

def main():
    print("Starting Schema Validation Process...")
    config = load_config()

    date_params = config.get("date_parameters", {})
    publication_ref_period = date_params.get("publication_reference_period", "unknown_period")

    processed_data_dir = config.get("output_paths", {}).get("processed_data_dir", "data/processed")
    schema_definitions_map = config.get("schema_definitions", {})

    all_validations_passed = True
    validation_summary = {}

    for schema_key, schema_path in schema_definitions_map.items():
        data_file_base = schema_key.replace("_schema", "")
        data_filepath = os.path.join(processed_data_dir, f"{data_file_base}_{publication_ref_period}.csv")

        print(f"\nValidating {data_file_base} ({data_filepath})...")
        print(f"Using schema: {schema_path}")

        schema_def = load_schema(schema_path)
        if not schema_def:
            print(f"ERROR: Could not load schema from {schema_path}. Skipping validation for {data_file_base}.")
            validation_summary[data_file_base] = {"status": "ERROR", "reason": f"Could not load schema: {schema_path}"}
            all_validations_passed = False
            continue

        if not os.path.exists(data_filepath):
            print(f"ERROR: Data file {data_filepath} not found. Skipping validation.")
            validation_summary[data_file_base] = {"status": "ERROR", "reason": f"Data file not found: {data_filepath}"}
            all_validations_passed = False
            continue

        errors = validate_csv_schema(data_filepath, schema_def)

        if not errors:
            print(f"Schema validation PASSED for {data_filepath}.")
            validation_summary[data_file_base] = {"status": "PASSED", "file": data_filepath, "schema": schema_path}
        else:
            print(f"Schema validation FAILED for {data_filepath}:")
            for error in errors:
                print(f"  - {error}")
            validation_summary[data_file_base] = {"status": "FAILED", "file": data_filepath, "schema": schema_path, "errors": errors}
            all_validations_passed = False

    report_file = "schema_validation_report.json"
    with open(report_file, 'w') as f:
        json.dump(validation_summary, f, indent=4)

    # Simplified print statements to avoid any f-string or complex string issues
    print("---")
    print("Schema validation summary report saved to:")
    print(report_file)
    print("---")

    if not all_validations_passed:
        print("---")
        print("One or more schema validations failed.")
        print("---")
        sys.exit(1)
    else:
        print("---")
        print("All schema validations passed successfully!")
        print("---")

if __name__ == "__main__":
    main()
