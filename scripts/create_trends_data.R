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
    # However, if the primary input (current SMR output) hash is missing, it's an issue.
    stop(paste("Expected hash file not found for trends input:", expected_hash_filepath,
               "This indicates an issue with Phase 3 (SMR output) generation or artifact handling."))
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
  # INPUT DATA NOW COMES FROM PROCESSED_DATA_DIR
  processed_data_dir <- here::here(config$output_paths$processed_data_dir)

  if (!dir.exists(processed_data_dir)) {
    warning(paste("Processed data directory not found, though expected:", processed_data_dir))
    dir.create(processed_data_dir, recursive = TRUE, showWarnings = FALSE)
    cat("Created directory (or ensured it exists):", processed_data_dir, "
")
  }

  # --- Load Input Data for Trends ---
  # NOW USING SMR OUTPUT AS THE BASE FOR CURRENT PERIOD'S TRENDS
  current_period_input_filename <- paste0("smr_output_", date_params$publication_reference_period, ".csv")
  current_period_input_filepath <- file.path(processed_data_dir, current_period_input_filename)
  current_period_input_hash_filepath <- paste0(current_period_input_filepath, ".sha256")

  verify_input_hash(current_period_input_filepath, current_period_input_hash_filepath)

  # Define col_types for smr_output_...csv
  # Based on smr_model.R output, includes: patient_id, admission_date, discharge_date, diagnosis_code_1,
  # discharged_alive_status, wrangled_indicator, age_group, comorbidity_score,
  # predicted_mortality_prob, smr_value
  # Ensure all columns from the smr_output placeholder/simulation are listed here.
  col_types_spec_smr_output <- readr::cols(
      patient_id = readr::col_integer(), # From original raw data via wrangling
      admission_date = readr::col_date(), # From original raw data
      discharge_date = readr::col_date(), # From original raw data
      diagnosis_code_1 = readr::col_character(), # From original raw data
      discharged_alive_status = readr::col_integer(), # From original raw data
      wrangled_indicator = readr::col_logical(), # Added in smr_wrangling.R
      age_group = readr::col_factor(levels = c("Young", "Mid", "Old")), # Added in smr_pmorbs.R
      comorbidity_score = readr::col_integer(), # Added in smr_pmorbs.R
      predicted_mortality_prob = readr::col_double(), # Added in smr_model.R
      smr_value = readr::col_double() # Added in smr_model.R
      # Any other columns passed through or created by the smr scripts should be defined
  )
  current_period_data_df <- readr::read_csv(current_period_input_filepath, col_types = col_types_spec_smr_output, show_col_types = FALSE)
  cat("Current period SMR output data for trends loaded from:", current_period_input_filepath, "
")

  input_data_for_trends <- list(smr_output_current_period = current_period_data_df)
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
