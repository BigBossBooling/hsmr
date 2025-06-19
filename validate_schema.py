#!/usr/bin/env python3
import csv
import json
import sys

# Define schemas here for simplicity in this environment
# In a real system, these would be in separate JSON schema files or Pydantic models
SCHEMAS = {
    "smr_output.csv": { # Simplified base name
        "columns": [
            # Expected column names and a basic type hint (not strictly enforced by this simple script)
            {"name": "quarter", "type": "string"},
            {"name": "year", "type": "numeric"},
            {"name": "hosp_id", "type": "string"},
            {"name": "smr_value", "type": "numeric"},
            {"name": "predicted_deaths", "type": "numeric"},
            {"name": "actual_deaths", "type": "numeric"},
            {"name": "confidence_lower", "type": "numeric"},
            {"name": "confidence_upper", "type": "numeric"}
        ],
        "min_columns": 8,
        "max_columns": 8
    },
    "trends_output.csv": {
        "columns": [
            {"name": "quarter_ending", "type": "date"}, # e.g. YYYY-MM-DD
            {"name": "metric_name", "type": "string"},
            {"name": "metric_value", "type": "numeric"},
            {"name": "strata", "type": "string"}
        ],
        "min_columns": 4,
        "max_columns": 4
    },
    "open_data_hsmr.csv": { # Assuming a similar structure to SMR output but maybe aggregated
        "columns": [
            {"name": "time_period", "type": "string"}, # e.g., YYYYQ_N
            {"name": "location_code", "type": "string"},
            {"name": "location_type", "type": "string"},
            {"name": "smr", "type": "numeric"},
            {"name": "crude_rate_deaths_per_100_episodes", "type": "numeric"}
        ],
        "min_columns": 5,
        "max_columns": 5
    }
    # Excel schema validation would be different (sheet names, specific cell checks)
    # and is harder with empty files. We'll focus on CSVs.
}

def validate_csv_schema(file_path, schema_name_base):
    """
    Validates the schema of a given CSV file.
    schema_name_base should be like "smr_output.csv" to match SCHEMAS keys.
    """
    validation_results = {
        "file": file_path,
        "schema_name": schema_name_base,
        "status": "FAIL",
        "findings": []
    }

    if schema_name_base not in SCHEMAS:
        validation_results["findings"].append(f"No schema definition found for '{schema_name_base}'.")
        return validation_results

    schema = SCHEMAS[schema_name_base]
    expected_col_names = [col["name"] for col in schema["columns"]]

    try:
        with open(file_path, 'r', newline='') as csvfile:
            reader = csv.reader(csvfile)
            header = next(reader, None)

            if header is None:
                if sum(1 for row in reader) == 0 and open(file_path).read() == "": # Check if truly empty
                     validation_results["findings"].append("File is completely empty (no header, no data). This might be acceptable for placeholders.")
                     validation_results["status"] = "PASS_EMPTY" # Special status for empty files
                     return validation_results
                validation_results["findings"].append("File is empty or header row is missing.")
                return validation_results

            # Column count check
            if "min_columns" in schema and len(header) < schema["min_columns"]:
                validation_results["findings"].append(f"Insufficient columns. Expected at least {schema['min_columns']}, found {len(header)}.")
            if "max_columns" in schema and len(header) > schema["max_columns"]:
                validation_results["findings"].append(f"Too many columns. Expected at most {schema['max_columns']}, found {len(header)}.")

            # Column name check
            if expected_col_names != header:
                missing_cols = set(expected_col_names) - set(header)
                extra_cols = set(header) - set(expected_col_names)
                if missing_cols:
                    validation_results["findings"].append(f"Missing expected columns: {list(missing_cols)}.")
                if extra_cols:
                    validation_results["findings"].append(f"Found unexpected extra columns: {list(extra_cols)}.")
                # Could also check order if schema["strict_order"] = True (not implemented here)

            # Data type checks would go here if the file had data
            # For now, since files are placeholders, we skip deep data type validation.
            # Example for later:
            # for i, row in enumerate(reader):
            #     if len(row) != len(header):
            #         validation_results["findings"].append(f"Row {i+2}: Incorrect number of columns.")
            #         continue
            #     for j, cell_value in enumerate(row):
            #         col_schema = schema["columns"][j]
            #         if col_schema["type"] == "numeric":
            #             try:
            #                 float(cell_value)
            #             except ValueError:
            #                 validation_results["findings"].append(f"Row {i+2}, Col '{col_schema['name']}': Value '{cell_value}' is not numeric.")
            #         # Add other type checks (date, etc.)

            if not validation_results["findings"]:
                validation_results["status"] = "PASS"
                validation_results["findings"].append("Schema validation passed (header check).")

    except FileNotFoundError:
        validation_results["findings"].append("File not found.")
    except Exception as e:
        validation_results["findings"].append(f"An error occurred: {str(e)}")

    return validation_results

if __name__ == "__main__":
    if len(sys.argv) != 3:
        print("Usage: python validate_schema.py <file_path> <schema_name_base>")
        print("Example: python validate_schema.py data/processed/smr_output_2025_Q2.csv smr_output.csv")
        sys.exit(1)

    file_path_arg = sys.argv[1]
    schema_name_arg = sys.argv[2] # e.g., "smr_output.csv"

    result = validate_csv_schema(file_path_arg, schema_name_arg)

    # Output results as JSON to stdout for the calling script to capture
    print(json.dumps(result))
