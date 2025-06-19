# HSMR Publication Pipeline: Comprehensive Error Handling & Recovery Protocol (Production Grade)

## Objective
This document outlines the conceptual design for a comprehensive error handling and recovery strategy for the HSMR (Hospital Standardised Mortality Ratios) publication pipeline when operating in a production environment. The goal is to minimize pipeline failures, ensure graceful degradation where appropriate (though typically full halt for HSMR data integrity), provide clear diagnostics for rapid troubleshooting, and facilitate efficient recovery.

## Guiding Principles
This protocol emphasizes proactive error trapping, informative logging, automated retries for transient issues, robust reporting for persistent errors, clear human intervention procedures, and prevention of indefinite pipeline hangs. It aims to enhance the overall reliability and maintainability of the HSMR automation.

---

## I. Script-Level Error Handling Enhancements (R, Python, Shell)

**Objective:** To ensure individual scripts and code components within the pipeline are internally robust, catch errors gracefully at the point of occurrence, log them informatively, and signal failure clearly to the orchestrating system (e.g., GitHub Actions) by exiting with appropriate status codes.

**Conceptual Solutions:**

1.  **Standardized Error Trapping & Propagation:**
    *   **R Scripts (`scripts/*.R`):**
        *   Utilize `tryCatch()` blocks around critical operations such as data loading/saving (`readr::read_csv`, `readr::write_csv`), database interactions (if any directly in R via `DBI`), complex data manipulations (`dplyr` chains), model fitting, and file I/O (`file.exists`, `source`).
        *   **Error Handler Logic (within `error = function(e) { ... }`):**
            *   Log the detailed error message provided by R: `conditionMessage(e)`.
            *   Capture and log the call stack: `traceback()` or preferably use `rlang::last_error()` or `rlang::last_trace()` for more structured trace information if `rlang` is adopted.
            *   Construct a context-specific error message prefix, e.g., "Error during SMR data wrangling for period [YYYY_QN]: ".
            *   Crucially, ensure the error handler concludes with `stop(paste(context_message_prefix, base_error_message_from_e))` to propagate the error condition. This ensures `Rscript` exits with a non-zero status code, which is essential for GitHub Actions (or any orchestrator) to recognize the step failure.
    *   **Python Scripts (`update_hsmr_config.py`, `qa_scripts/*.py`, `scripts/archive_and_stage.py`):**
        *   Employ `try...except...finally` blocks extensively.
        *   **Specific Exceptions:** Catch specific exception types (e.g., `FileNotFoundError`, `pd.errors.EmptyDataError`, `json.JSONDecodeError`, `requests.exceptions.ConnectionError`, custom-defined exceptions for application logic) rather than generic `except Exception:`. This allows for more nuanced error handling or reporting.
        *   **Exception Handler Logic (within `except SomeError as e:`):**
            *   Log detailed error information using Python's `logging` module, including the exception type, message, and full stack trace (e.g., via `logging.exception("Contextual message:")`).
            *   Construct context-specific messages.
            *   For unrecoverable errors within the script's scope, re-raise the exception or use `sys.exit(error_code)` (where `error_code != 0`) after logging to ensure the script failure is signaled to the orchestrator.
        *   **`finally` Blocks:** Use `finally` blocks for essential cleanup operations, such as closing database connections (if any), releasing file locks, or cleaning up temporary files, ensuring these actions occur regardless of whether an exception occurred.
    *   **Shell Scripts (used in GitHub Actions `run` steps):**
        *   **Strict Error Checking:** Always start scripts with `set -e` (or `set -o errexit`) to ensure the script exits immediately if any command fails.
        *   **Pipeline Safety:** Use `set -o pipefail` to ensure that a failure in any part of a pipeline (e.g., `command1 | command2`) results in a non-zero exit code for the entire pipeline.
        *   **Error Trapping (`trap`):** Use the `trap` command for cleanup actions (e.g., removing temporary files) on script exit ( `EXIT` signal) or on specific error signals (`ERR`).
        *   **Error Reporting:** Use `echo` to `>&2` (stderr) for error messages or use a dedicated logging function if defined.

2.  **Actionable and Contextual Error Messages:**
    *   Error messages logged or printed to console should be clear, concise, and provide sufficient context to aid in troubleshooting. They should ideally state:
        *   **What:** The operation that failed (e.g., "Reading input file for SMR processing", "Connecting to database for LTT extract").
        *   **Why:** The specific error encountered (e.g., "File not found", "Database timeout", "Invalid data format in column X").
        *   **Context:** Relevant parameters or identifiers (e.g., filename: `smr_extract_2023_Q4.csv`, pipeline_run_id: `12345`, config parameter: `db_server=myprodserver`).
        *   **Potential Impact/Next Steps (if inferable by the script):** E.g., "Data extraction cannot proceed. Please check file existence or network connectivity."

3.  **Input Data Validation within Scripts (Defensive Programming):**
    *   While comprehensive data validation occurs in Phase 4 (QA), individual scripts should still perform basic sanity checks on their direct inputs, especially if those inputs come from external sources or previous steps whose integrity isn't absolutely guaranteed by an immediately preceding hash check *within that same script's context*.
    *   Examples: Checking for expected data types for critical parameters, ensuring required columns are present in input dataframes (even after schema validation, as a defense-in-depth measure), checking for non-null values for essential inputs.
    *   Fail fast with clear error messages if these internal sanity checks are violated.

---

## II. Configurable Retry Mechanisms

**Objective:** To design and implement mechanisms that allow the pipeline to automatically recover from transient (temporary) issues without failing the entire pipeline run, thereby increasing resilience.

**Conceptual Solutions:**

1.  **Identify Retryable Operations & Error Types:**
    *   **Database Connections/Queries:** Transient network glitches, temporary database server overload, brief deadlocks.
    *   **API Calls to External Services (if any are introduced in the future):** Network timeouts, rate limiting responses (e.g., HTTP 429), temporary server errors (HTTP 502, 503, 504).
    *   **Cloud Storage Operations (e.g., S3, Azure Blob):** Transient network issues, eventual consistency related read-after-write issues (rare but possible for some operations).
    *   **File System Operations (especially if on network shares):** Temporary unavailability of network file systems.
    *   **Non-Retryable Errors:** Errors like "file not found" (for critical inputs), "invalid credentials," data format errors, or critical bugs in scripts are generally not retryable without code/config changes or manual intervention.

2.  **Implementation Strategy for Retries:**
    *   **Within Application Scripts (R/Python - Preferred for fine-grained control):**
        *   Implement retry logic directly within the R or Python scripts for specific, identified retryable operations.
        *   **Libraries:**
            *   **Python:** Utilize robust libraries like `tenacity` or `retry` which simplify the implementation of various retry strategies.
            *   **R:** May require custom functions using a loop, `Sys.sleep()` for delays, and incremental backoff logic.
        *   **Key Retry Parameters:**
            *   `max_retries`: Define the maximum number of attempts for a failing operation (e.g., 3 to 5 attempts).
            *   `delay_seconds` (or `wait_fixed`): The initial delay before the first retry (e.g., 5 seconds, 10 seconds).
            *   `backoff_factor` (or `wait_exponential_multiplier`): A multiplier for the delay between subsequent retries (e.g., a factor of 2 results in delays like 5s, 10s, 20s). This is exponential backoff.
            *   `jitter`: Add a small random amount to delay intervals to prevent synchronized retries from multiple processes (thundering herd problem), especially if the pipeline scales horizontally.
        *   **Logging Retries:** Log each retry attempt, the delay, and the outcome (success or failure of that attempt). This is crucial for understanding operational behavior.
    *   **In GitHub Actions (Step-Level Retries - More Limited):**
        *   GitHub Actions itself does not have a built-in, general-purpose retry mechanism for individual `run` steps with complex backoff strategies. `continue-on-error` allows a step to fail without failing the job, but it's not a retry.
        *   Some specific third-party marketplace Actions might have their own retry parameters.
        *   Therefore, implementing retry logic within the scripts offers more control and is generally preferred for application-level transient errors.

3.  **Configuration of Retry Parameters:**
    *   Retry parameters (max attempts, delay, backoff factor) should ideally be configurable rather than hardcoded directly in scripts.
    *   **Options:**
        *   Store in `hsmr_config.json` under a dedicated section (e.g., `"retry_config": {"db_connection": {"max_attempts": 3, "delay": 10}}`).
        *   Set via environment variables, which can be configured in the GitHub Actions workflow (and potentially passed from secrets if needed, though retry counts are usually not secret).
    *   This allows for tuning retry behavior per environment (e.g., more aggressive retries in dev/test, more conservative in prod) or per type of operation without code changes.

---

## III. Dead-Letter Queues (DLQ) / Robust Error Reporting & Handling

**Objective:** For persistent, non-transient errors that cannot be resolved by automated retries, ensure that all necessary diagnostic information is comprehensively captured, preserved, and routed appropriately for human investigation and action.

**Conceptual Solutions:**

1.  **Centralized Logging as Primary Diagnostic Store:**
    *   As detailed in the "Monitoring, Alerting & Logging Protocol," the centralized logging system (e.g., ELK, CloudWatch Logs, Azure Monitor Logs) is the primary destination for all detailed error information. This includes full error messages, stack traces, relevant input parameters, pipeline run IDs, and contextual information.
2.  **Alerting System Integration:**
    *   Critical errors that are logged after exhausting retries (or for non-retryable conditions) must trigger alerts to the designated operations or development team via the established alerting system (e.g., PagerDuty, Slack, email).
3.  **"Error Artifacts" in GitHub Actions Context:**
    *   **Purpose:** If a script fails due to issues with a specific input file (that it cannot recover from, e.g., a malformed critical data file despite passing initial hash checks), it can be beneficial to save this problematic input file alongside detailed error logs as a specific GitHub Actions artifact.
    *   **Mechanism:** The script would log the error and its intent to archive the problematic file. A subsequent step in the GitHub Actions workflow, conditioned to run on failure (e.g., using `if: failure()`), could then attempt to upload the specific file(s) implicated in the error. This requires the failing script to communicate which file(s) to archive (e.g., by writing their paths to a known temporary file).
    *   **Benefit:** Aids in offline debugging by providing the exact data that caused the failure.
4.  **Conceptual Dead-Letter Queue (DLQ) for Item-Level Processing (Less Directly Applicable to current HSMR design):**
    *   **Context:** True DLQs are typically used in systems that process streams of individual data items or messages (e.g., from a message queue like AWS SQS or Azure Service Bus). If a specific item consistently fails processing after retries, it's moved to a DLQ for later inspection and handling, allowing the main processing flow to continue for valid items.
    *   **HSMR Applicability:** The current HSMR pipeline design is primarily batch-oriented (processing whole files). A direct DLQ for individual data *rows* is less applicable unless a specific stage is re-architected to process row-by-row from a queue. However, the "Error Artifacts" concept above serves a similar purpose for problematic *files*.

---

## IV. Human Intervention Workflows & Runbooks

**Objective:** Define clear, documented processes for situations where automated error handling and retry mechanisms are exhausted, requiring human analysis, intervention, and decision-making to resolve issues and resume or appropriately conclude a pipeline run.

**Conceptual Solutions:**

1.  **Notification & Alerting Protocols:**
    *   **Clear Alert Content:** Alerts triggered by unrecoverable pipeline errors (as per the Monitoring plan) must clearly indicate:
        *   Severity of the error (e.g., CRITICAL - Pipeline Halted).
        *   Affected pipeline, job, and step (e.g., "HSMR Production Pipeline / process_and_analyze_data job / Run SMR Data Production Script step").
        *   Unique Pipeline Run ID.
        *   A concise summary of the error.
        *   A direct link to the detailed logs in the centralized logging system or GitHub Actions run logs.
        *   Timestamp of failure.
    *   **Targeted Notifications:** Define on-call rotations or responsible teams for different types of alerts or pipeline stages. Ensure alerts are routed to the personnel equipped to handle them.

2.  **Standard Operating Procedures (SOPs) / Runbooks:**
    *   **Development & Maintenance:** Develop and maintain a library of SOPs or runbooks for common and critical failure scenarios. Examples:
        *   "SOP: Handling Database Unreachable Errors in Phase 2 Data Extraction."
        *   "SOP: Investigating Critical Input File Missing or Corrupt Errors."
        *   "SOP: Responding to Schema Validation Failures in Phase 4."
        *   "SOP: Troubleshooting SMR Model Convergence Errors (if applicable in R)."
    *   **Content of SOPs:** Each SOP should include:
        *   **Symptoms:** How the error typically manifests (alert messages, log patterns).
        *   **Diagnostic Steps:** How to use logs, monitoring dashboards, and other tools to pinpoint the root cause.
        *   **Known Causes:** List of common or known causes for this type of error.
        *   **Resolution Steps:** Specific actions to take to resolve the issue (e.g., correcting a configuration, restarting a dependent service, manually providing a missing file after verification).
        *   **Escalation Procedures:** Who to contact if the issue cannot be resolved by the first responder.
        *   **Post-Resolution Actions:** Steps for safely re-running or resuming the pipeline.

3.  **Pipeline Re-run/Resume Capabilities:**
    *   **GitHub Actions:** The GitHub Actions platform allows for:
        *   Re-running entire failed workflow runs.
        *   Re-running specific failed jobs within a workflow run.
    *   **Idempotency & Checkpoints (Desirable Design):**
        *   **Idempotency:** Scripts should be designed to be idempotent where feasible (i.e., running them multiple times with the same inputs produces the same outcome without adverse side effects). This makes re-runs much safer. For example, writing outputs to temporary, run-specific locations first, and then atomically moving/promoting them to the final destination upon successful completion of a stage. Or, checking if an output already exists and its hash matches, then skipping regeneration.
        *   **Checkpoints:** For very long-running pipelines, consider designing logical checkpoints. If a failure occurs after a checkpoint, the pipeline might be resumable from that point rather than starting from scratch (this often requires more complex state management and is a feature of dedicated workflow orchestrators). For the HSMR quarterly run, re-running a failed job might be an acceptable granularity.

4.  **Secure Access for Troubleshooting & Correction:**
    *   Provide secure, audited, and typically time-limited (or just-in-time) access for authorized operational or development personnel to relevant systems for troubleshooting. This might include:
        *   Read-only access to production logs, metrics dashboards, and artifact storage.
        *   In rare, controlled circumstances, temporary elevated permissions might be needed for specific corrective actions if a fully automated recovery is not possible. Such access must be highly controlled, approved, and audited.

---

## V. Timeout Configuration

**Objective:** Prevent pipeline steps, script executions, or external calls from hanging indefinitely, which can consume resources, delay the detection of failures, and potentially block subsequent scheduled runs.

**Conceptual Solutions:**

1.  **GitHub Actions Workflow Timeouts:**
    *   **Job-Level Timeouts:** Set an appropriate `timeout-minutes` for each job in the `hsmr_automation_ci.yml` workflow. This is an overall time limit for all steps within that job. The timeout should be generous enough to accommodate normal processing fluctuations but tight enough to catch genuine hangs.
        *   Example: `timeout-minutes: 120` (for a job expected to take ~60-90 minutes).
    *   **Step-Level Timeouts:** For individual `run` steps within a job, a `timeout-minutes` can also be specified if a particular script or command is known to be prone to hanging but should not exceed a specific duration. This offers more granular control.
        *   Example: `run: Rscript my_long_script.R\ntimeout-minutes: 30`

2.  **Script-Internal Timeouts (for External Calls):**
    *   Within the R and Python scripts, implement timeouts for specific operations that involve external interactions:
        *   **Database Queries:** Most database driver libraries (e.g., `odbc` in R, `pyodbc` or `psycopg2` in Python) allow setting connection timeouts and query execution timeouts.
        *   **API Calls:** HTTP client libraries (e.g., `httr` in R, `requests` in Python) have parameters for connection timeouts and read timeouts.
        *   **Long-Running Computations (Internal):** For computationally intensive steps within a script (e.g., a complex model fitting process that is iterative), consider building in internal checks for maximum iterations or elapsed duration to prevent true infinite loops, if the algorithm allows. This is more about defensive coding within the script's logic.

3.  **Alerting on Timeouts:**
    *   Ensure that alerts are configured (via the Monitoring system) if GitHub Actions job or step timeouts are hit. A timeout is a clear indication of a problem that needs investigation (e.g., an unresponsive script, an unexpectedly large dataset causing extreme processing times, or a deadlock).

---
By implementing this comprehensive error handling and recovery protocol, the HSMR pipeline's robustness and operational stability in a production environment will be significantly enhanced, ensuring that issues are managed effectively and that the pipeline can deliver reliable outputs.
---
