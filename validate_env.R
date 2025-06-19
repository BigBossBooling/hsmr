# validate_env.R

# Define required packages and their minimum versions (optional)
# For now, we'll just check for presence.
required_packages <- c(
  "dplyr",
  "ggplot2",
  "rmarkdown",
  "knitr",
  "lubridate",
  "odbc",
  "DBI",
  "jsonlite",
  "readr",
  "here"
  # Add any other packages that will be critical for the pipeline
)

# Check R Version (Example: check for at least R 4.0.0)
r_version_major <- as.numeric(R.version$major)
r_version_minor <- as.numeric(R.version$minor)

min_r_major <- 4
min_r_minor <- 0

cat("Checking R version...
")
if (r_version_major < min_r_major || (r_version_major == min_r_major && r_version_minor < min_r_minor)) {
  stop(paste0("R version ", min_r_major, ".", min_r_minor, " or higher is required. Found: ", R.version$string))
} else {
  cat("R version check passed: ", R.version$string, "
")
}

cat("
Checking R packages...
")
all_packages_found <- TRUE
missing_packages <- c()

for (pkg in required_packages) {
  if (!requireNamespace(pkg, quietly = TRUE)) {
    cat("ERROR: Required package '", pkg, "' is not installed.
", sep = "")
    all_packages_found <- FALSE
    missing_packages <- c(missing_packages, pkg)
  } else {
    cat("Found package: '", pkg, "'
", sep = "")
  }
}

if (!all_packages_found) {
  stop("Missing required R packages: ", paste(missing_packages, collapse = ", "), "
Please check environment setup.")
} else {
  cat("
All required R packages found.
")
  cat("Environment validation successful!
")
}
