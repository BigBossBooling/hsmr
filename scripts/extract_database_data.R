# scripts/extract_database_data.R

# Load necessary libraries
# (Ensure DBI, odbc or other specific DB driver like RPostgres, jsonlite, readr, digest, here are listed in GHA R package installation)
library(DBI)
library(odbc) # Using odbc as a common example; replace if another driver (e.g., RPostgres, RMySQL) is used
library(jsonlite)
library(readr)
library(digest)
library(here)

# --- Configuration ---
config_file <- here::here("hsmr_config.json")

# Custom infix operator for "null coalescing" like ??
`%||%` <- function(a, b) if (!is.null(a) && !is.na(a) && nzchar(a)) a else b


# --- Main Function ---
main <- function() {
  cat("Starting database extraction process (REAL DATA MODE STRUCTURED)...
")

  # Load configuration
  if (!file.exists(config_file)) {
    stop("hsmr_config.json not found! It should be available from previous GHA steps.")
  }
  config <- jsonlite::read_json(config_file)
  cat("Configuration loaded successfully.
")

  date_params <- config$date_parameters
  db_config_placeholders <- config$database_config # Contains placeholders for server/db name env vars
  raw_data_dir <- here::here(config$output_paths$raw_data_dir)

  if (!dir.exists(raw_data_dir)) {
    dir.create(raw_data_dir, recursive = TRUE)
    cat("Created directory:", raw_data_dir, "
")
  }

  # --- Database Connection ---
  cat("Attempting to establish database connection...
")

  # Retrieve credentials securely from environment variables (populated by GitHub Actions Secrets)
  db_user <- Sys.getenv("HSMR_DB_USER")
  db_password <- Sys.getenv("HSMR_DB_PASSWORD")
  db_server_or_dsn <- Sys.getenv("HSMR_DB_SERVER_OR_DSN", unset = db_config_placeholders$db_server_placeholder %||% "")
  db_database_name <- Sys.getenv("HSMR_DB_DATABASE_NAME", unset = db_config_placeholders$db_name_placeholder %||% "")
  db_driver <- Sys.getenv("HSMR_DB_DRIVER", unset = "{ODBC Driver 17 for SQL Server}")
  db_port_str <- Sys.getenv("HSMR_DB_PORT", unset = "1433")

  if (db_user == "" || db_password == "" || db_server_or_dsn == "" || db_database_name == "") {
    stop("CRITICAL: Database credentials or connection parameters (HSMR_DB_USER, HSMR_DB_PASSWORD, HSMR_DB_SERVER_OR_DSN, HSMR_DB_DATABASE_NAME) are missing or empty. Ensure GitHub Actions secrets are set.")
  }

  # Attempt to convert port to integer, handle potential NA from empty string or non-numeric
  db_port <- tryCatch({
      as.integer(db_port_str)
  }, warning = function(w) {
      NA_integer_ # Return NA on warning (e.g. NAs introduced by coercion)
  })
  if(is.na(db_port)) {
      stop(paste0("CRITICAL: HSMR_DB_PORT ('", db_port_str, "') is not a valid integer port number."))
  }


  con <- NULL # Initialize connection object
  tryCatch({
    # For odbc, DSNs are often preferred as they can encapsulate driver and server details, including encryption.
    # If not using a DSN, then Driver, Server, Database, UID, PWD, Port are common.
    # Encryption parameters (Encrypt=yes, TrustServerCertificate=no/yes, sslmode=require) are highly
    # driver and database specific. These should be part of the DSN configuration or connection string.
    # The example below is generic for odbc::odbc(); actual parameters might vary.

    cat(paste0("Connecting with: Driver='", db_driver, "', Server='", db_server_or_dsn, "', DB='", db_database_name, "', Port='", db_port, "', User='", db_user, "'
"))

    con <- dbConnect(odbc::odbc(),
                     Driver = db_driver,
                     Server = db_server_or_dsn,
                     Database = db_database_name,
                     UID = db_user,
                     PWD = db_password,
                     Port = db_port,
                     timeout = 20
                     # IMPORTANT: Add specific encryption parameters here or ensure DSN handles them.
                     # e.g., for SQL Server: ...; Encrypt=yes; TrustServerCertificate=no;
                     # e.g., for PostgreSQL (using RPostgres driver): sslmode = "require"
                    )
    cat("Successfully connected to the database.
")
  }, error = function(e) {
    stop(paste("Database connection failed. Error:", e$message,
               "
Check DB server details (HSMR_DB_SERVER_OR_DSN), credentials (HSMR_DB_USER/PASSWORD), database name (HSMR_DB_DATABASE_NAME), driver (HSMR_DB_DRIVER), port (HSMR_DB_PORT), network access, firewall rules, and required TLS/SSL configurations for the connection."))
  })

  # --- SQL Queries to Execute ---
  sql_files_to_process <- list(
    smr = list(file = here::here("sql_queries", "get_smr_extract.sql"),
               output_csv = paste0("smr_extract_", date_params$publication_reference_period, ".csv")),
    ltt = list(file = here::here("sql_queries", "get_ltt_extract.sql"),
               output_csv = paste0("ltt_extract_", date_params$publication_reference_period, ".csv"))
  )

  on.exit({
    if (!is.null(con) && DBI::dbIsValid(con)) {
      dbDisconnect(con)
      cat("
Database connection closed.
")
    }
  })

  for (query_name in names(sql_files_to_process)) {
    sql_info <- sql_files_to_process[[query_name]]
    sql_file_path <- sql_info$file
    output_filename <- sql_info$output_csv
    output_filepath <- file.path(raw_data_dir, output_filename)

    cat("
Processing SQL file:", sql_file_path, "
")

    if (!file.exists(sql_file_path)) {
      warning(paste("SQL file not found:", sql_file_path, ". Skipping."))
      next
    }
    query_template <- readr::read_file(sql_file_path)

    query_parametrized <- query_template
    query_parametrized <- gsub("\\{start_date_iso\\}", date_params$start_date_iso, query_parametrized, fixed = TRUE)
    query_parametrized <- gsub("\\{end_date_iso\\}", date_params$end_date_iso, query_parametrized, fixed = TRUE)

    ltt_start_date_val <- date_params$ltt_start_date_iso %||% "1900-01-01" # Use default if not in config
    query_parametrized <- gsub("\\{ltt_start_date_iso\\}", ltt_start_date_val, query_parametrized, fixed = TRUE)

    cat("Executing query (first 200 chars): ", substr(query_parametrized, 1, 200), "...
")

    result_df <- NULL
    tryCatch({
      result_df <- dbGetQuery(con, query_parametrized)
      cat("Query executed successfully. Rows fetched:", nrow(result_df), "
")
    }, error = function(e) {
      detailed_error_msg <- paste("Failed to execute query from", sql_file_path, ". Error:", e$message)
      cat("ERROR:", detailed_error_msg, "
SQL attempted (first 500 chars):
", substr(query_parametrized, 1, 500), "
")
      stop(detailed_error_msg)
    })

    if (!is.null(result_df) && nrow(result_df) > 0) {
      # --- CONCEPTUAL PSEUDONYMIZATION PLACEHOLDER ---
      # WARNING: The following is a conceptual placeholder for pseudonymization.
      # For REAL production data containing PII, a robust, secure, and potentially
      # externally audited pseudonymization service or at-source pseudonymization MUST be used.
      # Simple hashing as shown below is NOT cryptographically secure for PII protection
      # in a production environment (e.g., vulnerable to rainbow tables if unsalted).

      pii_column_to_pseudonymize <- "patient_id" # Example PII column

      if (pii_column_to_pseudonymize %in% names(result_df)) {
        cat(paste0("INFO: Applying conceptual pseudonymization to column: '", pii_column_to_pseudonymize, "'
"))
        cat("WARNING: This is a SIMULATION of pseudonymization using unsalted SHA256. NOT FOR PRODUCTION PII.
")

        # Ensure the column is character for consistent hashing
        result_df[[pii_column_to_pseudonymize]] <- as.character(result_df[[pii_column_to_pseudonymize]])

        # Apply SHA256 hashing (example - unsalted, for simulation only)
        # For actual pseudonymization, a keyed hash (HMAC) or a dedicated service is necessary.
        result_df[[paste0("pseudo_", pii_column_to_pseudonymize)]] <- sapply(
          result_df[[pii_column_to_pseudonymize]],
          function(x) {
            if (is.na(x)) NA_character_ else digest::digest(x, algo = "sha256", serialize = FALSE)
          }
        )

        # Optionally, remove the original PII column if it's not needed downstream
        # For this simulation, we might keep it for comparison or remove it.
        # Let's assume for now we create a new pseudo column and might keep the original for a bit.
        # In a real scenario, the original PII might be dropped here if the pseudo ID is sufficient.
        # result_df[[pii_column_to_pseudonymize]] <- NULL
        cat(paste0("Conceptual 'pseudo_", pii_column_to_pseudonymize, "' column added.
"))
      } else {
        cat(paste0("INFO: PII column '", pii_column_to_pseudonymize, "' not found in '", query_name, "' result. Skipping conceptual pseudonymization for this column.
"))
      }
      # --- END CONCEPTUAL PSEUDONYMIZATION PLACEHOLDER ---
    }

    # Save to CSV
    readr::write_csv(result_df, output_filepath)
    cat("Data saved to:", output_filepath, "
")

    file_hash <- digest::digest(output_filepath, algo = "sha256", file = TRUE)
    hash_filepath <- paste0(output_filepath, ".sha256")
    writeLines(file_hash, hash_filepath)
    cat("SHA256 hash saved to:", hash_filepath, "(Hash:", file_hash, ")
")
  }

  cat("
Database extraction process completed.
")
}

# Run the main function
tryCatch({
  main()
}, error = function(e) {
  cat("
--- CRITICAL ERROR IN SCRIPT ---
Error in extract_database_data.R: ", conditionMessage(e), "
")
  # Stop with the original error message to ensure it's the primary failure reason seen in GHA
  stop(conditionMessage(e))
})
