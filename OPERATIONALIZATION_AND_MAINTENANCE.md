# HSMR Publication Pipeline: Operationalization & Maintenance Protocol

## Objective
This document outlines the conceptual design for the operationalization and ongoing maintenance of the automated HSMR (Hospital Standardised Mortality Ratios) publication pipeline. It covers automated scheduling, robust error handling and recovery procedures, and strategies for versioning and rollback of publication outputs.

## Guiding Principles
This protocol aims to ensure the HSMR pipeline runs reliably, efficiently, and in a timely manner according to the publication schedule. It emphasizes proactive error management, rapid recovery from failures, and full traceability of all published outputs.

---

## I. Automated Scheduling & Triggering

**Objective:** Ensure timely and reliable automated execution of the HSMR pipeline according to the publication schedule (e.g., quarterly).

**Key Considerations & Conceptual Solutions:**

1.  **Scheduler Selection:**
    *   **Option A: GitHub Actions Scheduled Triggers:**
        *   **Mechanism:** Utilize the `on: schedule:` directive within the main GitHub Actions workflow file (`.github/workflows/hsmr_automation_ci.yml`) using cron expressions.
        *   **Pros:** Simple to implement as the pipeline is already orchestrated via GitHub Actions. Configuration is version-controlled alongside the pipeline code. Native integration with GitHub's monitoring and logging for scheduled runs.
        *   **Cons:** Scheduling granularity is limited by GitHub Actions (e.g., minimum frequency might be every 5 minutes, though typically hourly or daily is sufficient for quarterly publications). Relies on GitHub's scheduler availability and may have less visibility/control compared to dedicated enterprise schedulers for highly complex, cross-system workflows.
    *   **Option B: Cloud-Native Schedulers (e.g., AWS EventBridge Scheduler, Azure Logic Apps Scheduler, Google Cloud Scheduler):**
        *   **Mechanism:** An external cloud scheduler triggers the GitHub Actions workflow using a `workflow_dispatch` event (e.g., via a webhook call to the GitHub API).
        *   **Pros:** Offers robust, highly available, and fine-grained scheduling control. Can integrate with broader cloud ecosystem monitoring and logging. Allows for more complex triggering logic if needed (e.g., dependent on other cloud events).
        *   **Cons:** Introduces an external component to configure and manage. Requires secure handling of API tokens/credentials for triggering `workflow_dispatch`.
    *   **Option C: Dedicated Workflow Orchestrator Schedulers (e.g., Apache Airflow, Prefect, Dagster, Kubeflow Pipelines):**
        *   **Mechanism:** If a dedicated workflow orchestrator is adopted for managing the HSMR pipeline (potentially for more complex dependencies, retry logic, and UI-based monitoring), these tools come with powerful built-in scheduling capabilities.
        *   **Pros:** Provides full control over scheduling, complex inter-task dependencies, backfills, history, and monitoring, all within a unified platform.
        *   **Cons:** Requires setting up and managing the orchestrator tool itself, which can be a significant undertaking.
    *   **Initial Recommendation:** For the current GitHub Actions-centric design of the HSMR pipeline, **GitHub Actions Scheduled Triggers** is the most straightforward starting point.
    *   **Future Scalability:** If the pipeline's orchestration needs grow significantly (e.g., more complex interdependencies with external systems, need for dynamic parameter passing to scheduled runs not easily supported by simple cron), migrating to a cloud-native scheduler triggering `workflow_dispatch` or a full workflow orchestrator should be considered.

2.  **Parameterization for Scheduled Runs:**
    *   **Dynamic Date Calculation:** The pipeline must correctly determine the target publication period when run on a schedule. The existing `update_hsmr_config.py` script (which calculates dates for the *previous* quarter based on the current execution date) is designed for this.
    *   **Manual Triggering with Parameters:** The `workflow_dispatch` trigger in GitHub Actions allows for manual runs. It can also be configured to accept input parameters, enabling users to specify a non-standard publication period (e.g., for re-running a previous quarter or for testing). This would require the `update_hsmr_config.py` script to be able to accept date parameters or for the workflow to pass these parameters to relevant scripts.

3.  **Monitoring of Scheduled Jobs:**
    *   The chosen scheduling mechanism must provide clear visibility into the status of scheduled job triggers (e.g., did the cron trigger fire successfully?).
    *   GitHub Actions provides a run history for scheduled workflows, showing success or failure of each run.
    *   Alerts should be configured (as per Section II. Robust Monitoring, Alerting & Logging in the Production Environment Protocol) for failures of scheduled pipeline runs.

4.  **Handling Overlapping Runs (Idempotency & Concurrency Control):**
    *   **Idempotency:** Design all pipeline scripts and operations to be idempotent where possible (i.e., running them multiple times with the same inputs produces the same result without unintended side effects). This is crucial for recovery and re-runs.
    *   **Concurrency Control (for GitHub Actions):** GitHub Actions allows specifying concurrency groups for workflows (`concurrency:` key). This can be used to ensure that only one instance of the production HSMR pipeline runs at a time for a given scope (e.g., the `main` branch or a specific environment context), preventing overlapping runs if a scheduled run is delayed and another is triggered.
        *   Example: `concurrency: hsmr_production_pipeline`

---

## II. Comprehensive Error Handling & Recovery (Production Grade)

**Objective:** Minimize pipeline failures, ensure graceful degradation when issues occur (where appropriate and safe), and facilitate rapid recovery with clear diagnostics and defined human intervention points.

**Key Considerations & Conceptual Solutions:**

1.  **Script-Level Error Handling (R, Python, Shell):**
    *   **Explicit Error Trapping:** Utilize `try-catch` blocks in R, `try-except` in Python, and `trap` with error checking in shell scripts for all operations prone to failure (e.g., file I/O, database connections, API calls, external process calls, data transformations that might fail on unexpected data).
    *   **Specific Exception Handling:** Catch specific, anticipated exceptions rather than generic ones to allow for tailored retry logic or error reporting. Log the full error message and stack trace.
    *   **Non-Zero Exit Codes:** Ensure all scripts reliably return non-zero exit codes upon encountering unrecoverable errors. This is critical for signaling failure to the orchestrator (e.g., GitHub Actions, which will automatically fail the step). The `set -e` option in shell scripts helps enforce this.

2.  **Retry Mechanisms:**
    *   **For Transient Errors:** Implement automated retries with exponential backoff and jitter for operations known to be susceptible to transient issues:
        *   Database connection attempts.
        *   Network calls to external services (if any are introduced).
        *   File transfers to/from cloud storage (robustness against temporary network glitches).
    *   **Configurable Retries:** The number of retry attempts and backoff parameters should ideally be configurable (e.g., via environment variables or the `hsmr_config.json`).
    *   **GitHub Actions Step Retries:** GitHub Actions offers a basic `continue-on-error` for steps and some actions might have built-in retry capabilities. However, for fine-grained control, implementing retries within the scripts themselves (especially for network operations) is often more effective.

3.  **Graceful Degradation & Partial Success (To be used with extreme caution for HSMR):**
    *   **Concept:** In some systems, if a non-critical component fails (e.g., generating an optional chart), the main pipeline might still be allowed to complete successfully, flagging the partial failure.
    *   **HSMR Context:** Given the sensitivity and critical nature of HSMR data, data integrity is paramount. Most failures encountered during data extraction, processing, validation, or core report generation should likely halt the entire pipeline run for that quarter to prevent the publication of potentially erroneous or incomplete information. This feature should be avoided unless a very clear case for a non-critical, safely ignorable failure can be made and approved.

4.  **Dead-Letter Queues (DLQ) / Enhanced Error Reporting:**
    *   **Centralized Logging:** As defined in the Production Environment Protocol, all detailed error information (input parameters, state at time of error, full error logs, stack traces) must be captured and sent to the centralized logging system.
    *   **Alerting:** Critical errors that cause pipeline halts must trigger immediate alerts to the responsible team.
    *   **Conceptual DLQ for Data Issues:** While HSMR is largely batch-processed, if there were ever a stage involving row-by-row processing where individual records could fail validation or processing, such records could theoretically be shunted to a "dead-letter" storage area for later investigation. This is less applicable to the current design but a concept to be aware of for data-intensive pipelines.

5.  **Human Intervention Workflow & Runbooks:**
    *   **Clear Notifications:** When automated recovery (retries) fails and the pipeline halts, the system must clearly notify the designated operational team with actionable information (failed job/step, link to logs, error summary).
    *   **Standard Operating Procedures (SOPs) / Runbooks:** Develop and maintain runbooks for common failure scenarios. These should outline:
        *   Troubleshooting steps.
        *   Escalation procedures.
        *   Steps for manual correction of underlying issues (if applicable).
        *   Instructions for safely re-running failed parts of the pipeline.
    *   **Re-run Capabilities:**
        *   GitHub Actions allows re-running failed jobs or entire workflows.
        *   For more granular re-runs (e.g., a specific script within a job), the pipeline might need to be designed with checkpoints or idempotent stages if feasible, or rely on manual re-triggering of the relevant job after correction.

6.  **Timeout Configuration:**
    *   **Step/Job Timeouts:** Configure appropriate execution timeouts for individual steps and overall jobs within the GitHub Actions workflow to prevent indefinite hangs (e.g., if an R script enters an unexpected infinite loop or an external resource is unresponsive).
    *   **Script-Internal Timeouts:** Critical network calls or external process interactions within scripts should also have their own internal timeouts if the libraries used support them.

---

## III. Versioning & Rollback Strategy (for Publication Outputs)

**Objective:** Ensure full traceability of all published HSMR outputs and enable a reliable rollback to a previous, known-good version in the event a critical error is discovered post-publication.

**Key Considerations & Conceptual Solutions:**

1.  **Comprehensive Versioning of All Components:**
    *   **Code & Configuration:** All scripts (R, Python, Shell, SQL), R Markdown (`.Rmd`) files, Infrastructure as Code (IaC) templates, and the GitHub Actions workflow file (`hsmr_automation_ci.yml`) must be version-controlled in Git. Use semantic versioning (e.g., `v1.0.2`) or commit hashes/tags to mark specific versions used for each publication run.
    *   **Data (Source Extracts & Processed Data):**
        *   **Raw Data Extracts:** If raw data extracts are stored long-term (as per the Data Security Protocol), they should be versioned, typically by the date of extraction or the pipeline run ID that generated them.
        *   **Processed Data Artifacts:** Artifacts generated by each pipeline run (e.g., `smr_output_YYYY_QN.csv`, `trends_output_YYYY_QN.csv`) are inherently versioned by the unique pipeline run ID (e.g., `github.run_id` used in artifact naming). Store these in a version-aware artifact repository or versioned cloud storage.
        *   **Lookup/Reference Files:** These (e.g., `lookup_hospital_codes.csv`) should be version-controlled in Git if they change infrequently. If they are large or change very often outside of code release cycles, they might be versioned in a dedicated data store, with their specific version used by a run recorded in `hsmr_config.json`.
    *   **Models (Statistical/AI):** If any statistical models (e.g., the logistic regression model for SMR if it were trained and versioned offline) or AI models (for anomaly detection) are used, these models and their training data/parameters must be versioned (e.g., using tools like MLflow, DVC, or clear file naming conventions with associated metadata).
    *   **Configuration File (`hsmr_config.json`):** The `hsmr_config.json` generated for each specific run (containing date parameters, file manifests with hashes, etc.) is effectively a versioned configuration for that run. It's included in the run's artifacts. Master templates or scripts that generate this config (`update_hsmr_config.py`) are versioned in Git.

2.  **Versioning of Final Publication Outputs:**
    *   **Unique Publication Identifiers:** Each distinct HSMR publication set (which includes report PDFs/HTMLs, associated public data files, etc.) must be assigned a unique version identifier. This could be, for example, `HSMR_Report_YYYY_QN_RunID_vMAJOR.MINOR.PATCH`. The `YYYY_QN` indicates the reporting period, `RunID` links it to the specific pipeline execution, and `vMAJOR.MINOR.PATCH` could denote versions if a specific period's report is re-issued with corrections.
    *   **Immutable Storage for Publications:** Store each version of the final, approved publication set in a secure, version-enabled storage location (e.g., a dedicated S3 bucket with versioning enabled, a controlled document management system, or a specific section of the defined archive). The `publication_outputs/` artifact from Phase 5, once validated and approved, represents a versioned set of these documents.

3.  **Rollback Procedure (Conceptual):**
    *   **A. Detection & Decision:** A formal process must be in place for:
        *   Identifying a critical error in a live, published HSMR report or dataset.
        *   Assessing the impact of the error.
        *   Making a formal decision (involving relevant stakeholders like data owners, subject matter experts, communications teams, and governance bodies) that a rollback to a previous version or a republication of a corrected version is necessary.
    *   **B. Mechanism for Rollback (Restoring a Previous "Public Truth"):**
        *   **If Served from Versioned System:** If publication files are served via a system that inherently supports pointing to specific versions (e.g., a web content management system with versioning, a CDN that can switch origins or versions): Update the system configuration to point to the last known good version's files.
        *   **If Direct File Replacement:** Retrieve the complete set of files for the last known good version from the immutable archive (see point 2b above) and use these to replace the currently live (erroneous) files in the public distribution locations.
        *   **Access Control:** Ensure that only authorized personnel can perform rollback operations.
    *   **C. Communication Plan:** Have a predefined communication plan to inform stakeholders (internal and external, including the public if necessary) about the rollback, the reason for it, and when a corrected version will be available.
    *   **D. Audit Trail:** The entire rollback process (the error identified, the decision-making, the technical actions taken, and all communications) must be thoroughly documented and form part of the publication's auditable history.

4.  **Data "Rollback" (Focus on Correction and Re-Processing):**
    *   **No Source Data Alteration:** Rolling back or altering *data* in the original source systems or historical data warehouses due to a pipeline error is typically not feasible, not desirable, and can break data provenance.
    *   **Focus on Pipeline Correction:** The strategy should be to:
        *   Identify and correct the root cause of the error within the HSMR pipeline (e.g., a bug in an R script, an incorrect lookup file, a flawed configuration parameter).
        *   Archive the erroneous version of the publication outputs and clearly mark them as "superseded" or "retracted," noting the reason.
        *   Re-run the corrected pipeline for the affected publication period (potentially using the original raw data extract for that period, if still available and appropriate) to generate a new, corrected version of the publication.
        *   This new version will then go through the usual QA and approval process before being published.

---
This Operationalization and Maintenance Protocol provides a framework for ensuring the HSMR pipeline is managed effectively in a production environment. Continuous review and adaptation of these procedures will be necessary as the pipeline and its operational context evolve.
---
