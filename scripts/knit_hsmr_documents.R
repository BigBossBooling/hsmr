# scripts/knit_hsmr_documents.R

# Assume packages are pre-installed in the GHA environment
library(jsonlite)
library(rmarkdown)
library(digest)
library(here)
library(readr)
library(tools)

# --- Configuration ---
config_file <- here::here("hsmr_config.json")

# --- Main Function ---
main <- function() {
  cat("Starting R Markdown document knitting process...
")

  # Load configuration
  if (!file.exists(config_file)) {
    stop(paste("Configuration file not found:", config_file))
  }
  config <- jsonlite::read_json(config_file)
  cat("Configuration loaded successfully for R Markdown knitting.
")

  date_params <- config$date_parameters
  publication_ref_period <- date_params$publication_reference_period
  generation_datetime_str <- format(Sys.time(), "%Y-%m-%d %H:%M:%S %Z")

  rmd_configs <- config$rmd_files_config
  if (is.null(rmd_configs) || length(rmd_configs) == 0) {
    cat("No R Markdown files listed in the configuration. Exiting knitting process.
")
    return()
  }

  publication_output_dir <- here::here(config$output_paths$publication_outputs_dir)
  if (!dir.exists(publication_output_dir)) {
    dir.create(publication_output_dir, recursive = TRUE)
    cat("Created directory:", publication_output_dir, "
")
  }

  processed_data_dir <- here::here(config$output_paths$processed_data_dir)
  smr_output_filename <- paste0("smr_output_", publication_ref_period, ".csv")
  smr_output_filepath <- file.path(processed_data_dir, smr_output_filename)

  trends_output_filename <- paste0("trends_output_", publication_ref_period, ".csv")
  trends_output_filepath <- file.path(processed_data_dir, trends_output_filename)

  render_params <- list(
    publication_period = publication_ref_period,
    generation_date = substr(generation_datetime_str, 1, 10),
    smr_data_file_path = smr_output_filepath,
    trends_data_file_path = trends_output_filepath
  )

  for (rmd_key in names(rmd_configs)) {
    rmd_info <- rmd_configs[[rmd_key]]
    rmd_file_path <- here::here(rmd_info$rmd_path)
    output_formats <- rmd_info$output_formats
    output_filename_base <- paste0(rmd_info$output_filename_base, "_", publication_ref_period)

    cat("
Processing R Markdown file:", rmd_file_path, "
")

    if (!file.exists(rmd_file_path)) {
      warning(paste("R Markdown file not found:", rmd_file_path, ". Skipping."))
      next
    }

    for (fmt in output_formats) {
      output_ext <- switch(fmt,
                           "html_document" = "html",
                           "pdf_document" = "pdf",
                           "word_document" = "docx",
                           "NULL"
                           )
      if (is.null(output_ext) || output_ext == "NULL") {
          output_ext <- tools::file_ext(fmt)
          if (nchar(output_ext) == 0) output_ext <- "html"
          warning(paste("Could not reliably determine extension for format '", fmt, "'. Defaulting to '", output_ext, "'", sep=""))
      }

      if (fmt == "pdf_document" && !rmarkdown::pandoc_available(to = "latex")) {
          cat("WARNING: LaTeX (via pandoc) not available, cannot knit to PDF. Skipping PDF for", rmd_file_path, "
")
          next
      }

      final_output_filename <- paste0(output_filename_base, ".", output_ext)
      final_output_filepath <- file.path(publication_output_dir, final_output_filename)

      cat("Knitting to format:", fmt, "-> Output:", final_output_filepath, "
")

      tryCatch({
        file_content <- paste(
          "--- SIMULATED RENDERED DOCUMENT ---",
          paste("Rmd Source:", rmd_file_path),
          paste("Output Format:", fmt),
          paste("Output File:", final_output_filepath),
          paste("Publication Period Param:", render_params$publication_period),
          paste("Generation Date Param:", render_params$generation_date),
          paste("SMR Data File Param:", render_params$smr_data_file_path),
          paste("Trends Data File Param:", render_params$trends_data_file_path),
          "--- END SIMULATION ---",
          sep = "
"
        )
        writeLines(file_content, final_output_filepath)
        cat("Simulated knitting successful for", final_output_filepath, "
")

        output_doc_hash <- digest::digest(final_output_filepath, algo = "sha256", file = TRUE)
        output_doc_hash_filepath <- paste0(final_output_filepath, ".sha256")
        writeLines(output_doc_hash, output_doc_hash_filepath)
        cat("SHA256 hash for output document saved to:", output_doc_hash_filepath, "(Hash:", output_doc_hash, ")
")

      }, error = function(e) {
        cat("ERROR knitting", rmd_file_path, "to", fmt, ":", e$message, "
")
      })
    }
  }

  cat("

--- Manual Finalization Steps Required ---
")
  cat("The following documents have been generated (simulated) and require manual review and finalization:

")

  for (rmd_key in names(rmd_configs)) {
    rmd_info <- rmd_configs[[rmd_key]]
    output_formats <- rmd_info$output_formats
    output_filename_base <- paste0(rmd_info$output_filename_base, "_", publication_ref_period)

    for (fmt in output_formats) {
      output_ext <- switch(fmt,
                           "html_document" = "html",
                           "pdf_document" = "pdf",
                           "word_document" = "docx",
                           "NULL"
                           )
      if (is.null(output_ext) || output_ext == "NULL") {
          output_ext <- tools::file_ext(fmt)
          if (nchar(output_ext) == 0) output_ext <- "html"
      }
      final_output_filename <- paste0(output_filename_base, ".", output_ext)
      final_output_filepath <- file.path(publication_output_dir, final_output_filename)
      hash_filepath <- paste0(final_output_filepath, ".sha256")

      if (file.exists(final_output_filepath)) {
        cat("Document: ", final_output_filepath, "
")
        if (file.exists(hash_filepath)) {
          doc_hash <- readLines(hash_filepath, n = 1, warn = FALSE)
          cat("  SHA256 Hash: ", doc_hash, "
")
        } else {
          cat("  SHA256 Hash: Not found (should have been generated).
")
        }
      } else {
        cat("Document (expected but not found): ", final_output_filepath, "
")
      }
    }
     cat("
")
  }

  cat("Please perform the following manual checks and finalization steps as per the 'National Statistics Publication Templates repository readme' or internal guidelines:
")
  cat("1.  Review overall document structure, formatting, and clarity.
")
  cat("2.  Add/Verify the official Cover Page.
")
  cat("3.  Verify and finalize the Table of Contents.
")
  cat("4.  Check formatting of all tables and ensure they are publication-ready.
")
  cat("5.  Verify all figures/charts for correctness and clarity.
")
  cat("6.  Perform a final proofread for any typos or grammatical errors.
")
  cat("7.  Ensure all accessibility standards are met (e.g., for PDF outputs).
")
  cat("8.  Confirm all redactions or suppressions have been correctly applied if necessary.
")
  cat("9.  Obtain necessary sign-offs before wider distribution.
")
  cat("--------------------------------------------
")

  cat("
R Markdown document knitting process completed (including manual step reporting).
")
}

tryCatch({
  main()
}, error = function(e) {
  cat("Error in knit_hsmr_documents.R: ", e$message, "
")
  stop(e)
})
