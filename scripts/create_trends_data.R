# scripts/create_trends_data.R

# Load necessary libraries
if (!requireNamespace("jsonlite", quietly = TRUE)) install.packages("jsonlite", repos = "https://cloud.r-project.org/")
if (!requireNamespace("readr", quietly = TRUE)) install.packages("readr", repos = "https://cloud.r-project.org/")
if (!requireNamespace("digest", quietly = TRUE)) install.packages("digest", repos = "https://cloud.r-project.org/")
if (!requireNamespace("here", quietly = TRUE)) install.packages("here", repos = "https://cloud.r-project.org/")

library(jsonlite)
library(readr)
library(digest)
library(here)

# Source sub-scripts
source(here::here("scripts", "create_trends.R")) # Contains calculate_trends_data

# --- Configuration ---
config_file <- here::here("hsmr_config.json") # Assumes config is in root

# --- Helper Function for Hash Verification (can be moved to a shared utils.R if used by multiple scripts) ---
verify_input_hash <- function(input_filepath, expected_hash_filepath) {
  if (!file.exists(input_filepath)) {
    stop(paste("Input file not found for trends:", input_filepath))
  }
  if (!file.exists(expected_hash_filepath)) {
    # For trends, some inputs might be optional or historical, so this might be a warning
    # However, if the primary input (current SMR extract) hash is missing, it's an issue.
    stop(paste("Expected hash file not found for trends input:", expected_hash_filepath,
               "This indicates an issue with Phase 2 output generation or artifact handling."))
  }

  expected_hash <- trimws(readLines(expected_hash_filepath, n = 1, warn = FALSE))
  calculated_hash <- digest::digest(input_filepath, algo = "sha256", file = TRUE)

  if (calculated_hash != expected_hash) {
    stop(paste("Hash mismatch for input file for trends:", input_filepath,
               "
  Expected:", expected_hash,
               "
  Actual  :", calculated_hash))
  }
  cat("Input file hash verified for trends:", input_filepath, "
")
  return(TRUE)
}

# --- Main Function ---
main <- function() {
  cat("Starting Trends data production process...
")

  # Load configuration
  if (!file.exists(config_file)) {
    stop("hsmr_config.json not found! It should be available from Phase 2 artifacts.")
  }
  config <- jsonlite::read_json(config_file)
  cat("Configuration loaded successfully for trends.
")

  date_params <- config$date_parameters
  raw_data_dir <- here::here(config$output_paths$raw_data_dir)
  processed_data_dir <- here::here(config$output_paths$processed_data_dir)

  # Create processed data directory if it doesn't exist
  if (!dir.exists(processed_data_dir)) {
    dir.create(processed_data_dir, recursive = TRUE)
    cat("Created directory:", processed_data_dir, "
")
  }

  # --- Load Input Data for Trends ---
  # For this simulation, we'll re-use the SMR extract from the current period.
  # A real trends process would likely involve loading and appending historical trend data.
  smr_input_filename <- paste0("smr_extract_", date_params$publication_reference_period, ".csv")
  smr_input_filepath <- file.path(raw_data_dir, smr_input_filename)
  smr_input_hash_filepath <- paste0(smr_input_filepath, ".sha256")

  # Verify hash of the input SMR extract (as it's being reused here)
  verify_input_hash(smr_input_filepath, smr_input_hash_filepath)

  # Define col_types for current_period_data_df to match create_smr_data.R and extract_database_data.R
  col_types_spec <- readr::cols(
      patient_id = readr::col_integer(),
      admission_date = readr::col_date(), # Important for trends script
      discharge_date = readr::col_date(),
      diagnosis_code_1 = readr::col_character(),
      discharged_alive_status = readr::col_integer()
      # Ensure this matches the structure of the (simulated) smr_extract file
  )
  current_period_data_df <- readr::read_csv(smr_input_filepath, col_types = col_types_spec, show_col_types = FALSE)
  cat("Current period data for trends loaded from:", smr_input_filepath, "
")

  input_data_for_trends <- list(smr_extract_current_period = current_period_data_df)
  # In a real scenario, add historical data to this list:
  # input_data_for_trends$historical_trends <- read_csv(here::here(processed_data_dir, "historical_trends_master.csv"))


  # --- Execute Trends Calculation (Simulated) ---
  trends_output_df <- calculate_trends_data(input_data_for_trends, date_params)

  # Define output trends data file
  trends_output_filename <- paste0("trends_output_", date_params$publication_reference_period, ".csv")
  trends_output_filepath <- file.path(processed_data_dir, trends_output_filename)

  # Save processed trends data
  readr::write_csv(trends_output_df, trends_output_filepath)
  cat("Processed trends data saved to:", trends_output_filepath, "
")

  # Calculate and save SHA256 hash of the trends output CSV
  output_hash <- digest::digest(trends_output_filepath, algo = "sha256", file = TRUE)
  output_hash_filepath <- paste0(trends_output_filepath, ".sha256")
  writeLines(output_hash, output_hash_filepath)
  cat("SHA256 hash for trends output saved to:", output_hash_filepath, "(Hash:", output_hash, ")
")

  cat("
Trends data production process completed.
")
}

# Run the main function
tryCatch({
  main()
}, error = function(e) {
  cat("Error in create_trends_data.R: ", e$message, "
")
  stop(e) # Re-throw error to fail GHA step
})
