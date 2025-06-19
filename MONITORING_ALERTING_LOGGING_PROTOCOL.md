# HSMR Publication Pipeline: Robust Monitoring, Alerting & Logging (Centralized)

## Objective
This document outlines the conceptual design for a comprehensive, centralized monitoring, alerting, and logging strategy for the HSMR (Hospital Standardised Mortality Ratios) automation pipeline. The goal is to establish robust observability into the pipeline's health, performance, and security, enabling proactive issue detection, rapid troubleshooting, and continuous operational improvement.

## Guiding Principles
This protocol is guided by the principles of full observability (if it moves, monitor it), structured and actionable data (logs and metrics), proactive alerting on deviations and failures, and centralized analysis capabilities. It aims to minimize downtime, reduce mean time to resolution (MTTR), and provide insights into pipeline behavior.

---

## I. Centralized Logging System

**Objective:** To aggregate logs from all components of the HSMR automation pipeline and its supporting infrastructure into a single, searchable, and secure location for troubleshooting, auditing, and operational analysis.

**Key Components & Conceptual Solutions:**

1.  **Log Sources - Comprehensive Collection:**
    *   **A. GitHub Actions Workflow Engine:**
        *   Capture detailed logs from each job and step execution, including `stdout`, `stderr`, and any diagnostic output from actions.
    *   **B. Application Scripts (R & Python):**
        *   **R Scripts (`scripts/*.R`):** Implement structured logging. While base R `cat()`, `message()`, `warning()`, `stop()` provide output, using dedicated logging packages (e.g., `logger`, `futile.logger`, `lgr`) configured to output structured formats (ideally JSON) is recommended. Logs must include timestamps (UTC), severity levels (INFO, WARN, ERROR, DEBUG, CRITICAL), script name, function/context, and detailed messages.
        *   **Python Scripts (`update_hsmr_config.py`, `qa_scripts/*.py`, `scripts/archive_and_stage.py`):** Utilize Python's built-in `logging` module, configured to output structured logs (e.g., JSON via custom formatters or libraries like `python-json-logger`). Essential log fields include timestamp, severity, script name, function/module, message, and full stack traces for exceptions.
    *   **C. Compute Infrastructure (VMs, Containers, Orchestration Services):**
        *   **OS-level logs:** (e.g., syslog, journald) from any VMs (like self-hosted GHA runners).
        *   **Container logs:** `stdout`/`stderr` from Docker containers running R/Python scripts. Container orchestration platforms (Kubernetes, ECS, Batch) typically manage these.
        *   **Orchestrator logs:** Logs from services like Kubernetes control plane, AWS Batch job state changes, or other workflow engine logs.
    *   **D. Cloud Services (Platform Logs):**
        *   **Secrets Management (e.g., AWS Secrets Manager, Azure Key Vault):** Audit logs detailing every access attempt (success/failure) to secrets.
        *   **Identity and Access Management (IAM) (e.g., AWS CloudTrail, Azure Activity Log):** Logs for all IAM user activity, role assumptions, and policy changes. Critical for security monitoring.
        *   **Storage Services (e.g., AWS S3, Azure Blob Storage):** Server access logs detailing all object-level requests (GET, PUT, DELETE, etc.), including source IP, user/role, and status.
        *   **Database Access (Source Systems & Operational DBs):** Query logs, connection logs, and security audit logs from the source databases being accessed by the pipeline (if configurable and permissible). Any operational databases used by the pipeline itself should also have comprehensive logging enabled.
        *   **Network Infrastructure:** VPC Flow Logs (AWS), NSG Flow Logs (Azure), or equivalent for capturing IP traffic information within the virtual network. Useful for security analysis and troubleshooting network connectivity.

2.  **Log Format & Structure:**
    *   **Standardized Format (JSON Recommended):** Enforce JSON as the standard log format for all application-generated logs (R and Python). This allows for easy parsing, indexing, and searching in centralized logging platforms.
    *   **Essential Log Fields (Minimum Set):**
        *   `timestamp`: ISO 8601 format in UTC (e.g., `YYYY-MM-DDTHH:MM:SS.sssZ`).
        *   `log_level`: Standard severity levels (e.g., `INFO`, `WARNING`, `ERROR`, `DEBUG`, `CRITICAL`).
        *   `service_name` / `application_name`: Identifier for the component generating the log (e.g., `HSMR-Pipeline`, `create_smr_data.R`, `GHA-Job-process_and_analyze_data`).
        *   `pipeline_run_id` / `correlation_id`: A unique identifier that links all log entries for a single execution of the HSMR pipeline from start to finish. This can be the GitHub Actions `github.run_id`.
        *   `function_name` / `module_name` / `script_step`: Specific location within the code generating the log.
        *   `message`: The human-readable log message.
        *   `error_details` (for errors): Full error message, stack trace, exception type.
        *   `contextual_data` (optional, as appropriate): Key-value pairs providing relevant context, e.g., `filename_processed`, `record_id`, `config_parameter_value`. Avoid logging overly verbose or sensitive data directly if not necessary. Hashes of data files can be logged here for audit.

3.  **Log Collection & Aggregation Strategy:**
    *   **GitHub Actions:** Logs are natively collected by the GitHub Actions platform. For long-term retention, advanced analysis, and correlation with other logs, these should be exported (e.g., via GitHub API calls, or using dedicated marketplace Actions like `Logtail / Better Stack` or custom scripts) to the chosen centralized logging platform.
    *   **Application Logs (Running in Cloud Compute):**
        *   **Containerized Applications:** Configure containers to log to `stdout`/`stderr`. The container orchestration service (Kubernetes, ECS, AWS Batch with Fargate/EC2) will then typically have built-in integrations or configurable agents (e.g., Fluentd, Fluent Bit as sidecars or daemonsets) to forward these logs to the centralized platform.
        *   **VM-based Applications / Self-Hosted Runners:** Install and configure a logging agent (e.g., AWS CloudWatch Agent, Azure Monitor Agent, Fluentd, Fluent Bit) on the VMs. The agent will collect logs from specified files (e.g., application log files, system logs) or syslog and forward them.
    *   **Cloud Service Logs:** Configure each respective cloud service to export its logs directly or indirectly (e.g., via an intermediary S3 bucket) to the centralized logging platform. Most cloud providers offer native integrations for this (e.g., CloudTrail to CloudWatch Logs, Azure service logs to Azure Monitor).

4.  **Centralized Logging Platform Selection:**
    *   **Cloud-Native Options:**
        *   **AWS:** Amazon CloudWatch Logs (for ingestion and basic searching/alarming) often paired with Amazon OpenSearch Service (for advanced Kibana-based analytics) or Amazon Athena (for querying logs stored in S3).
        *   **Azure:** Azure Monitor Logs (powered by Log Analytics workspaces) with Azure Dashboards or integration with tools like Power BI for visualization.
        *   **Google Cloud Platform (GCP):** Google Cloud Logging with Cloud Monitoring and Looker or Google Data Studio for visualization.
    *   **Open Source / Third-Party Options:**
        *   **ELK Stack (Elasticsearch, Logstash, Kibana):** Powerful, flexible, but requires self-management or using a managed ELK service.
        *   **Splunk:** Feature-rich, but can be expensive.
        *   **Grafana Loki:** Designed for log aggregation, often used with Prometheus for metrics.
        *   **Managed SaaS Logging Services (e.g., Datadog, Logz.io, Sematext, Logtail):** Offer comprehensive logging solutions with varying features and pricing.
    *   **Initial Recommendation:** For simplicity and strong integration with other cloud services, starting with the **native cloud provider's logging solution** (e.g., CloudWatch Logs if on AWS, Azure Monitor Logs if on Azure) is often the most efficient approach. If requirements grow beyond their capabilities or if a multi-cloud solution is needed, then evaluate dedicated platforms like ELK or SaaS providers.

5.  **Log Retention & Archiving Policies:**
    *   **Active Storage:** Define a retention period for logs to be kept in actively searchable, "hot" storage within the logging platform (e.g., 30-90 days for operational troubleshooting).
    *   **Archival Storage:** After the active period, logs should be automatically archived to cheaper, long-term cold storage (e.g., AWS S3 Glacier, Azure Archive Blob Storage).
    *   **Compliance:** Retention periods must align with compliance requirements (e.g., HIPAA, GDPR, organizational data retention policies), which could be several years.

6.  **Security & Access Control for Logs:**
    *   **Encryption:** Ensure logs are encrypted both in transit (to the logging platform) and at rest (within the platform and in archival storage).
    *   **Access Control:** Implement strict, role-based access control (RBAC) for accessing logs. Developers and operators might need access to recent application logs for troubleshooting specific pipeline runs. Security and audit teams may require broader, potentially read-only, access for investigation and compliance reviews. Sensitive information within logs should be masked if possible or access further restricted.

---

## II. Performance Monitoring & Alerting

**Objective:** To proactively track the performance characteristics and operational health of the HSMR pipeline, identify bottlenecks or anomalous behavior, and alert relevant personnel when issues arise or predefined thresholds are breached.

**Key Components & Conceptual Solutions:**

1.  **Metrics to Monitor:**
    *   **A. Pipeline Execution Metrics (sourced from GitHub Actions API, or a dedicated workflow orchestrator):**
        *   Job/Step Success/Failure Status & Counts.
        *   Job/Step Execution Durations (min, max, average, 95th percentile).
        *   Overall Pipeline Run Duration (end-to-end).
        *   Frequency of Pipeline Runs (scheduled vs. actual).
        *   Size of input, intermediate, and output artifacts.
    *   **B. Data Quality Metrics (sourced from QA script outputs - Phase 4):**
        *   Number of schema validation failures per run/file.
        *   Number and types of data rule violations per run/file.
        *   Number of anomalies flagged by the (conceptual) AI detection module.
        *   Trends in these metrics over time.
    *   **C. Compute Resource Metrics (for underlying VMs, Containers, Batch Job infrastructure):**
        *   CPU Utilization (average, maximum, per instance/container).
        *   Memory Utilization (average, maximum, per instance/container).
        *   Disk Space Usage & I/O throughput/latency (if applicable, for ephemeral or persistent storage).
        *   Network I/O (bytes in/out, packets).
    *   **D. R/Python Script Performance (Custom Application Metrics):**
        *   Instrument critical R and Python scripts to emit custom metrics. This can be done by:
            *   Writing metrics to structured log output (e.g., JSON) which can then be parsed by the logging platform to extract metrics.
            *   Using client libraries to send metrics directly to a monitoring system (e.g., Prometheus client libraries, CloudWatch Embedded Metric Format).
        *   **Examples:** Time taken for specific critical functions (e.g., SMR model fitting, large data joins in R, complex validation logic in Python), number of records processed per script/stage, number of files generated.
    *   **E. Cloud Service-Specific Metrics (native metrics from cloud provider):**
        *   **Secrets Manager:** API call latency, error rates, audit logs of access.
        *   **Storage (S3/Blob):** Latency for GET/PUT requests, error rates, bucket/container size.
        *   **Database (Source Systems, if monitored):** Query latency for HSMR extraction queries, database connection error rates (as observed from the pipeline side).
        *   **NAT Gateway/Firewall:** Active connections, data processed, dropped packets.

2.  **Monitoring Tools Selection:**
    *   **Cloud-Native Platforms:**
        *   **AWS CloudWatch Metrics & Alarms:** Collects metrics from AWS services and custom metrics. Can trigger alarms.
        *   **Azure Monitor Metrics & Alerts:** Similar capabilities for Azure services.
        *   **Google Cloud Monitoring & Alerting:** For GCP services.
    *   **Open Source / Third-Party Platforms:**
        *   **Prometheus & Grafana:** Prometheus for time-series metrics collection and alerting (Alertmanager); Grafana for powerful dashboarding and visualization. This is a very popular and flexible combination.
        *   **Datadog, Dynatrace, New Relic:** Comprehensive SaaS APM and infrastructure monitoring solutions. Offer broad integrations and advanced features but come with associated costs.
    *   **GitHub Actions:** Provides basic run duration and status. For more detailed metrics on GHA itself (e.g., runner utilization if self-hosted), external monitoring or exporter tools might be needed.
    *   **Initial Recommendation:** Leverage **cloud-native monitoring tools** (CloudWatch, Azure Monitor) for infrastructure and managed service metrics due to ease of integration. For application-level custom metrics and advanced dashboarding/alerting, **Prometheus and Grafana** offer a powerful and widely adopted open-source solution. If the organization already uses a specific third-party tool (like Datadog), align with that.

3.  **Dashboards for Visualization:**
    *   **Purpose:** Create centralized, role-specific dashboards to visualize key metrics, log trends, and the overall health/performance of the HSMR pipeline.
    *   **Key Dashboards (Examples):**
        *   **Pipeline Health Overview:** Status of recent pipeline runs (success/failure), overall duration trends, number of critical alerts.
        *   **Performance Deep Dive:** Detailed execution times for each job and critical script, resource utilization trends (CPU, memory) for compute components.
        *   **Data Quality Dashboard:** Trends in schema validation errors, data rule violations, and AI-flagged anomalies over time.
        *   **Resource Utilization Dashboard:** Long-term trends for CPU, memory, disk, and network usage to inform capacity planning.
    *   **Tools:** Grafana (highly flexible), Kibana (for ELK-based logs/metrics), AWS CloudWatch Dashboards, Azure Dashboards, Google Cloud Dashboards, or dashboards within third-party monitoring tools.

4.  **Alerting Rules & Notification Channels:**
    *   **A. Critical Alerts (Requiring Immediate Action/Investigation):**
        *   Complete pipeline run failure (any critical job/step fails to complete successfully).
        *   Critical data validation errors (e.g., schema validation failure for a key output dataset that would prevent downstream processing).
        *   Sustained resource exhaustion (e.g., CPU or Memory utilization > 95% for X minutes, critical disk space < Y% remaining).
        *   Security-related alerts (e.g., from AWS GuardDuty, Azure Security Center, or critical IAM policy change alerts).
        *   Failure to connect to critical external systems (e.g., source databases, secrets manager).
        *   Significant anomolies in output data that pass basic validation but are flagged as statistically improbable by advanced checks.
    *   **B. Warning Alerts (Requiring Investigation, but not necessarily immediate pipeline halt):**
        *   Job/step execution duration exceeding predefined thresholds (e.g., > 1.5x the historical average for that step).
        *   An increase in non-critical data rule violations or data quality warnings.
        *   A notable number of anomalies flagged by the (conceptual) AI detection module that might warrant earlier human review.
        *   Resource utilization approaching warning thresholds (e.g., CPU > 80%, Disk > 75%).
        *   Increased error rates for API calls to dependent services.
    *   **Notification Channels:** Route alerts based on severity and target audience:
        *   **High Severity / Critical:** PagerDuty, Opsgenie, SMS notifications to on-call personnel, dedicated critical alert Slack/Teams channel.
        *   **Medium / Warning Severity:** Email to relevant teams, standard Slack/Teams channel.
        *   **Low Severity / Info (e.g., successful completion):** Optional email digest, informational Slack/Teams channel.
    *   **Actionable Alerts:** Alerts must be "actionable." They should include:
        *   Clear description of the issue and its potential impact.
        *   Pipeline Run ID, Job/Step Name, specific component affected.
        *   Relevant metric values that triggered the alert.
        *   Timestamp of occurrence.
        *   Direct links to relevant dashboards or log queries for deeper investigation.
        *   References to runbooks or SOPs for common issues.

---
This comprehensive monitoring, alerting, and logging strategy is vital for maintaining a healthy, reliable, and performant HSMR automation pipeline in a production environment. It provides the necessary feedback loops for operational management and continuous improvement.
---
