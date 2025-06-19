# scripts/create_smr_data.R

# Load necessary libraries
if (!requireNamespace("jsonlite", quietly = TRUE)) install.packages("jsonlite", repos = "https://cloud.r-project.org/")
if (!requireNamespace("readr", quietly = TRUE)) install.packages("readr", repos = "https://cloud.r-project.org/")
if (!requireNamespace("digest", quietly = TRUE)) install.packages("digest", repos = "https://cloud.r-project.org/")
if (!requireNamespace("here", quietly = TRUE)) install.packages("here", repos = "https://cloud.r-project.org/")
# Add other specific libraries like dplyr, tidyr if used directly here or in sourced scripts

library(jsonlite)
library(readr)
library(digest)
library(here)

# Source sub-scripts (assuming they are in the same 'scripts' directory)
source(here::here("scripts", "smr_wrangling.R"))
source(here::here("scripts", "smr_pmorbs.R"))
source(here::here("scripts", "smr_model.R"))

# --- Configuration ---
config_file <- here::here("hsmr_config.json") # Assumes config is in root (downloaded by GHA)

# --- Helper Function for Hash Verification ---
verify_input_hash <- function(input_filepath, expected_hash_filepath) {
  if (!file.exists(input_filepath)) {
    stop(paste("Input file not found:", input_filepath))
  }
  if (!file.exists(expected_hash_filepath)) {
    # If the hash file itself is missing, it's an issue with previous steps or setup
    stop(paste("Expected hash file not found:", expected_hash_filepath,
               "This indicates an issue with the artifact from Phase 2 or its generation."))
  }

  expected_hash <- trimws(readLines(expected_hash_filepath, n = 1, warn = FALSE))
  calculated_hash <- digest::digest(input_filepath, algo = "sha256", file = TRUE)

  if (calculated_hash != expected_hash) {
    stop(paste("Hash mismatch for input file:", input_filepath,
               "
  Expected:", expected_hash,
               "
  Actual  :", calculated_hash,
               "
Data integrity check failed. Ensure the input data is the correct version from Phase 2."))
  }
  cat("Input file hash verified for:", input_filepath, "
")
  return(TRUE)
}


# --- Main Function ---
main <- function() {
  cat("Starting SMR data production process...
")

  # Load configuration
  if (!file.exists(config_file)) {
    stop("hsmr_config.json not found! It should be available from Phase 2 artifacts.")
  }
  config <- jsonlite::read_json(config_file)
  cat("Configuration loaded successfully.
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

  # Define input SMR extract file (example name)
  smr_input_filename <- paste0("smr_extract_", date_params$publication_reference_period, ".csv")
  smr_input_filepath <- file.path(raw_data_dir, smr_input_filename)
  smr_input_hash_filepath <- paste0(smr_input_filepath, ".sha256")

  # Verify hash of input SMR extract CSV
  verify_input_hash(smr_input_filepath, smr_input_hash_filepath)

  # Load raw SMR data
  # Explicitly define column types for empty file scenario to avoid issues with placeholders
  # The actual smr_extract from Phase 2.2 has: patient_id, admission_date, discharge_date, diagnosis_code_1, discharged_alive_status
  col_types_spec <- readr::cols(
      patient_id = readr::col_integer(),
      admission_date = readr::col_date(),
      discharge_date = readr::col_date(),
      diagnosis_code_1 = readr::col_character(),
      discharged_alive_status = readr::col_integer()
      # Add any other columns from the actual (simulated) extract in extract_database_data.R
      # For example, if smr_wrangling expects more, ensure they are here or handled.
      # The current dummy extract_database_data.R creates these 5 columns.
  )
  raw_smr_df <- readr::read_csv(smr_input_filepath, col_types = col_types_spec, show_col_types = FALSE)
  cat("Raw SMR data loaded from:", smr_input_filepath, "
")

  # --- Load relevant lookup files ---
  # This part will read from config$reference_file_manifest
  lookup_data <- list()
  if (!is.null(config$reference_file_manifest) && length(config$reference_file_manifest) > 0) {
    cat("Loading lookup files specified in manifest...
")
    for (lookup_info in config$reference_file_manifest) {
      lookup_name <- gsub("\\.csv$", "", lookup_info$name) # Use base name as list key
      lookup_path <- here::here(lookup_info$path)
      lookup_hash_path <- paste0(lookup_path, ".sha256") # Assuming convention for lookup hashes

      # Verify lookup file hash (if a .sha256 file exists for it)
      # For this simulation, we assume lookup hashes are NOT YET generated/enforced for lookups themselves,
      # but verify_reference_files.R in Phase 2 *did* check them against the config.
      # So here, we just load them. If verify_reference_files.R passed, they are good.
      if (!file.exists(lookup_path)) {
          stop(paste("Lookup file specified in manifest not found:", lookup_path))
      }
      lookup_data[[lookup_name]] <- readr::read_csv(lookup_path, show_col_types = FALSE)
      cat("Loaded lookup:", lookup_info$name, "into lookup_data$",lookup_name,"
")
    }
  } else {
    cat("No lookup files listed in manifest or manifest is empty.
")
  }


  # --- Execute SMR Processing Steps (Simulated) ---
  wrangled_df <- perform_smr_wrangling(raw_smr_df, lookup_data)
  pmorbs_df <- create_smr_pmorbs(wrangled_df)
  smr_model_output_df <- run_smr_model(pmorbs_df)

  # Define output SMR data file
  smr_output_filename <- paste0("smr_output_", date_params$publication_reference_period, ".csv")
  smr_output_filepath <- file.path(processed_data_dir, smr_output_filename)

  # Save processed SMR data
  readr::write_csv(smr_model_output_df, smr_output_filepath)
  cat("Processed SMR data saved to:", smr_output_filepath, "
")

  # Calculate and save SHA256 hash of the SMR output CSV
  output_hash <- digest::digest(smr_output_filepath, algo = "sha256", file = TRUE)
  output_hash_filepath <- paste0(smr_output_filepath, ".sha256")
  writeLines(output_hash, output_hash_filepath)
  cat("SHA256 hash for SMR output saved to:", output_hash_filepath, "(Hash:", output_hash, ")
")

  cat("
SMR data production process completed.
")
}

# Run the main function
tryCatch({
  main()
}, error = function(e) {
  cat("Error in create_smr_data.R: ", e$message, "
")
  stop(e) # Re-throw error to fail GHA step
})
