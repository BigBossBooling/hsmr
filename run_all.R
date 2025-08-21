# --- Master Orchestration Script: run_all.R ---

# Purpose: This script is the single entry point for the entire pipeline.
# It sources all necessary scripts in the correct order to ensure
# a complete, end-to-end run of the analysis.

# This script can be run directly from the command line,
# making it suitable for CI/CD automation.

# Run the SMR data creation pipeline
message("--- Starting HSMR Pipeline: SMR Data Creation ---")
source("create_smr_data.R")

# Run the trends data creation pipeline
message("\n--- Starting HSMR Pipeline: Trends Data Creation ---")
source("create_trends_data.R")

# Render the final reports
message("\n--- Starting HSMR Pipeline: Report Generation ---")
rmarkdown::render("markdown/hsmr_quarterly_report.Rmd")

message("\n--- HSMR Pipeline Complete! ---")
