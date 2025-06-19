# scripts/create_excel_tables.R

# Load necessary libraries
if (!requireNamespace("jsonlite", quietly = TRUE)) install.packages("jsonlite", repos = "https://cloud.r-project.org/")
if (!requireNamespace("readr", quietly = TRUE)) install.packages("readr", repos = "https://cloud.r-project.org/")
if (!requireNamespace("digest", quietly = TRUE)) install.packages("digest", repos = "https://cloud.r-project.org/")
if (!requireNamespace("here", quietly = TRUE)) install.packages("here", repos = "https://cloud.r-project.org/")
# For actual Excel, you'd use openxlsx or writexl
# if (!requireNamespace("openxlsx", quietly = TRUE)) install.packages("openxlsx", repos = "https://cloud.r-project.org/")

library(jsonlite)
library(readr)
library(digest)
library(here)
# library(openxlsx) # For actual Excel file handling

# --- Configuration ---
config_file <- here::here("hsmr_config.json") # Assumes config is in root

# --- Helper Function for Hash Verification ---
verify_input_hash <- function(input_filepath, expected_hash_filepath, file_description = "Input file") {
  if (!file.exists(input_filepath)) {
    stop(paste(file_description, "not found:", input_filepath))
  }
  if (!file.exists(expected_hash_filepath)) {
    # For this script, inputs are expected to have hashes from previous processing steps
    stop(paste("Expected hash file not found for", file_description, ":", expected_hash_filepath,
                "This indicates an issue with prior data processing or artifact handling."))
  }

  expected_hash <- trimws(readLines(expected_hash_filepath, n = 1, warn = FALSE))
  calculated_hash <- digest::digest(input_filepath, algo = "sha256", file = TRUE)

  if (calculated_hash != expected_hash) {
    stop(paste("Hash mismatch for", file_description, ":", input_filepath,
               "
  Expected:", expected_hash,
               "
  Actual  :", calculated_hash))
  }
  cat("Input file hash verified for:", file_description, "(", input_filepath, ")
")
  return(TRUE)
}

# --- Main Function ---
main <- function() {
  cat("Starting Excel tables generation process (simulated with CSV)...
")

  # Load configuration
  if (!file.exists(config_file)) {
    stop("hsmr_config.json not found! It should be available from previous GHA steps.")
  }
  config <- jsonlite::read_json(config_file)
  cat("Configuration loaded successfully for table generation.
")

  date_params <- config$date_parameters
  processed_data_dir <- here::here(config$output_paths$processed_data_dir)
  final_output_dir <- here::here(config$output_paths$final_output_dir) # Using 'final_output_dir' from config

  # Create final output directory if it doesn't exist
  if (!dir.exists(final_output_dir)) {
    dir.create(final_output_dir, recursive = TRUE)
    cat("Created directory:", final_output_dir, "
")
  }

  # --- Load Processed Data ---
  smr_output_filename <- paste0("smr_output_", date_params$publication_reference_period, ".csv")
  smr_output_filepath <- file.path(processed_data_dir, smr_output_filename)
  smr_output_hash_filepath <- paste0(smr_output_filepath, ".sha256")
  verify_input_hash(smr_output_filepath, smr_output_hash_filepath, "SMR output data")

  col_types_smr <- readr::cols( # Define to handle placeholder empty files gracefully
      .default = readr::col_guess() # Keep default guessing for most
      # Ensure specific columns from smr_model_output_df are correctly typed if known
      # For example, if 'smr_value' is critical and numeric:
      # smr_value = readr::col_double()
  )
  smr_data_df <- readr::read_csv(smr_output_filepath, col_types = col_types_smr, show_col_types = FALSE)
  cat("SMR output data loaded from:", smr_output_filepath, "
")

  trends_output_filename <- paste0("trends_output_", date_params$publication_reference_period, ".csv")
  trends_output_filepath <- file.path(processed_data_dir, trends_output_filename)
  trends_output_hash_filepath <- paste0(trends_output_filepath, ".sha256")
  verify_input_hash(trends_output_filepath, trends_output_hash_filepath, "Trends output data")

  col_types_trends <- readr::cols( # Define to handle placeholder empty files
      time_period = readr::col_character(),
      total_admissions = readr::col_integer(),
      total_deaths = readr::col_integer(),
      crude_mortality_rate = readr::col_double()
  )
  trends_data_df <- readr::read_csv(trends_output_filepath, col_types = col_types_trends, show_col_types = FALSE)
  cat("Trends output data loaded from:", trends_output_filepath, "
")

  # --- Load Template (CSV Template for Simulation) ---
  template_entry <- Filter(function(x) x$name == "hsmr_report_template.csv" && x$type == "template", config$reference_file_manifest)
  if (length(template_entry) == 0 || length(template_entry[[1]]$path) == 0) {
    stop("HSMR report template 'hsmr_report_template.csv' with type 'template' not found in config manifest or path is empty.")
  }
  template_path_from_config <- template_entry[[1]]$path
  template_filepath <- here::here(template_path_from_config)

  # Hash for template should have been verified by verify_reference_files.R in Phase 2.
  # We can re-verify here by extracting the expected hash from config for this specific template.
  template_expected_hash <- template_entry[[1]]$expected_hash
  # Create a dummy hash file path for the helper, or pass hash directly if helper is modified
  # For now, we'll assume verify_reference_files.R did its job.
  cat("Using template (CSV for simulation):", template_filepath, " (Integrity assumed from Phase 2 verification)
")

  if (!file.exists(template_filepath)) {
      stop(paste("Template file not found:", template_filepath))
  }
  template_lines <- readLines(template_filepath, warn = FALSE)


  # --- Simulate Populating Template and Save Output ---
  # For simulation with CSV, we'll create a single CSV output file.
  # A real Excel process would involve writing to different sheets, formatting, etc.

  # Using .xlsx extension for the output file as per original plan, even if content is CSV for simulation
  final_tables_filename <- paste0("final_hsmr_tables_", date_params$publication_reference_period, ".xlsx")
  final_tables_filepath <- file.path(final_output_dir, final_tables_filename)

  # Start with template header (simulating different "sheets" or tables)
  writeLines(c("--- Template Introduction ---"), final_tables_filepath) # Simulate a section
  writeLines(template_lines, final_tables_filepath, sep="
") # Write template content

  # Append SMR data (simulated - actual Excel would place this in a specific sheet/location)
  cat("

--- SMR Data ---
", file = final_tables_filepath, append = TRUE)
  # write header of smr_data_df only if it has rows
  if(nrow(smr_data_df) > 0) {
      write.table(smr_data_df, final_tables_filepath, sep = ",", row.names = FALSE, col.names = TRUE, append = TRUE, quote = TRUE)
  } else {
      write(names(smr_data_df), file=final_tables_filepath, ncolumns=length(names(smr_data_df)), append=TRUE, sep=",") # just header
  }

  # Append Trends data (simulated)
  cat("

--- Trends Data ---
", file = final_tables_filepath, append = TRUE)
  if(nrow(trends_data_df) > 0) {
      write.table(trends_data_df, final_tables_filepath, sep = ",", row.names = FALSE, col.names = TRUE, append = TRUE, quote = TRUE)
  } else {
      write(names(trends_data_df), file=final_tables_filepath, ncolumns=length(names(trends_data_df)), append=TRUE, sep=",") # just header
  }

  cat("Simulated Excel tables (as structured CSV content) saved to:", final_tables_filepath, "
")

  # Calculate and save SHA256 hash of the final output file
  output_hash <- digest::digest(final_tables_filepath, algo = "sha256", file = TRUE)
  output_hash_filepath <- paste0(final_tables_filepath, ".sha256")
  writeLines(output_hash, output_hash_filepath)
  cat("SHA256 hash for final tables output saved to:", output_hash_filepath, "(Hash:", output_hash, ")
")

  cat("
Excel tables generation process completed (simulated with CSV content in .xlsx file).
")
}

# Run the main function
tryCatch({
  main()
}, error = function(e) {
  cat("Error in create_excel_tables.R: ", e$message, "
")
  stop(e) # Re-throw error to fail GHA step
})
