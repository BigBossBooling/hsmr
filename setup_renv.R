# Ensure r_user_libs exists for installing renv package itself
r_user_libs_path <- "/app/r_user_libs"
if (!dir.exists(r_user_libs_path)) {
  dir.create(r_user_libs_path, recursive = TRUE)
  print(paste("Created directory:", r_user_libs_path))
}

# Add r_user_libs_path to .libPaths if not already present
if (!(r_user_libs_path %in% .libPaths())) {
  .libPaths(c(r_user_libs_path, .libPaths()))
}
print(paste("Initial .libPaths():", paste(.libPaths(), collapse=", ")))

# Install renv if not already available in the user library
if (!requireNamespace("renv", quietly = TRUE)) {
  print(paste("Installing renv into:", r_user_libs_path))
  install.packages("renv", lib = r_user_libs_path, repos = "https://cloud.r-project.org/")
} else {
  print("renv package is already available.")
}

# Initialize renv for the project (bare mode).
# This creates .Rprofile, renv/activate.R etc. if not present.
print("Initializing renv for the project (bare mode if not already initialized)...")
renv::init(bare = TRUE, project = "/app", restart = FALSE) # restart=FALSE if session already running
print("Renv initialized.")

# Activate renv for this session by sourcing the .Rprofile.
# This sets up the project-specific library paths.
print("Sourcing .Rprofile to activate renv for the current session...")
source("/app/.Rprofile") # This should point .libPaths() to the renv project library
print(paste("Active .libPaths() after renv activation:", paste(.libPaths(), collapse=", ")))

# --- Step 1: Identify dependencies from DESCRIPTION and install them ---
print("Attempting to install packages listed in DESCRIPTION file using renv::hydrate()...")
# hydrate will look at DESCRIPTION and try to install those packages into the renv library.
# It might also try to update other packages if the lockfile suggests it.
# We want it to primarily focus on getting packages from DESCRIPTION installed.
renv::hydrate(project = "/app", update = "none") # update="none" to avoid unwanted updates now
print("renv::hydrate() complete. Packages from DESCRIPTION should now be in the project library.")

# --- Step 2: Snapshot installed packages into renv.lock ---
print("Setting snapshot type to 'explicit' to focus on DESCRIPTION file dependencies for locking.")
renv::settings$snapshot.type("explicit")

print("Now attempting to snapshot all installed packages (including those from DESCRIPTION) into renv.lock...")
# This snapshot should now find the packages installed by hydrate() and record their versions.
renv::snapshot(project = "/app", prompt = FALSE)
print("renv::snapshot() complete. renv.lock should be updated with installed package versions.")

# --- Final check ---
print("To fully restore/rebuild, run 'renv::restore()' in a clean session after this setup.")
print("Contents of the updated renv.lock will be displayed next.")

lockfile_path <- "/app/renv.lock"
if (file.exists(lockfile_path)) {
  print("--- renv.lock contents ---")
  cat(readLines(lockfile_path), sep = "\n")
  print("--- end of renv.lock ---")
} else {
  print("renv.lock not found or not updated as expected.")
}
