# Ensure r_user_libs exists and is in .libPaths()
r_user_libs_path <- "/app/r_user_libs"
if (!dir.exists(r_user_libs_path)) {
  dir.create(r_user_libs_path, recursive = TRUE)
  print(paste("Created directory:", r_user_libs_path))
}
if (!(r_user_libs_path %in% .libPaths())) {
  .libPaths(c(r_user_libs_path, .libPaths()))
}
print(paste("Using .libPaths():", paste(.libPaths(), collapse=", ")))

# Function to parse DESCRIPTION file and get Imports/Depends
get_desc_dependencies <- function(desc_file = "/app/DESCRIPTION") {
  if (!file.exists(desc_file)) {
    stop("DESCRIPTION file not found at ", desc_file)
  }
  con <- file(desc_file, open = "r")
  lines <- readLines(con)
  close(con)

  dependencies <- c()
  in_imports <- FALSE
  in_depends <- FALSE

  for (line in lines) {
    if (startsWith(line, "Imports:")) {
      in_imports <- TRUE
      line <- sub("Imports:\\s*", "", line)
    } else if (startsWith(line, "Depends:")) {
      in_depends <- TRUE
      line <- sub("Depends:\\s*", "", line)
    } else if (startsWith(line, "Suggests:") || startsWith(line, "LinkingTo:") || startsWith(line, "Enhances:")) {
      in_imports <- FALSE
      in_depends <- FALSE
      next
    }

    if (in_imports || in_depends) {
      line <- gsub("#.*$", "", line)
      line <- trimws(line)

      if (nchar(line) > 0) {
        pkgs <- strsplit(line, ",")[[1]]
        for (pkg_entry in pkgs) {
          pkg_entry <- trimws(pkg_entry)
          pkg_name <- sub("\\s*\\(.*\\)", "", pkg_entry)
          if (nchar(pkg_name) > 0 && pkg_name != "R") {
            dependencies <- c(dependencies, pkg_name)
          }
        }
      }
      if (!grepl(",\\s*$", line)) {
          if (in_imports && (which(lines == line)[1] == length(lines) || !grepl("^[[:space:]]", lines[which(lines == line)[1] + 1]))) in_imports <- FALSE
          if (in_depends && (which(lines == line)[1] == length(lines) || !grepl("^[[:space:]]", lines[which(lines == line)[1] + 1]))) in_depends <- FALSE
      }
    }
  }
  return(unique(dependencies))
}

# Get dependencies from DESCRIPTION
print("Parsing DESCRIPTION file for dependencies...")
required_packages <- get_desc_dependencies()
if (length(required_packages) == 0) {
  print("No packages found in DESCRIPTION file's Imports or Depends fields. Exiting.")
  quit(save = "no", status = 0)
}
print(paste("Required packages from DESCRIPTION:", paste(required_packages, collapse=", ")))

# Determine which packages are not yet installed
print("Checking for already installed packages in user library...")
installed_status <- sapply(required_packages, function(p) requireNamespace(p, quietly = TRUE, lib.loc = r_user_libs_path))
missing_packages <- required_packages[!installed_status]

if (length(missing_packages) == 0) {
  print("All required packages are already installed in the user library.")
  quit(save = "no", status = 0)
}

print(paste("Missing packages to install:", paste(missing_packages, collapse=", ")))

# Attempt to install only the FIRST missing package
pkg_to_install <- missing_packages[1]
print(paste("Attempting to install FIRST missing package:", pkg_to_install, "into", r_user_libs_path))

tryCatch({
  install.packages(pkg_to_install, lib = r_user_libs_path, repos = "https://cloud.r-project.org/", Ncpus = 2)
  print(paste("Successfully attempted install for:", pkg_to_install))
  if (requireNamespace(pkg_to_install, quietly = TRUE, lib.loc = r_user_libs_path)) {
    print(paste(pkg_to_install, "is now installed."))
  } else {
    print(paste("Installation of", pkg_to_install, "seems to have FAILED. It's not found after install attempt."))
  }
}, error = function(e) {
  print(paste("ERROR during install.packages for:", pkg_to_install))
  print(e)
})

# Final check of this specific package
if (requireNamespace(pkg_to_install, quietly = TRUE, lib.loc = r_user_libs_path)) {
    print(paste("Final check: ", pkg_to_install, "is installed."))
} else {
    print(paste("Final check: ", pkg_to_install, "IS NOT installed."))
}

print("Script finished attempting to install one package.")
