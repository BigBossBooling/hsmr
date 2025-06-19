# R script to setup environment and install required packages

# --- Configuration ---
required_packages <- c(
  "dplyr",      # For data manipulation
  "ggplot2",    # For plotting
  "rmarkdown",  # For report generation
  "knitr",      # For report generation
  "lubridate",  # For date/time manipulation
  "odbc",       # For database connectivity
  "DBI",        # For database connectivity (often a dependency of odbc or used with it)
  "readr",      # For reading csv files (already in setup_environment.R)
  "haven",      # For SPSS files (already in setup_environment.R)
  "janitor",    # For cleaning names (already in setup_environment.R)
  "tidylog",    # For dplyr logs (already in setup_environment.R)
  "tidyr",      # For data manipulation (already in setup_environment.R)
  "stringr",    # For strings (already in setup_environment.R)
  "scales",     # For ggplot2 (already in setup_environment.R)
  "ggrepel",    # For ggplot2 labels (already in setup_environment.R)
  "here",       # For file paths (used in setup_environment.R)
  "openxlsx",   # For Excel files (already in setup_environment.R)
  "devtools",   # For package building (already in setup_environment.R)
  "xfun"        # For number to words (already in setup_environment.R)
  # Add other essential packages for HSMR analysis as they are identified
)

CRAN_MIRROR <- "https://cloud.r-project.org"

# --- User Library Setup ---
local_lib_path <- "/app/r_user_libs" # Fixed path

if (!dir.exists(local_lib_path)) {
  dir.create(local_lib_path, recursive = TRUE, showWarnings = FALSE)
}
.libPaths(c(local_lib_path, .libPaths()))

message(paste("Ensuring R library path:", local_lib_path))
message("Current .libPaths():")
print(.libPaths())

# --- Package Installation Logic ---
message("Starting R environment setup...")

installed_packages_list <- rownames(installed.packages())
packages_to_install <- setdiff(required_packages, installed_packages_list)

if (length(packages_to_install) > 0) {
  message(paste("The following packages will be installed into:", local_lib_path))
  message(paste(packages_to_install, collapse=", "))

  tryCatch({
    install.packages(packages_to_install, lib = local_lib_path, repos = CRAN_MIRROR, Ncpus = 2, ask = FALSE)

    Sys.sleep(1)
    installed_again <- rownames(installed.packages(lib.loc = local_lib_path))
    missing_after_install <- setdiff(packages_to_install, installed_again)

    if(length(missing_after_install) > 0) {
      packages_failed_str <- paste(missing_after_install, collapse=", ")
      warning_message <- paste("Failed to install the following packages into", local_lib_path, ":", packages_failed_str)
      warning(warning_message)
      message("Please check error messages. Common issues: missing system dependencies for the R package (e.g., -dev libraries for XML, curl, openssl), network problems, or CRAN mirror issues.")
      # Optionally, try to install system dependencies if identifiable, or provide specific instructions.
      if(any(c("odbc") %in% missing_after_install)){
        message("ODBC installation often requires system libraries like unixodbc-dev.")
        message("Consider running: sudo apt-get update && sudo apt-get install -y unixodbc-dev")
      }
    } else {
      message(paste("All newly specified packages successfully installed into:", local_lib_path))
    }
  }, error = function(e) {
    warning(paste("An error occurred during package installation:", e$message))
    message("Please check your internet connection, CRAN mirror, or package dependencies (especially system libraries like -dev versions for XML, curl, openssl etc.).")
  })
} else {
  message("All R packages listed in required_packages are already installed in the accessible library paths.")
}

message("R environment setup script finished.")
