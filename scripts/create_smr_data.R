# scripts/create_smr_data.R

# Load necessary libraries
# Using if(!requireNamespace) for GHA where packages are installed by setup-r-dependencies
if (!requireNamespace("jsonlite", quietly = TRUE)) { print("Installing jsonlite"); install.packages("jsonlite", repos = "https://cloud.r-project.org/", quiet=TRUE) }
if (!requireNamespace("readr", quietly = TRUE)) { print("Installing readr"); install.packages("readr", repos = "https://cloud.r-project.org/", quiet=TRUE) }
if (!requireNamespace("digest", quietly = TRUE)) { print("Installing digest"); install.packages("digest", repos = "https://cloud.r-project.org/", quiet=TRUE) }
if (!requireNamespace("here", quietly = TRUE)) { print("Installing here"); install.packages("here", repos = "https://cloud.r-project.org/", quiet=TRUE) }
if (!requireNamespace("logger", quietly = TRUE)) { print("Installing logger"); install.packages("logger", repos = "https://cloud.r-project.org/", quiet=TRUE) }

library(jsonlite)
library(readr)
library(digest)
library(here)
library(logger) # Added logger

# Configure logger
# Basic configuration: Log INFO and above to console with a timestamp and level
log_threshold(INFO)
# Default formatter_glue is good. Example of a more custom one if needed:
# log_layout(layout_glue('[{time}] [{level}] [{fn}] {msg}'))
# Using default for now, which includes time, level, namespace (if applicable), and message.

# Source sub-scripts
# These sub-scripts still use cat(), their output will go to stdout alongside logger messages.
# For full structured logging, they would also need to be updated to use logger.
source(here::here("scripts", "smr_wrangling.R"))
source(here::here("scripts", "smr_pmorbs.R"))
source(here::here("scripts", "smr_model.R"))

config_file <- here::here("hsmr_config.json")

verify_input_hash <- function(input_filepath, expected_hash_filepath) {
  log_debug(paste("Verifying hash for input file:", input_filepath))
  if (!file.exists(input_filepath)) {
    err_msg <- paste("Input file not found:", input_filepath)
    log_fatal(err_msg)
    stop(err_msg)
  }
  if (!file.exists(expected_hash_filepath)) {
    err_msg <- paste("Expected hash file not found:", expected_hash_filepath,
               "This indicates an issue with the artifact from Phase 2 or its generation.")
    log_fatal(err_msg)
    stop(err_msg)
  }

  expected_hash <- trimws(readLines(expected_hash_filepath, n = 1, warn = FALSE))
  calculated_hash <- digest::digest(input_filepath, algo = "sha256", file = TRUE)

  if (calculated_hash != expected_hash) {
    err_msg <- paste("Hash mismatch for input file:", input_filepath,
               "\n  Expected:", expected_hash, "\n  Actual  :", calculated_hash,
               "\nData integrity check failed. Ensure the input data is the correct version from Phase 2.")
    log_fatal(err_msg)
    stop(err_msg)
  }
  log_info(paste("Input file hash verified for:", input_filepath))
  return(TRUE)
}

main <- function() {
  log_info("Starting SMR data production process...")

  if (!file.exists(config_file)) {
    err_msg <- "hsmr_config.json not found! It should be available from Phase 2 artifacts."
    log_fatal(err_msg)
    stop(err_msg)
  }
  config <- jsonlite::read_json(config_file)
  log_info("Configuration loaded successfully.")

  date_params <- config$date_parameters
  raw_data_dir <- here::here(config$output_paths$raw_data_dir)
  processed_data_dir <- here::here(config$output_paths$processed_data_dir)

  if (!dir.exists(processed_data_dir)) {
    dir.create(processed_data_dir, recursive = TRUE)
    log_info(paste("Created directory:", processed_data_dir))
  }

  smr_input_filename <- paste0("smr_extract_", date_params$publication_reference_period, ".csv")
  smr_input_filepath <- file.path(raw_data_dir, smr_input_filename)
  smr_input_hash_filepath <- paste0(smr_input_filepath, ".sha256")

  verify_input_hash(smr_input_filepath, smr_input_hash_filepath)

  col_types_spec <- readr::cols(
      patient_id = readr::col_integer(), admission_date = readr::col_date(),
      discharge_date = readr::col_date(), diagnosis_code_1 = readr::col_character(),
      discharged_alive_status = readr::col_integer()
  )
  raw_smr_df <- readr::read_csv(smr_input_filepath, col_types = col_types_spec, show_col_types = FALSE)
  log_info(paste("Raw SMR data loaded from:", smr_input_filepath, "(Rows:", nrow(raw_smr_df), ")"))

  lookup_data <- list()
  if (!is.null(config$reference_file_manifest) && length(config$reference_file_manifest) > 0) {
    log_info("Loading lookup files specified in manifest...")
    for (lookup_info in config$reference_file_manifest) {
      # Use a more robust way to create a key name, e.g. remove extension and sanitize
      lookup_key_name <- gsub("[^[:alnum:]_]", "_", tools::file_path_sans_ext(lookup_info$name))

      lookup_path <- here::here(lookup_info$path)
      if (!file.exists(lookup_path)) {
          err_msg <- paste("Lookup file specified in manifest not found:", lookup_path)
          log_error(err_msg) # Log as error, but stop will be handled by main tryCatch
          stop(err_msg)
      }
      lookup_data[[lookup_key_name]] <- readr::read_csv(lookup_path, show_col_types = FALSE)
      log_info(paste("Loaded lookup:", lookup_info$name, "into lookup_data$",lookup_key_name))
    }
  } else {
    log_info("No lookup files listed in manifest or manifest is empty.")
  }

  log_info("Executing SMR Processing Steps (Simulated)...")
  wrangled_df <- perform_smr_wrangling(raw_smr_df, lookup_data)
  pmorbs_df <- create_smr_pmorbs(wrangled_df)
  smr_model_output_df <- run_smr_model(pmorbs_df)
  log_info("SMR Processing Steps completed (Simulated).")

  smr_output_filename <- paste0("smr_output_", date_params$publication_reference_period, ".csv")
  smr_output_filepath <- file.path(processed_data_dir, smr_output_filename)

  readr::write_csv(smr_model_output_df, smr_output_filepath)
  log_info(paste("Processed SMR data saved to:", smr_output_filepath, "(Rows:", nrow(smr_model_output_df), ")"))

  output_hash <- digest::digest(smr_output_filepath, algo = "sha256", file = TRUE)
  output_hash_filepath <- paste0(smr_output_filepath, ".sha256")
  writeLines(output_hash, output_hash_filepath)
  log_info(paste("SHA256 hash for SMR output saved to:", output_hash_filepath, "(Hash:", output_hash, ")"))

  log_info("SMR data production process completed.")
}

tryCatch({
  main()
}, error = function(e) {
  # Log the fatal error before stopping. The stop() call itself will also print the message to stderr.
  log_fatal(paste("CRITICAL ERROR in create_smr_data.R:", conditionMessage(e)))
  # Ensure the script exits with a non-zero status
  quit(status = 1, save = "no")
})
