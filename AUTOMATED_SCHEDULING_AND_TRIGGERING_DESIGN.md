# HSMR Publication Pipeline: Automated Scheduling & Triggering Design

## Objective
This document outlines the conceptual design for the automated scheduling and triggering mechanisms for the HSMR (Hospital Standardised Mortality Ratios) publication pipeline. It aims to ensure timely, reliable, and flexible execution of the pipeline according to both regular publication schedules and ad-hoc operational needs.

## Guiding Principles
The design prioritizes reliability for critical production runs, flexibility for manual interventions and reprocessing, clear parameterization, and robust monitoring of the triggering process itself.

---

## I. Scheduler Selection & Justification

**Objective:** To select and define the primary mechanism for automated, periodic execution of the HSMR pipeline (e.g., quarterly) and for manual ad-hoc runs.

**Options & Analysis:**

1.  **GitHub Actions Scheduled Triggers (`on: schedule:`):**
    *   **Mechanism:** Uses `cron` expressions directly within the `hsmr_automation_ci.yml` workflow file to trigger runs on a predefined schedule.
    *   **Pros:**
        *   Native to the GitHub Actions environment where the pipeline is defined and executed.
        *   Simple `cron` syntax for defining schedules.
        *   No external dependencies if the entire pipeline is orchestrated as a single, cohesive GitHub Actions workflow.
        *   Scheduling configuration is version-controlled alongside the pipeline code.
    *   **Cons:**
        *   GitHub Actions schedules are "best-effort" and can sometimes be delayed if GitHub's platform is under heavy load. This might not be ideal for time-critical production runs.
        *   Scheduling granularity is limited by `cron` capabilities (typically to the minute).
        *   Lacks advanced enterprise scheduling features like complex calendar-based scheduling (e.g., "third Tuesday of the month"), inter-system dependency management, or a centralized dashboard for managing many different scheduled jobs across an organization.
        *   Monitoring of the trigger's successful firing is within the GitHub Actions UI ("Scheduled" runs).

2.  **Cloud-Native Schedulers (e.g., AWS EventBridge Scheduler, Azure Logic Apps with Recurrence trigger, Google Cloud Scheduler):**
    *   **Mechanism:** An external cloud scheduler service is configured to trigger the HSMR GitHub Actions workflow, typically by making an API call to GitHub to initiate a `workflow_dispatch` event. This often involves a small intermediary function (e.g., AWS Lambda, Azure Function) to make the GitHub API call securely.
    *   **Pros:**
        *   **High Reliability & Precision:** These services are designed for robust, enterprise-grade scheduling with precise timing and high availability.
        *   **Fine-grained Control:** Offer more advanced scheduling options than simple cron (e.g., specific dates, complex recurrence patterns, time zone management).
        *   **Integrated Monitoring:** Integrate seamlessly with the cloud provider's monitoring and logging services (e.g., AWS CloudWatch, Azure Monitor), allowing for robust monitoring of the trigger itself.
        *   **Event-Based Capabilities:** Can often trigger workflows based on other cloud events, not just time schedules, which might be useful for future enhancements.
    *   **Cons:**
        *   Introduces an external cloud service component that needs to be configured, managed (though often simple), and secured.
        *   Requires setting up secure authentication from the cloud scheduler to the GitHub API (e.g., using a GitHub App or Personal Access Token stored securely).

3.  **Dedicated Workflow Orchestrator Schedulers (e.g., Apache Airflow, Prefect, Dagster, Kubeflow Pipelines):**
    *   **Mechanism:** If the HSMR pipeline (or parts of it) were to be managed by a dedicated workflow orchestration tool, these tools come with their own powerful, integrated scheduling capabilities.
    *   **Pros:**
        *   Offers the most comprehensive control over scheduling, complex inter-task dependencies within and across pipelines, backfilling capabilities, a rich user interface for monitoring and management, versioning of workflows (DAGs), and an extensive ecosystem of plugins and integrations.
    *   **Cons:**
        *   Represents the highest operational overhead in terms of setting up, managing, and maintaining the orchestrator tool itself.
        *   Likely overkill if the HSMR pipeline is relatively self-contained and its primary orchestration is managed within GitHub Actions.

**Primary Recommendation for HSMR Pipeline:**

*   **A. For Regularly Scheduled Quarterly Production Runs:**
    *   **Mechanism:** **Cloud-Native Scheduler** (e.g., AWS EventBridge Scheduler or Azure Logic Apps Recurrence Trigger).
    *   **Action:** This scheduler will be configured to make a secure API call to GitHub to trigger the HSMR pipeline using the `workflow_dispatch` event.
    *   **Justification:** This approach provides a higher degree of reliability, precision, and external monitoring for critical, time-sensitive production runs compared to GitHub's native `on: schedule:`. It allows for better separation of scheduling concerns from the workflow definition and leverages the robustness of enterprise-grade cloud scheduling services. The operational overhead for a simple scheduled trigger is typically low.
*   **B. For Manual Ad-Hoc Runs (e.g., reprocessing a specific quarter, development runs, testing):**
    *   **Mechanism:** **GitHub Actions `workflow_dispatch` trigger.**
    *   **Justification:** This is already planned for (and potentially partially implemented in) the `hsmr_automation_ci.yml` workflow. It provides a simple, direct, and permission-controlled way for authorized users to trigger the pipeline manually from the GitHub UI, potentially with specific input parameters.

**Infrastructure as Code (IaC) for Schedulers:**
*   The configuration of the chosen cloud-native scheduler (e.g., the AWS EventBridge rule and any associated Lambda function, or the Azure Logic App definition) must be defined and managed using Infrastructure as Code (IaC) principles (e.g., Terraform, CloudFormation, ARM/Bicep). This ensures the scheduling mechanism is version-controlled, reproducible, and can be deployed consistently.

---

## II. Parameterization for Scheduled and Manual Runs

**Objective:** Ensure that both scheduled and manually triggered pipeline runs can correctly determine or be configured for the target publication period and any other necessary runtime parameters.

**Conceptual Solutions:**

1.  **Scheduled Runs (Triggered by Cloud Scheduler via `workflow_dispatch`):**
    *   **Period Determination Logic:** The primary logic for determining the "current publication period" (which is typically the quarter preceding the execution date) should reside within the pipeline itself, specifically in the `update_hsmr_config.py` script.
    *   **Payload from Cloud Scheduler (Minimal):** The `workflow_dispatch` event triggered by the cloud scheduler could carry a minimal JSON payload, for example:
        ```json
        {
          "run_type": "scheduled_quarterly_production"
        }
        ```
        This payload can be logged by the GitHub Actions workflow for audit purposes to distinguish scheduled runs from manual runs.
    *   **`update_hsmr_config.py` Responsibility:** The Python script, upon execution, will:
        *   Check if it's a `scheduled_quarterly_production` run (e.g., by inspecting an environment variable set from the `workflow_dispatch` payload, or by default if no specific override parameters are found).
        *   If so, it will execute its standard logic: `get_previous_quarter_dates()` to calculate date parameters based on the current system date of the GitHub Actions runner.
        *   This keeps the date calculation logic centralized and consistent.

2.  **Manual Runs (Triggered directly by `workflow_dispatch` in GitHub Actions):**
    *   **Configurable Inputs in Workflow YAML:** The `workflow_dispatch` trigger in the `hsmr_automation_ci.yml` file should be configured to accept optional inputs that allow users to override the default date calculation. This is essential for reprocessing historical data, testing specific periods, or handling non-standard runs.
        *   **Example `workflow_dispatch` inputs:**
          ```yaml
          on:
            workflow_dispatch:
              inputs:
                target_year:
                  description: 'Target Year for the report (e.g., 2023). If blank, defaults to previous quarter logic.'
                  required: false
                  type: string
                target_quarter:
                  description: 'Target Quarter for the report (1-4). If blank, defaults to previous quarter logic.'
                  required: false
                  type: string
                # Add other potentially overridable parameters, e.g., specific data source flags for testing
          ```
    *   **Adaptation of `update_hsmr_config.py`:**
        *   The Python script must be modified to detect these inputs when the workflow is triggered by `workflow_dispatch`. GitHub Actions makes these inputs available as environment variables (e.g., `INPUT_TARGET_YEAR`, `INPUT_TARGET_QUARTER`).
        *   If these environment variables are present and contain valid year/quarter values, `update_hsmr_config.py` should use them to calculate the date parameters instead of defaulting to the "previous quarter based on current date" logic.
        *   If the inputs are absent, blank, or invalid, the script should fall back to its default behavior (calculating based on the current date).
        *   This provides the necessary flexibility for manual runs while ensuring scheduled runs use the intended automated date logic.
    *   **Logging of Effective Period:** Regardless of how the period is determined (default calculation or manual override), the effective `publication_reference_period` used for the run must be clearly logged at the beginning of the pipeline execution (e.g., by `update_hsmr_config.py` and in the GHA workflow logs).

---

## III. Monitoring of Scheduled Triggers & Runs

**Objective:** Ensure that the initiation and early stages of scheduled pipeline runs are effectively tracked, and that any failures in the triggering mechanism or catastrophic early workflow failures are promptly detected and alerted.

**Conceptual Solutions:**

1.  **Cloud Scheduler Monitoring (For Scheduled Production Runs):**
    *   **Native Cloud Metrics:** Cloud-native schedulers (AWS EventBridge Scheduler, Azure Logic Apps Scheduler) provide built-in metrics regarding their own execution, such as:
        *   Number of successful trigger invocations.
        *   Number of failed trigger invocations (e.g., if the target GitHub API for `workflow_dispatch` was unreachable or returned an error).
    *   **Alerting on Trigger Failures:** Configure alerts within the cloud provider's monitoring system (e.g., AWS CloudWatch Alarms, Azure Monitor Alerts) to notify the operations team if a scheduled trigger fails to successfully invoke the GitHub Actions workflow. This is critical for ensuring that scheduled runs are not missed.

2.  **GitHub Actions Workflow Run Monitoring:**
    *   **Existing Framework:** The monitoring and alerting framework designed for the HSMR pipeline itself (as detailed in the "Robust Monitoring, Alerting & Logging" protocol) will cover the execution of the workflow once it has been successfully triggered. This includes:
        *   Monitoring job statuses (success/failure).
        *   Tracking overall workflow duration.
        *   Alerting on `workflow_run` completion statuses (especially failures).
    *   **Distinguishing Run Types:** It's beneficial if logs and alerts can distinguish between scheduled production runs and manual ad-hoc runs (e.g., by using the `run_type` parameter passed in the `workflow_dispatch` payload or by inspecting `github.event_name`).

3.  **"Heartbeat" or "Expected Run Completion" Check (Advanced - Optional):**
    *   **Concept:** For extremely critical, infrequent processes like a quarterly publication, a secondary, independent monitoring check could be implemented. This check would run on a different schedule (e.g., daily or weekly) and verify that the expected number of quarterly pipeline runs have successfully initiated and/or completed in the recent past (e.g., "Has a successful Q1 production run completed by April 15th?").
    *   **Mechanism:** This could be a simple script querying the GitHub Actions API for workflow run history or checking for the presence of expected output artifacts from successful runs.
    *   **Value:** Acts as a meta-monitor to catch subtle issues like an accidental disabling of the primary cloud scheduler or a recurring early failure in the GitHub Actions workflow that might be missed if primary alerts are misconfigured or overlooked.
    *   **Overhead:** This adds another component to monitor and maintain, so its value should be weighed against the robustness of the primary scheduler and workflow monitoring. For a quarterly process with direct monitoring of the cloud scheduler and the GHA workflow, this might be initially deferred.

---
This conceptual design for automated scheduling and triggering provides a framework for ensuring the HSMR pipeline is executed reliably and flexibly. The specific implementation will involve configuring the chosen cloud scheduling service, adapting the `update_hsmr_config.py` script for parameterization, and setting up appropriate monitoring and alerts for the triggering mechanisms.
---
