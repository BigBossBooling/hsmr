# install_minimal_packages.R
# Install only readr and here for focused testing.

local_lib_path <- "/app/r_user_libs"

if (!dir.exists(local_lib_path)) {
  dir.create(local_lib_path, recursive = TRUE, showWarnings = FALSE)
}
.libPaths(c(local_lib_path, .libPaths()))

packages_to_install <- c("readr", "here")
installed_packages_list <- rownames(installed.packages())
packages_needing_install <- setdiff(packages_to_install, installed_packages_list)

if (length(packages_needing_install) > 0) {
  message(paste("Installing:", paste(packages_needing_install, collapse=", ")))
  install.packages(packages_needing_install, lib = local_lib_path, repos = "https://cloud.r-project.org", Ncpus = 2, ask = FALSE)
} else {
  message("readr and here are already installed.")
}

# Verify
message("Checking for readr:")
print(find.package("readr", lib.loc = .libPaths(), quiet = FALSE))
message("Checking for here:")
print(find.package("here", lib.loc = .libPaths(), quiet = FALSE))
