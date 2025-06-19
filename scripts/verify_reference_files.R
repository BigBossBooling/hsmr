# scripts/verify_reference_files.R

# Load necessary libraries
if (!requireNamespace("jsonlite", quietly = TRUE)) install.packages("jsonlite", repos = "https://cloud.r-project.org/")
if (!requireNamespace("digest", quietly = TRUE)) install.packages("digest", repos = "https://cloud.r-project.org/")
if (!requireNamespace("here", quietly = TRUE)) install.packages("here", repos = "https://cloud.r-project.org/")

library(jsonlite)
library(digest)
library(here)

# --- Configuration ---
config_file <- here::here("hsmr_config.json") # Assumes config is in root, downloaded by GHA

# --- Main Function ---
main <- function() {
  cat("Starting reference file verification process...
")

  # Load configuration
  if (!file.exists(config_file)) {
    stop(paste("Configuration file not found:", config_file,
               "It should be available from previous GHA steps."))
  }
  config <- jsonlite::read_json(config_file)
  cat("Configuration loaded successfully.
")

  if (is.null(config$reference_file_manifest) || length(config$reference_file_manifest) == 0) {
    cat("No reference files listed in the manifest. Skipping verification.
")
    return()
  }

  all_files_verified <- TRUE
  error_messages <- c()

  for (file_info in config$reference_file_manifest) {
    file_name <- file_info$name
    file_path_from_config <- file_info$path
    # Use here::here to ensure path is relative to project root, regardless of script location
    actual_file_path <- here::here(file_path_from_config)
    expected_hash <- file_info$expected_hash

    cat("
Verifying file:", file_name, "(Path:", actual_file_path, ")
")

    # Check 1: File Existence
    if (!file.exists(actual_file_path)) {
      msg <- paste("ERROR: File not found:", actual_file_path)
      cat(msg, "
")
      error_messages <- c(error_messages, msg)
      all_files_verified <- FALSE
      next # Skip further checks for this file
    }
    cat("File exists.
")

    # Check 2: File Readability (implied by file.exists, but good to be aware)
    # Actual read attempt is not done here, but by digest()

    # Check 3: Hash Comparison
    if (!is.null(expected_hash) && nzchar(expected_hash)) {
      calculated_hash <- digest::digest(actual_file_path, algo = "sha256", file = TRUE)
      if (calculated_hash == expected_hash) {
        cat("SHA256 Hash verification PASSED. (Expected/Actual:", expected_hash, ")
")
      } else {
        msg <- paste("ERROR: SHA256 Hash verification FAILED for", actual_file_path,
                     "
  Expected:", expected_hash,
                     "
  Actual  :", calculated_hash)
        cat(msg, "
")
        error_messages <- c(error_messages, msg)
        all_files_verified <- FALSE
      }
    } else {
      cat("WARNING: No expected hash provided for", file_name, ". Skipping hash check.
")
    }
  }

  if (!all_files_verified) {
    full_error_message <- paste("Reference file verification failed. Issues found:
",
                                paste(error_messages, collapse = "
"))
    stop(full_error_message)
  } else {
    cat("
All reference files verified successfully!
")
  }
}

# Run the main function
tryCatch({
  main()
}, error = function(e) {
  cat("Error in verify_reference_files.R: ", e$message, "
")
  stop(e) # Re-throw error to fail GHA step
})
