# Activate renv by sourcing .Rprofile
if (file.exists("/app/.Rprofile")) {
  source("/app/.Rprofile")
  print("Renv activated via .Rprofile.")
  print(paste("Active .libPaths():", paste(.libPaths(), collapse=", ")))
} else {
  # If .Rprofile doesn't exist, renv needs to be initialized first.
  # This might happen if the workspace was reset or .Rprofile was deleted.
  print("No .Rprofile found. Attempting to initialize renv (bare)...")
  tryCatch({
    # Ensure renv package itself is available in a known user library for init
    r_user_libs_path <- "/app/r_user_libs"
    if (!dir.exists(r_user_libs_path)) dir.create(r_user_libs_path, recursive = TRUE)
    if (!(r_user_libs_path %in% .libPaths())) .libPaths(c(r_user_libs_path, .libPaths()))
    if (!requireNamespace("renv", quietly = TRUE)) install.packages("renv", lib = r_user_libs_path, repos = "https://cloud.r-project.org/")

    renv::init(bare = TRUE, project = "/app")
    source("/app/.Rprofile") # Source the newly created .Rprofile
    print("Renv initialized and activated.")
    print(paste("Updated .libPaths():", paste(.libPaths(), collapse=", ")))
  }, error = function(e_init) {
    stop(paste("Failed to initialize renv:", e_init$message))
  })
}

# Define a small list of packages to test installation
# These are generally simple and quick to install.
# Both are listed in the project's DESCRIPTION file.
packages_to_test <- c("here", "glue")

print(paste("Attempting to install test packages:", paste(packages_to_test, collapse=", ")))

# Install packages one by one
for (pkg in packages_to_test) {
  print(paste("Attempting to install:", pkg))
  tryCatch({
    # renv::install will also update the lockfile if successful
    renv::install(pkg, project = "/app", prompt = FALSE)
    print(paste("Successfully installed and locked:", pkg))
  }, error = function(e) {
    print(paste("ERROR installing package:", pkg))
    print(e$message)
    # Optionally, could try to proceed to the next package
  })
}

print("Test package installation attempt finished.")
print("Running final renv::snapshot() to consolidate lockfile...")
# type = "all" to capture everything currently installed in the project library.
# If the installs above worked, these packages should now be in that library.
renv::snapshot(project = "/app", prompt = FALSE, type = "all")
print("Final renv::snapshot() complete.")

lockfile_path <- "/app/renv.lock"
if (file.exists(lockfile_path)) {
  print("--- renv.lock contents ---")
  cat(readLines(lockfile_path), sep = "\n")
  print("--- end of renv.lock ---")
} else {
  print("renv.lock not found.")
}
