# qa_scripts/detect_anomalies.py

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

def simulate_anomaly_detection(df, df_name="DataFrame", rules=None):
    """
    Simulates anomaly detection on a Pandas DataFrame.
    'rules' is an optional list of simple rule dictionaries.
    Example rule:
    {
        "rule_name": "High SMR Value",
        "column": "smr_value",
        "condition": "greater_than",
        "threshold": 3.0,
        "description": "SMR value significantly above expected norms."
    }
    {
        "rule_name": "Large Change in Deaths",
        "column": "total_deaths",
        "condition": "percentage_change_from_historical_gt",
        "historical_value": 100, # Dummy historical value
        "threshold_percentage": 50, # +/- 50% change
        "description": "Significant percentage change in total deaths from historical average."
    }
    Returns a list of detected anomaly messages.
    """
    anomalies = []
    if df.empty or len(df.index) == 0: # Check if df has any data rows
        print(f"INFO: DataFrame '{df_name}' has no data rows. Skipping anomaly detection simulation.")
        return anomalies

    if rules is None:
        rules = []

    for rule in rules:
        rule_name = rule.get("rule_name", "Unnamed Anomaly Rule")
        column_name = rule.get("column")
        condition_type = rule.get("condition")
        threshold = rule.get("threshold")
        description = rule.get("description", "")

        if column_name and column_name not in df.columns:
            print(f"WARNING: Column '{column_name}' for anomaly rule '{rule_name}' not found in '{df_name}'. Skipping rule.")
            continue

        try:
            # Ensure data in column is numeric for relevant conditions
            if condition_type in ["greater_than", "percentage_change_from_historical_gt"]:
                if column_name: # Only if column is specified (e.g. not for a generic model rule)
                    # Attempt to convert to numeric, coercing errors. This will turn non-numeric into NaN.
                    numeric_series = pd.to_numeric(df[column_name], errors='coerce')
                else: # If no column, rule might be for whole df - skip numeric conversion here
                    numeric_series = None # Placeholder
            else: # For other types of rules, might not need numeric_series
                numeric_series = df[column_name] if column_name else None


            if condition_type == "greater_than":
                if threshold is not None and numeric_series is not None:
                    flagged_rows = df[numeric_series > threshold] # Use the coerced numeric series
                    if not flagged_rows.empty:
                        anomalies.append({
                            "rule_name": rule_name,
                            "column": column_name,
                            "condition": f"> {threshold}",
                            "num_flagged": len(flagged_rows),
                            "example_values": list(flagged_rows[column_name].head(3)), # Original values for example
                            "description": description
                        })
            elif condition_type == "percentage_change_from_historical_gt":
                historical_value = rule.get("historical_value")
                threshold_percentage = rule.get("threshold_percentage")
                if historical_value is not None and threshold_percentage is not None and numeric_series is not None:
                    current_sum = numeric_series.sum() # Sum of numeric, NaN-coerced values
                    if pd.isna(current_sum): # if all values were non-numeric in column
                        print(f"WARNING: Rule '{rule_name}' for column '{column_name}' could not be applied as sum is NA (column may be non-numeric).")
                        continue

                    percentage_change = ((current_sum - historical_value) / historical_value) * 100 if historical_value != 0 else float('inf')
                    if abs(percentage_change) > threshold_percentage:
                        anomalies.append({
                            "rule_name": rule_name,
                            "column": column_name,
                            "condition": f"abs % change > {threshold_percentage}% from historical {historical_value}",
                            "current_value_sum": float(current_sum), # ensure it's basic float for JSON
                            "percentage_change": round(percentage_change, 2),
                            "description": description
                        })
            # Add more conceptual conditions here
        except Exception as e:
            anomalies.append({
                "rule_name": rule_name,
                "error": f"Error during anomaly rule execution: {str(e)}"
            })

    if not anomalies:
        print(f"No anomalies detected by simulation for '{df_name}'.")
    else:
        print(f"Potential anomalies detected by simulation for '{df_name}':")
        for anom_idx, anom in enumerate(anomalies): # Use enumerate for unique keys if needed for JSON
            print(f"  - {anom.get('rule_name')}: {anom.get('description', '')} (Details: {json.dumps(anom)})") # Print full anom dict for clarity

    return anomalies

def define_anomaly_rules():
    """Defines conceptual anomaly detection rules."""
    rules = {
        "smr_output": [
            {"rule_name": "High SMR Value", "column": "smr_value", "condition": "greater_than", "threshold": 2.5, "description": "Individual SMR value seems unusually high."},
        ],
        "trends_output": [
             {"rule_name": "Large Change in Total Deaths (Trends)", "column": "total_deaths", "condition": "percentage_change_from_historical_gt",
              "historical_value": 50,
              "threshold_percentage": 30,
              "description": "Sum of total_deaths in trends output changed significantly from historical."}
        ]
    }
    return rules

def main():
    print("Starting AI-Assisted Anomaly Detection Process (Conceptual Simulation)...")
    config = load_config()
    anomaly_rules_definitions = define_anomaly_rules()

    date_params = config.get("date_parameters", {})
    publication_ref_period = date_params.get("publication_reference_period", "unknown_period")

    processed_data_dir = config.get("output_paths", {}).get("processed_data_dir", "data/processed")

    overall_anomalies_found = False
    anomaly_summary_report = {}

    files_to_check_config = {
        "smr_output": os.path.join(processed_data_dir, f"smr_output_{publication_ref_period}.csv"),
        "trends_output": os.path.join(processed_data_dir, f"trends_output_{publication_ref_period}.csv")
    }

    for file_key, data_filepath in files_to_check_config.items():
        print(f"\nSimulating anomaly detection for {file_key} ({data_filepath})...")

        if not os.path.exists(data_filepath):
            print(f"WARNING: Data file not found: {data_filepath}. Skipping anomaly detection.")
            anomaly_summary_report[file_key] = {"status": "SKIPPED", "reason": "Data file not found"}
            continue

        try:
            df = pd.read_csv(data_filepath)
        except pd.errors.EmptyDataError: # If file is 0-bytes or only header recognized as empty by pandas
             print(f"INFO: Data file {data_filepath} is empty or header-only. Skipping anomaly detection.")
             anomaly_summary_report[file_key] = {"status": "SKIPPED_EMPTY", "reason": "Data file is empty or header-only"}
             continue
        except Exception as e:
            print(f"ERROR: Failed to read CSV {data_filepath}: {str(e)}")
            anomaly_summary_report[file_key] = {"status": "ERROR", "reason": f"Failed to read CSV: {str(e)}"}
            continue # Don't set overall_anomalies_found to True for read errors, but it's an error state

        file_specific_rules = anomaly_rules_definitions.get(file_key, [])
        detected_anomalies = simulate_anomaly_detection(df, df_name=file_key, rules=file_specific_rules)

        anomaly_summary_report[file_key] = {
            "status": "COMPLETED",
            "file": data_filepath,
            "detected_anomalies_count": len(detected_anomalies),
            "detected_anomalies_details": detected_anomalies if detected_anomalies else "None"
        }
        if detected_anomalies:
            overall_anomalies_found = True

    report_file = "anomaly_detection_report.json"
    with open(report_file, 'w') as f:
        json.dump(anomaly_summary_report, f, indent=4)
    print(f"\nAnomaly detection simulation summary report saved to {report_file}")

    if overall_anomalies_found:
        print("\nPotential anomalies were detected and reported. These require human review.")
    else:
        print("\nNo anomalies detected by simulation.")

if __name__ == "__main__":
    main()
