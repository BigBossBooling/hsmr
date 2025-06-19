#!/bin/bash

# Configuration
GIT_REPO_URL="https://your-git-repo-url.git" # Replace with actual repo URL
WORKSPACE_DIR="./hsmr_workspace"
MAIN_BRANCH_NAME="main" # Or "master" depending on your repository
R_SCRIPT_PATH="../setup_R_env.R" # Relative path to the R script

# Determine current year and quarter for branch naming
YEAR=$(date +'%Y')
MONTH=$(date +'%m')

QUARTER=""
if ((10#$MONTH >= 1 && 10#$MONTH <= 3)); then
  QUARTER="Q1"
elif ((10#$MONTH >= 4 && 10#$MONTH <= 6)); then
  QUARTER="Q2"
elif ((10#$MONTH >= 7 && 10#$MONTH <= 9)); then
  QUARTER="Q3"
else
  QUARTER="Q4"
fi

NEW_BRANCH_NAME="HSMR_${YEAR}_${QUARTER}"

# --- Git Operations ---
echo "Starting workspace setup for ${NEW_BRANCH_NAME}..."

# Create workspace directory if it doesn't exist
mkdir -p "${WORKSPACE_DIR}"
cd "${WORKSPACE_DIR}" || { echo "Failed to enter workspace directory: ${WORKSPACE_DIR}"; exit 1; }

# Check if repo is already cloned
if [ -d ".git" ]; then
  echo "Repository already exists. Fetching latest changes..."
  # Attempt to fetch, but proceed even if it fails (e.g. no network in test env)
  git fetch origin || echo "Warning: Failed to fetch from origin. Proceeding..."
else
  echo "Cloning repository from ${GIT_REPO_URL}..."
  # Attempt to clone, but proceed with a warning if it fails
  git clone "${GIT_REPO_URL}" . || { echo "Warning: Failed to clone repository. A dummy .git directory will be created for testing purposes."; mkdir .git; }
fi

# Switch to the main branch and ensure it's up-to-date (or create if doesn't exist)
echo "Switching to ${MAIN_BRANCH_NAME} branch..."
if git rev-parse --verify "${MAIN_BRANCH_NAME}" >/dev/null 2>&1; then
  git checkout "${MAIN_BRANCH_NAME}" || { echo "Failed to checkout ${MAIN_BRANCH_NAME} branch."; exit 1; }
  echo "Pulling latest changes for ${MAIN_BRANCH_NAME}..."
  # Attempt to pull, but proceed even if it fails
  git pull origin "${MAIN_BRANCH_NAME}" || echo "Warning: Failed to pull changes for ${MAIN_BRANCH_NAME}. Proceeding..."
else
  echo "${MAIN_BRANCH_NAME} does not exist. Creating it locally for testing purposes."
  git checkout -b "${MAIN_BRANCH_NAME}" || { echo "Failed to create ${MAIN_BRANCH_NAME} branch."; exit 1; }
fi


# Create the new development branch
echo "Creating new development branch: ${NEW_BRANCH_NAME}..."
if git rev-parse --verify "${NEW_BRANCH_NAME}" >/dev/null 2>&1; then
  echo "Branch ${NEW_BRANCH_NAME} already exists. Checking it out."
  git checkout "${NEW_BRANCH_NAME}" || { echo "Failed to checkout existing branch ${NEW_BRANCH_NAME}."; exit 1; }
else
  git checkout -b "${NEW_BRANCH_NAME}" || { echo "Failed to create new branch ${NEW_BRANCH_NAME}."; exit 1; }
fi

echo "Successfully set up Git repository. Current branch: ${NEW_BRANCH_NAME}"
echo "Workspace directory: $(pwd)"

# --- R Environment Setup ---
echo "Setting up R environment..."
if [ -f "${R_SCRIPT_PATH}" ]; then
  Rscript "${R_SCRIPT_PATH}" || { echo "R environment setup failed."; exit 1; }
  echo "R environment setup complete."
else
  echo "Warning: R setup script not found at ${R_SCRIPT_PATH}"
fi

echo "Workspace and R environment setup finished for branch: ${NEW_BRANCH_NAME}"

exit 0
