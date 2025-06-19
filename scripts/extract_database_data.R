# scripts/extract_database_data.R

# Load necessary libraries
if (!requireNamespace("DBI", quietly = TRUE)) install.packages("DBI", repos = "https://cloud.r-project.org/")
if (!requireNamespace("odbc", quietly = TRUE)) install.packages("odbc", repos = "https://cloud.r-project.org/") # Or RPostgres, RSQLite, etc.
if (!requireNamespace("jsonlite", quietly = TRUE)) install.packages("jsonlite", repos = "https://cloud.r-project.org/")
if (!requireNamespace("readr", quietly = TRUE)) install.packages("readr", repos = "https://cloud.r-project.org/")
if (!requireNamespace("digest", quietly = TRUE)) install.packages("digest", repos = "https://cloud.r-project.org/")
if (!requireNamespace("here", quietly = TRUE)) install.packages("here", repos = "https://cloud.r-project.org/")

library(DBI)
library(odbc) # Placeholder, replace with actual DB driver package if different
library(jsonlite)
library(readr)
library(digest)
library(here)

# --- Configuration ---
config_file <- here::here("hsmr_config.json") # Assumes config is in root, downloaded by GHA

# --- Main Function ---
main <- function() {
  cat("Starting database extraction process...
")

  # Load configuration
  if (!file.exists(config_file)) {
    stop("hsmr_config.json not found! It should be downloaded as an artifact.")
  }
  config <- jsonlite::read_json(config_file)
  cat("Configuration loaded successfully.
")

  date_params <- config$date_parameters
  db_config_placeholder <- config$database_config # Placeholder
  raw_data_dir <- here::here(config$output_paths$raw_data_dir)

  # Create raw data directory if it doesn't exist
  if (!dir.exists(raw_data_dir)) {
    dir.create(raw_data_dir, recursive = TRUE)
    cat("Created directory:", raw_data_dir, "
")
  }

  # --- Database Connection (Simulated) ---
  # In a real scenario, get credentials from environment variables (GitHub Secrets)
  # db_user <- Sys.getenv("DB_USER")
  # db_password <- Sys.getenv("DB_PASSWORD")
  # db_server <- Sys.getenv("DB_SERVER_OR_DSN") # Or from config if not sensitive
  # db_database_name <- Sys.getenv("DB_NAME")   # Or from config

  # Example DSN connection (replace with your actual connection details)
  # con_string <- paste0("Driver={ODBC Driver 17 for SQL Server};",
  #                      "Server=", db_server, ";",
  #                      "Database=", db_database_name, ";",
  #                      "Uid=", db_user, ";",
  #                      "Pwd=", db_password)
  # tryCatch({
  #   con <- dbConnect(odbc::odbc(), .connection_string = con_string, timeout = 10)
  #   cat("Successfully connected to the database (simulated).
")
  # }, error = function(e) {
  #   stop("Database connection failed (simulated): ", e$message)
  # })

  cat("SIMULATING database connection. No actual DB calls will be made in this script version.
")
  # To simulate, we'll just create dummy data frames later.

  # --- SQL Queries to Execute ---
  # Assumes SQL files are in a 'sql_queries' directory relative to project root
  sql_files_to_process <- list(
    smr = list(file = here::here("sql_queries", "get_smr_extract.sql"),
               output_csv = paste0("smr_extract_", date_params$publication_reference_period, ".csv")),
    ltt = list(file = here::here("sql_queries", "get_ltt_extract.sql"),
               output_csv = paste0("ltt_extract_", date_params$publication_reference_period, ".csv"))
  )

  for (query_name in names(sql_files_to_process)) {
    sql_info <- sql_files_to_process[[query_name]]
    sql_file_path <- sql_info$file
    output_filename <- sql_info$output_csv
    output_filepath <- file.path(raw_data_dir, output_filename)

    cat("
Processing SQL file:", sql_file_path, "
")

    if (!file.exists(sql_file_path)) {
      warning("SQL file not found:", sql_file_path, ". Skipping.")
      next
    }
    query_template <- readr::read_file(sql_file_path)

    # Parameterize query (simple substitution, more robust methods exist e.g., glue, sqlInterpolate)
    # For LTT, you might need different date parameters from config if they exist
    query_parametrized <- gsub("\\{start_date_iso\\}", date_params$start_date_iso, query_template)
    query_parametrized <- gsub("\\{end_date_iso\\}", date_params$end_date_iso, query_parametrized)
    query_parametrized <- gsub("\\{ltt_start_date_iso\\}",
                               ifelse(!is.null(date_params$ltt_start_date_iso), date_params$ltt_start_date_iso, "1900-01-01"), # Default LTT start
                               query_parametrized)


    cat("Executing query (simulated):
", substr(query_parametrized, 1, 200), "...
")

    # --- Simulate Data Fetching ---
    # In a real scenario: result_df <- dbGetQuery(con, query_parametrized)
    if (query_name == "smr") {
      result_df <- data.frame(
        patient_id = 1:5,
        admission_date = rep(as.Date(date_params$start_date_iso), 5) + 0:4,
        discharge_date = rep(as.Date(date_params$end_date_iso), 5) - 4:0,
        diagnosis_code_1 = paste0("A0", 1:5),
        discharged_alive_status = c(1,1,0,1,1)
      )
    } else if (query_name == "ltt") {
      result_df <- data.frame(
        admission_year_month = c(paste0(date_params$year,"-01"), paste0(date_params$year,"-02")),
        diagnosis_group = c("Group A", "Group B"),
        number_of_admissions = c(10,15),
        number_of_deaths = c(1,2)
      )
    } else {
      result_df <- data.frame(id = integer(), value = character()) # Empty dataframe
    }
    cat("Simulated data fetched. Rows:", nrow(result_df), "
")

    # Save to CSV
    readr::write_csv(result_df, output_filepath)
    cat("Data saved to:", output_filepath, "
")

    # Calculate and save SHA256 hash of the CSV
    file_hash <- digest::digest(output_filepath, algo = "sha256", file = TRUE)
    hash_filepath <- paste0(output_filepath, ".sha256")
    writeLines(file_hash, hash_filepath)
    cat("SHA256 hash saved to:", hash_filepath, "(Hash:", file_hash, ")
")
  }

  # --- Close Database Connection (Simulated) ---
  # if (exists("con") && !is.null(con)) {
  #   dbDisconnect(con)
  #   cat("
Database connection closed (simulated).
")
  # }

  cat("
Database extraction process completed (simulated).
")
}

# Run the main function
tryCatch({
  main()
}, error = function(e) {
  cat("Error in extract_database_data.R: ", e$message, "
")
  stop(e) # Re-throw error to fail GHA step
})
