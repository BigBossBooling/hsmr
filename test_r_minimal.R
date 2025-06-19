print("R script started.")
print(paste("R.version.string:", R.version.string))
# sessionInfo() provides more details about loaded packages, paths etc.
print("--- Session Info ---")
sessionInfo()
print("--- .libPaths() ---")
print(.libPaths())
print("R script finished.")
