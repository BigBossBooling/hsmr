# --- Refactored Script: create_smr_data.R ---

# Purpose: This script orchestrates the creation of all data sets
# for the SMR pipeline. It now loads configuration from config.yml
# and uses dedicated functions for modularity.

library(hsmr)
library(here)
library(yaml)
library(dplyr)

# 1. Load Configuration and Dependencies
# This step replaces hardcoded paths and values.
config <- yaml::read_yaml(here("config.yml"))

source(here("R", "load_functions.R"))
source(here("R", "smr_calculation_functions.R"))

# 2. Get Secure Database Credentials
# This now uses environment variables for automation.
db_user <- Sys.getenv("DB_USERNAME")
db_pass <- Sys.getenv("DB_PASSWORD")

if (db_user == "" || db_pass == "") {
  stop("Database credentials not found in environment variables. Pipeline cannot proceed.")
}

# 3. Load and Prepare Core Data
# Uses a refactored function from the hsmr package.
raw_data <- load_and_prepare_data(config, db_user, db_pass)


# 4. Calculate SMRs
# Core logic is now isolated in the hsmr package.
final_smrs <- calculate_smrs(raw_data, config)

# 5. Prepare Data for Public Dashboard
# New, dedicated function for modularity and clarity.
public_dashboard_data <- create_public_dashboard_data(
  final_smrs,
  config
)

# 6. Save Outputs
save_data_to_file(final_smrs, here(config$outputs_dir, "smrs_hospital.csv"))
save_data_to_file(public_dashboard_data, here(config$outputs_dir, "public_dashboard_data.csv"))

message("SMR data pipeline successfully completed.")
