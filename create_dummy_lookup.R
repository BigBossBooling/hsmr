# create_dummy_lookup.R
# This script creates a simple dummy lookup file for testing purposes.

# Create a dummy data frame
dummy_specialty_group <- data.frame(
  specialty_code = c("01", "02", "03", "04", "05"),
  specialty_name = c("General Surgery", "Cardiology", "Orthopedics", "Neurology", "Oncology"),
  grouping = c("Surgical", "Medical", "Surgical", "Medical", "Medical")
)

# Define the path using here::here for robustness, assuming 'reference_files' is in the project root
# If 'here' package is not available or setup_environment.R doesn't set up 'here' base,
# a relative path might be needed depending on execution context.
# For this step, we assume 'reference_files' is directly under the current working dir.
lookup_dir <- "reference_files"
if (!dir.exists(lookup_dir)) {
  dir.create(lookup_dir)
}
lookup_path <- file.path(lookup_dir, "discovery_spec_grps.rds")

# Save the dummy data frame as an RDS file
saveRDS(dummy_specialty_group, file = lookup_path)

message(paste("Dummy lookup file 'discovery_spec_grps.rds' created at:", lookup_path))
