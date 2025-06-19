# scripts/knit_hsmr_documents.R

# Assume packages are pre-installed in the GHA environment
if (!requireNamespace("logger", quietly = TRUE)) { print("Installing logger for knit_hsmr_documents.R"); install.packages("logger", repos = "https://cloud.r-project.org/", quiet=TRUE) }

library(jsonlite)
library(rmarkdown)
library(digest)
library(here)
library(readr)
library(tools)
library(logger)

# --- Configuration ---
config_file <- here::here("hsmr_config.json")

# --- Helper Function for Hash Verification ---
verify_input_data_hash <- function(data_filepath, data_description = "Input data file") {
  log_debug(paste("Verifying hash for", data_description, ":", data_filepath))
  expected_hash_filepath <- paste0(data_filepath, ".sha256")

  if (!file.exists(data_filepath)) {
    err_msg <- paste(data_description, "not found:", data_filepath)
    log_fatal(err_msg)
    stop(err_msg)
  }
  if (!file.exists(expected_hash_filepath)) {
    err_msg <- paste("Expected hash file not found for", data_description, ":", expected_hash_filepath,
               "\nThis indicates an issue with artifact generation from a previous phase.")
    log_fatal(err_msg)
    stop(err_msg)
  }

  expected_hash <- trimws(readLines(expected_hash_filepath, n = 1, warn = FALSE))
  calculated_hash <- digest::digest(data_filepath, algo = "sha256", file = TRUE)

  if (calculated_hash != expected_hash) {
    err_msg <- paste("Hash mismatch for", data_description, ":", data_filepath,
               "\n  Expected:", expected_hash, "\n  Actual  :", calculated_hash,
               "\nData integrity check failed. Ensure the input data is the correct, validated version.")
    log_fatal(err_msg)
    stop(err_msg)
  }
  log_info(paste("Input file hash VERIFIED for", data_description, ":", data_filepath))
  return(TRUE)
}


# --- Main Function ---
main <- function() {
  log_threshold(INFO)
  log_formatter(formatter_glue)

  log_info("Starting R Markdown document knitting process (Production Mode)...")

  if (!file.exists(config_file)) {
    err_msg <- paste("Configuration file not found:", config_file)
    log_fatal(err_msg); stop(err_msg)
  }
  config <- jsonlite::read_json(config_file)
  log_info("Configuration loaded successfully for R Markdown knitting.")

  date_params <- config$date_parameters
  publication_ref_period <- date_params$publication_reference_period
  generation_datetime_str <- format(Sys.time(), "%Y-%m-%d %H:%M:%S %Z")

  rmd_configs <- config$rmd_files_config
  if (is.null(rmd_configs) || length(rmd_configs) == 0) {
    log_info("No R Markdown files listed in the configuration. Exiting knitting process.")
    return()
  }

  publication_output_dir <- here::here(config$output_paths$publication_outputs_dir)
  if (!dir.exists(publication_output_dir)) {
    dir.create(publication_output_dir, recursive = TRUE)
    log_info(paste("Created directory:", publication_output_dir))
  }

  processed_data_dir <- here::here(config$output_paths$processed_data_dir)
  smr_data_input_filename <- paste0("smr_output_", publication_ref_period, ".csv")
  smr_data_input_filepath <- file.path(processed_data_dir, smr_data_input_filename)

  trends_data_input_filename <- paste0("trends_output_", publication_ref_period, ".csv")
  trends_data_input_filepath <- file.path(processed_data_dir, trends_data_input_filename)

  log_info("Verifying input data files for RMarkdown rendering...")
  verify_input_data_hash(smr_data_input_filepath, "SMR Processed Data")
  verify_input_data_hash(trends_data_input_filepath, "Trends Processed Data")
  log_info("All required input data files for RMarkdown rendering have been hash verified.")

  render_params <- list(
    publication_period = publication_ref_period,
    generation_date = substr(generation_datetime_str, 1, 10),
    smr_data_file_path = smr_data_input_filepath,
    trends_data_file_path = trends_data_input_filepath
  )

  any_knit_errors <- FALSE

  for (rmd_key in names(rmd_configs)) {
    rmd_info <- rmd_configs[[rmd_key]]
    rmd_file_path <- here::here(rmd_info$rmd_path)
    output_formats <- rmd_info$output_formats
    output_filename_base <- paste0(rmd_info$output_filename_base, "_", publication_ref_period)

    log_info(paste("Processing R Markdown file:", rmd_file_path))

    if (!file.exists(rmd_file_path)) {
      log_warn(paste("R Markdown file not found:", rmd_file_path, ". Skipping."))
      any_knit_errors <- TRUE
      next
    }

    for (fmt in output_formats) {
      output_ext <- switch(fmt,
                           "html_document" = "html", "pdf_document" = "pdf",
                           "word_document" = "docx", "NULL")
      if (is.null(output_ext) || output_ext == "NULL") {
          output_ext_temp <- tools::file_ext(fmt);
          if (nchar(output_ext_temp) == 0) output_ext_temp <- "html"
          output_ext <- output_ext_temp
          log_warn(paste0("Could not reliably determine extension for format '", fmt, "'. Defaulting to '", output_ext, "'"))
      }

      final_output_filename <- paste0(output_filename_base, ".", output_ext)
      final_output_filepath <- file.path(publication_output_dir, final_output_filename)

      log_info(paste("Attempting to knit to format:", fmt, "-> Output:", final_output_filepath))

      SIMULATE_KNITTING <- toupper(Sys.getenv("SIMULATE_KNITTING", unset = "FALSE")) == "TRUE"

      if (SIMULATE_KNITTING) {
        log_info("SIMULATE_KNITTING is TRUE. Creating dummy output file.")
        file_content <- paste(
          "--- SIMULATED RENDERED DOCUMENT ---",
          paste("Rmd Source:", rmd_file_path), paste("Output Format:", fmt),
          paste("Output File:", final_output_filepath),
          paste("Publication Period Param:", render_params$publication_period),
          paste("Generation Date Param:", render_params$generation_date),
          paste("SMR Data File Param:", render_params$smr_data_file_path),
          paste("Trends Data File Param:", render_params$trends_data_file_path),
          "--- END SIMULATION ---", sep = "
"
        )
        writeLines(file_content, final_output_filepath)
        log_info(paste("Simulated knitting successful for", final_output_filepath))
      } else {
        pandoc_dir_found <- tryCatch(rmarkdown::find_pandoc()$dir, error = function(e) NULL)
        if (fmt == "pdf_document" && (is.null(pandoc_dir_found) || !rmarkdown::pandoc_available(to = "latex"))) {
            log_warn(paste("LaTeX (via pandoc) not available or pandoc not found. Skipping PDF for", rmd_file_path))
            any_knit_errors <- TRUE
            next
        }
        tryCatch({
          rmarkdown::render(
            input = rmd_file_path,
            output_format = fmt,
            output_file = final_output_filename,
            output_dir = publication_output_dir,
            params = render_params,
            quiet = FALSE
          )
          log_info(paste("Successfully knitted", rmd_file_path, "to", final_output_filepath))
        }, error = function(e) {
          log_error(paste("ERROR knitting", rmd_file_path, "to", fmt, ":", conditionMessage(e)))
          any_knit_errors <<- TRUE
        })
      }

      if (file.exists(final_output_filepath)) {
        output_doc_hash <- digest::digest(final_output_filepath, algo = "sha256", file = TRUE)
        output_doc_hash_filepath <- paste0(final_output_filepath, ".sha256")
        writeLines(output_doc_hash, output_doc_hash_filepath)
        log_info(paste("SHA256 hash for output document saved to:", output_doc_hash_filepath))
      } else if (!SIMULATE_KNITTING && !(fmt == "pdf_document" && (is.null(pandoc_dir_found) || !rmarkdown::pandoc_available(to = "latex")))) {
        log_warn(paste("Output file not found after attempted render (and not a skipped PDF):", final_output_filepath))
      }
    }
  }

  # Manual Finalization Reporting
  log_info("
--- Manual Finalization Steps Required ---")
  log_info("The following documents have been generated and require manual review and finalization:")

  report_lines <- c(
    "--- Manual Finalization Steps Required ---",
    "The following documents have been generated and require manual review and finalization:",
    ""
  )

  for (rmd_key_report in names(rmd_configs)) {
    rmd_info_report <- rmd_configs[[rmd_key_report]]
    output_formats_report <- rmd_info_report$output_formats
    output_filename_base_report <- paste0(rmd_info_report$output_filename_base, "_", publication_ref_period)

    for (fmt_report in output_formats_report) {
      output_ext_report <- switch(fmt_report,
                           "html_document" = "html", "pdf_document" = "pdf",
                           "word_document" = "docx", "NULL")
      if (is.null(output_ext_report) || output_ext_report == "NULL") {
          output_ext_temp_report <- tools::file_ext(fmt_report);
          if (nchar(output_ext_temp_report) == 0) output_ext_temp_report <- "html"
          output_ext_report <- output_ext_temp_report
      }
      final_output_filename_report <- paste0(output_filename_base_report, ".", output_ext_report)
      final_output_filepath_report <- file.path(publication_output_dir, final_output_filename_report)
      hash_filepath_report <- paste0(final_output_filepath_report, ".sha256")

      doc_info_line <- ""
      if (file.exists(final_output_filepath_report)) {
        doc_info_line <- paste("Document: ", final_output_filepath_report)
        log_info(doc_info_line)
        report_lines <- c(report_lines, doc_info_line)

        if (file.exists(hash_filepath_report)) {
          doc_hash_report <- trimws(readLines(hash_filepath_report, n = 1, warn = FALSE))
          hash_info_line <- paste("  SHA256 Hash: ", doc_hash_report)
          log_info(hash_info_line)
          report_lines <- c(report_lines, hash_info_line)
        } else {
          no_hash_line <- "  SHA256 Hash: Not found (should have been generated)."
          log_warn(no_hash_line)
          report_lines <- c(report_lines, no_hash_line)
        }
      } else {
        SIMULATE_KNITTING_check <- toupper(Sys.getenv("SIMULATE_KNITTING", unset = "FALSE")) == "TRUE"
        is_pdf_no_latex_check <- (fmt_report == "pdf_document" && (is.null(tryCatch(rmarkdown::find_pandoc()$dir, error = function(e) NULL)) || !rmarkdown::pandoc_available(to = "latex")))

        if(!(is_pdf_no_latex_check && !SIMULATE_KNITTING_check)) {
            doc_not_found_line <- paste("Document (expected but not found/not generated): ", final_output_filepath_report)
            log_warn(doc_not_found_line)
            report_lines <- c(report_lines, doc_not_found_line)
        }
      }
    }
    log_info("")
    report_lines <- c(report_lines, "")
  }

  checklist_header <- "Please perform the following manual checks and finalization steps as per the 'National Statistics Publication Templates repository readme' or internal guidelines:"
  log_info(checklist_header)
  report_lines <- c(report_lines, checklist_header)

  manual_tasks <- c(
    "1.  Review overall document structure, formatting, and clarity.",
    "2.  Add/Verify the official Cover Page.",
    "3.  Verify and finalize the Table of Contents.",
    "4.  Check formatting of all tables and ensure they are publication-ready.",
    "5.  Verify all figures/charts for correctness and clarity.",
    "6.  Perform a final proofread for any typos or grammatical errors.",
    "7.  Ensure all accessibility standards are met (e.g., for PDF outputs).",
    "8.  Confirm all redactions or suppressions have been correctly applied if necessary.",
    "9.  Obtain necessary sign-offs before wider distribution."
  )
  for(task in manual_tasks){
      log_info(task)
      report_lines <- c(report_lines, task)
  }

  separator_line <- "--------------------------------------------"
  log_info(separator_line)
  report_lines <- c(report_lines, separator_line)

  checklist_filename <- paste0("MANUAL_FINALIZATION_CHECKLIST_", publication_ref_period, ".txt")
  checklist_filepath <- file.path(publication_output_dir, checklist_filename)

  tryCatch({
    writeLines(report_lines, checklist_filepath)
    log_info(paste("Manual finalization checklist saved to:", checklist_filepath))
  }, error = function(e){
    log_warn(paste("Failed to write manual finalization checklist to file:", checklist_filepath, "Error:", conditionMessage(e)))
  })

  if (any_knit_errors) {
    err_msg <- "One or more R Markdown documents failed to knit or were skipped due to missing dependencies (e.g. LaTeX for PDF). Check logs for details."
    log_fatal(err_msg)
    stop(err_msg)
  } else {
    log_info("R Markdown document knitting process completed successfully (or simulated successfully).")
  }
}

tryCatch({
  main()
}, error = function(e) {
  final_error_message <- paste("CRITICAL ERROR in knit_hsmr_documents.R:", conditionMessage(e))
  if (requireNamespace("logger", quietly = TRUE) && exists("log_fatal") && is.function(log_fatal)) {
    log_fatal(final_error_message)
  } else {
    cat(final_error_message, "
")
  }
  quit(status = 1, save = "no")
})
