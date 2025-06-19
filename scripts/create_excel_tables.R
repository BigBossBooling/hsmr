# scripts/create_excel_tables.R

# Load necessary libraries
if (!requireNamespace("jsonlite", quietly = TRUE)) {cat("Installing jsonlite (required by create_excel_tables.R)
"); install.packages("jsonlite", repos = "https://cloud.r-project.org/", quiet = TRUE)}
if (!requireNamespace("readr", quietly = TRUE)) {cat("Installing readr (required by create_excel_tables.R)
"); install.packages("readr", repos = "https://cloud.r-project.org/", quiet = TRUE)}
if (!requireNamespace("digest", quietly = TRUE)) {cat("Installing digest (required by create_excel_tables.R)
"); install.packages("digest", repos = "https://cloud.r-project.org/", quiet = TRUE)}
if (!requireNamespace("here", quietly = TRUE)) {cat("Installing here (required by create_excel_tables.R)
"); install.packages("here", repos = "https://cloud.r-project.org/", quiet = TRUE)}
if (!requireNamespace("openxlsx", quietly = TRUE)) {cat("Installing openxlsx (required by create_excel_tables.R)
"); install.packages("openxlsx", repos = "https://cloud.r-project.org/", quiet = TRUE)}


library(jsonlite)
library(readr)
library(digest)
library(here)
library(openxlsx) # For actual Excel file handling

# --- Configuration ---
config_file <- here::here("hsmr_config.json")

# --- Helper Function for Hash Verification ---
verify_input_hash <- function(input_filepath, expected_hash_filepath, file_description = "Input file") {
  if (!file.exists(input_filepath)) {
    stop(paste(file_description, "not found:", input_filepath))
  }
  if (!file.exists(expected_hash_filepath)) {
    stop(paste("Expected hash file not found for", file_description, ":", expected_hash_filepath,
                "This indicates an issue with prior data processing or artifact handling."))
  }
  expected_hash <- trimws(readLines(expected_hash_filepath, n = 1, warn = FALSE))
  calculated_hash <- digest::digest(input_filepath, algo = "sha256", file = TRUE)
  if (calculated_hash != expected_hash) {
    stop(paste("Hash mismatch for", file_description, ":", input_filepath,
               "
  Expected:", expected_hash, "
  Actual  :", calculated_hash))
  }
  cat("Input file hash verified for:", file_description, "(", input_filepath, ")
")
  return(TRUE)
}

# --- Main Function ---
main <- function() {
  cat("Starting Excel tables generation process...
")

  if (!requireNamespace("openxlsx", quietly = TRUE)) {
      # This check is more of a fallback; GHA should have installed it.
      # If it's still not found, then there's a fundamental env issue.
      cat("CRITICAL ERROR: openxlsx package is not available even after attempting install. Cannot generate real Excel file.
")
      stop("openxlsx package is required but not installed/loadable. Please update R environment dependencies.")
  }


  config <- jsonlite::read_json(config_file)
  cat("Configuration loaded successfully for table generation.
")

  date_params <- config$date_parameters
  processed_data_dir <- here::here(config$output_paths$processed_data_dir)
  final_output_dir <- here::here(config$output_paths$final_output_dir)

  if (!dir.exists(final_output_dir)) {
    dir.create(final_output_dir, recursive = TRUE)
    cat("Created directory:", final_output_dir, "
")
  }

  # Load Processed Data (SMR and Trends)
  smr_output_filename <- paste0("smr_output_", date_params$publication_reference_period, ".csv")
  smr_output_filepath <- file.path(processed_data_dir, smr_output_filename)
  smr_output_hash_filepath <- paste0(smr_output_filepath, ".sha256")
  verify_input_hash(smr_output_filepath, smr_output_hash_filepath, "SMR output data")

  # Define col_types for smr_output_...csv to handle placeholders correctly
  col_types_smr <- readr::cols(
      patient_id = readr::col_integer(),
      admission_date = readr::col_date(),
      discharge_date = readr::col_date(),
      diagnosis_code_1 = readr::col_character(),
      discharged_alive_status = readr::col_integer(),
      wrangled_indicator = readr::col_logical(),
      age_group = readr::col_factor(levels = c("Young", "Mid", "Old")),
      comorbidity_score = readr::col_integer(),
      predicted_mortality_prob = readr::col_double(),
      smr_value = readr::col_double()
  )
  smr_data_df <- readr::read_csv(smr_output_filepath, col_types = col_types_smr, show_col_types = FALSE)
  cat("SMR output data loaded from:", smr_output_filepath, " (Rows: ", nrow(smr_data_df), ")
")

  trends_output_filename <- paste0("trends_output_", date_params$publication_reference_period, ".csv")
  trends_output_filepath <- file.path(processed_data_dir, trends_output_filename)
  trends_output_hash_filepath <- paste0(trends_output_filepath, ".sha256")
  verify_input_hash(trends_output_filepath, trends_output_hash_filepath, "Trends output data")

  col_types_trends <- readr::cols(
      time_period = readr::col_character(),
      total_admissions = readr::col_integer(),
      total_deaths = readr::col_integer(),
      crude_mortality_rate = readr::col_double()
  )
  trends_data_df <- readr::read_csv(trends_output_filepath, col_types = col_types_trends, show_col_types = FALSE)
  cat("Trends output data loaded from:", trends_output_filepath, " (Rows: ", nrow(trends_data_df), ")
")

  # --- Generate Real Excel File ---
  final_tables_filename <- paste0("final_hsmr_tables_", date_params$publication_reference_period, ".xlsx")
  final_tables_filepath <- file.path(final_output_dir, final_tables_filename)

  wb <- openxlsx::createWorkbook()

  # SMR Data Sheet
  openxlsx::addWorksheet(wb, "SMR_Data")
  openxlsx::writeData(wb, sheet = "SMR_Data", x = paste("SMR Data for Period:", date_params$publication_reference_period), startCol = 1, startRow = 1)
  # Check if smr_data_df has columns before trying to write it, to avoid error with 0-col df
  if (ncol(smr_data_df) > 0) {
    openxlsx::writeData(wb, sheet = "SMR_Data", x = smr_data_df, startCol = 1, startRow = 3,
                        headerStyle = openxlsx::createStyle(textDecoration = "bold"), borders = "all")
    openxlsx::setColWidths(wb, sheet = "SMR_Data", cols = 1:ncol(smr_data_df), widths = "auto")
  } else {
    openxlsx::writeData(wb, sheet = "SMR_Data", x = "SMR data is empty or has no columns.", startCol = 1, startRow = 3)
  }

  # Trends Data Sheet
  openxlsx::addWorksheet(wb, "Trends_Data")
  openxlsx::writeData(wb, sheet = "Trends_Data", x = paste("Trends Data for Period:", date_params$publication_reference_period), startCol = 1, startRow = 1)
  if (ncol(trends_data_df) > 0) {
    openxlsx::writeData(wb, sheet = "Trends_Data", x = trends_data_df, startCol = 1, startRow = 3,
                        headerStyle = openxlsx::createStyle(textDecoration = "bold"), borders = "all")
    openxlsx::setColWidths(wb, sheet = "Trends_Data", cols = 1:ncol(trends_data_df), widths = "auto")
  } else {
     openxlsx::writeData(wb, sheet = "Trends_Data", x = "Trends data is empty or has no columns.", startCol = 1, startRow = 3)
  }


  cat("Attempting to save real Excel workbook to:", final_tables_filepath, "
")
  tryCatch({
    openxlsx::saveWorkbook(wb, final_tables_filepath, overwrite = TRUE)
    cat("Real Excel workbook saved successfully to:", final_tables_filepath, "
")
  }, error = function(e) {
    cat("ERROR saving Excel workbook:", e$message, "
")
    stop(paste("Failed to save Excel workbook:", e$message))
  })

  # Calculate and save SHA256 hash of the final output file
  output_hash <- digest::digest(final_tables_filepath, algo = "sha256", file = TRUE)
  output_hash_filepath <- paste0(final_tables_filepath, ".sha256")
  writeLines(output_hash, output_hash_filepath)
  cat("SHA256 hash for final tables output saved to:", output_hash_filepath, "(Hash:", output_hash, ")
")

  cat("
Excel tables generation process completed.
")
}

# Run the main function
tryCatch({
  main()
}, error = function(e) {
  cat("Error in create_excel_tables.R: ", e$message, "
")
  stop(e)
})
