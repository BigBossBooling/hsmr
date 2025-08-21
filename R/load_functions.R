# --- Load and Save Functions ---

# Purpose: This file contains helper functions for loading data from disk/database
# and for saving output files.

library(odbc)
library(readr)
library(here)
library(dplyr)
library(tidylog)
library(janitor)

#' @title Load and Prepare Data
#'
#' @description Connects to the database, loads all necessary lookup files,
#' and extracts the core data tables required for the SMR analysis.
#'
#' @param config A list containing the configuration from config.yml.
#' @param db_user The username for the database connection.
#' @param db_pass The password for the database connection.
#'
#' @return A list containing all the loaded data frames.
load_and_prepare_data <- function(config, db_user, db_pass) {

  # Define the database connection with SMRA
  smra_connect  <- suppressWarnings(dbConnect(odbc(),  dsn="SMRA",
                                              uid=db_user,
                                              pwd=db_pass))

  # --- Read in lookup files ---
  pdiag_grp_data <- read_csv(here("reference_files", "diag_grps_lookup_updated.csv")) %>%
    select(diag1_4, DIAGNOSIS_GROUP) %>%
    clean_names()

  morbs <- read_csv(here("reference_files", "morbs.csv")) %>%
    gather(code, diag, diag_3:diag_4) %>%
    select(-code) %>%
    filter(!is.na(diag))

  specialty_group <- readRDS(here("reference_files", "discovery_spec_grps.rds"))

  # --- Extract data from SMRA databases ---
  # Note: The SQL query functions (e.g., query_gro_smr) are assumed to be
  # available in the hsmr package.

  # Dates are calculated based on the end_date from the config
  end_date <- lubridate::ymd(config$end_date)
  start_date <- end_date - years(3) + days(1)
  start_date_5 <- start_date - years(5)

  deaths  <- as_tibble(dbGetQuery(smra_connect,
                                  query_gro_smr(extract_start = start_date))) %>%
    clean_names()

  smr01 <- as_tibble(dbGetQuery(smra_connect,
                                query_smr01(extract_start = start_date,
                                            extract_end = end_date))) %>%
    clean_names()

  data_pmorbs <- as_tibble(dbGetQuery(smra_connect,
                                      query_smr01_minus5(
                                        extract_start = start_date_5,
                                        extract_end = end_date))) %>%
    clean_names()

  # Disconnect from the database
  dbDisconnect(smra_connect)

  # Return all data objects in a list
  return(
    list(
      smr01 = smr01,
      deaths = deaths,
      data_pmorbs = data_pmorbs,
      pdiag_grp_data = pdiag_grp_data,
      morbs = morbs,
      specialty_group = specialty_group
    )
  )
}


#' @title Save Data to File
#'
#' @description A wrapper function for saving data frames to files,
#' using the convention from the original project.
#'
#' @param data The data frame to save.
#' @param filepath The full path to the output file.
#'
save_data_to_file <- function(data, filepath) {

  # This function is a placeholder for the original hsmr::save_file logic,
  # adapted to take a full path.
  # For now, we will use write_csv as a stand-in.

  # Create directory if it doesn't exist
  dir.create(dirname(filepath), showWarnings = FALSE, recursive = TRUE)

  # Save the file
  readr::write_csv(data, filepath)

  message("Successfully saved data to: ", filepath)
}
