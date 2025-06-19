# HSMR Publication Pipeline: Production Environment Setup & Management Protocol

## Objective
This document outlines the conceptual design for a secure, scalable, resilient, and observable production environment for hosting and executing the automated HSMR (Hospital Standardised Mortality Ratios) publication pipeline.

## Guiding Principles
The production environment design adheres to principles of security by design, infrastructure as code, least privilege, defense-in-depth, high availability, scalability, and comprehensive observability. It aims to ensure reliable and timely execution of the HSMR publication process.

---

## I. Dedicated Production Infrastructure

**Objective:** Define a secure, scalable, and resilient infrastructure for hosting and executing the HSMR automation pipeline in a production setting.

**Key Considerations & Conceptual Solutions:**

1.  **Environment Segregation:**
    *   **Recommendation:** Maintain a minimum of three distinct, isolated environments:
        *   **`Development (Dev)`:**
            *   **Purpose:** For developers to build, experiment, and test new features or changes to the pipeline.
            *   **Data:** Primarily synthetic or fully anonymized test data. No access to production sensitive data.
            *   **Infrastructure:** Can be local machines, shared cloud development sandboxes, or ephemeral cloud resources.
        *   **`Staging (UAT/Pre-Production)`:**
            *   **Purpose:** A production-like environment for end-to-end testing of release candidates. Used for User Acceptance Testing (UAT) and final validation before deployment to production.
            *   **Data:** Should use high-quality, production-like data. This could be recently pseudonymized production data (if processes allow and it's deemed necessary for accurate testing) or carefully curated, structurally identical synthetic data that covers edge cases. Direct use of live production sensitive data is discouraged.
            *   **Infrastructure:** Should mirror the production environment as closely as possible in terms of architecture, software versions, and configurations.
        *   **`Production (Prod)`:**
            *   **Purpose:** The live environment where the actual HSMR publication pipeline executes with real, sensitive patient data.
            *   **Access:** Highly restricted, controlled, and audited.
    *   **Network Isolation:** Each environment (Dev, Staging, Prod) must be strictly network-isolated from the others (e.g., deployed in separate Virtual Private Clouds/VPCs in AWS, Virtual Networks/VNets in Azure, or equivalent logical network boundaries). Communication between environments, if ever necessary, must be via secure, controlled, and audited channels.

2.  **Compute Platform Selection:**
    *   **Option A: Virtual Machines (VMs) (e.g., AWS EC2, Azure Virtual Machines, Google Compute Engine):**
        *   **Pros:** Offers full control over the operating system and underlying environment. May be simpler for initial setup if the team is more familiar with traditional server management.
        *   **Cons:** Requires more manual effort for OS patching, configuration management, and security hardening. Lower deployment density and slower scaling compared to containers.
        *   **Suitability:** Could be considered if pipeline components are monolithic, have complex OS-level dependencies not easily containerized, or if specific legacy software is required.
    *   **Option B: Containerization (e.g., Docker) & Orchestration (e.g., Kubernetes - AWS EKS, Azure AKS, Google GKE; or simpler services like AWS ECS, Azure Container Instances, AWS Fargate):**
        *   **Pros:** Promotes consistency between Dev, Staging, and Prod environments. Simplifies dependency management ("it works on my machine" problem is reduced). Enables efficient resource utilization, rapid scaling, and resilience. Aligns very well with CI/CD practices and microservice architectures (if pipeline components are decomposed).
        *   **Cons:** Steeper learning curve, especially for full Kubernetes orchestration. Requires effort to Dockerize R and Python scripts and manage container images.
        *   **Primary Recommendation:** **Strongly recommended for a modern, scalable, and maintainable deployment.** The HSMR pipeline, with its distinct script components (Python for orchestration/validation, R for analysis), is well-suited for containerization. Each phase or significant script could potentially be packaged as a separate container image.
    *   **Option C: Managed Services / Serverless Compute (e.g., AWS Batch, Azure Batch for R/Python jobs; AWS Step Functions / Azure Logic Apps for orchestration; AWS Lambda / Azure Functions for smaller, event-driven Python scripts):**
        *   **Pros:** Significantly reduces infrastructure management overhead (server patching, OS maintenance handled by the cloud provider). Offers pay-per-use cost models and can provide automatic scaling for certain services.
        *   **Cons:** Can lead to increased vendor lock-in. Serverless functions (Lambda, Azure Functions) might have limitations on execution duration, memory, or specific software versions/libraries that could be restrictive for long-running R analytical scripts. Batch services are generally more flexible for such workloads.
        *   **Suitability:** Could be ideal for orchestrating the overall pipeline (Step Functions, Logic Apps) and for running specific, containerized batch processing tasks (R scripts via AWS/Azure Batch using custom Docker images) without managing server clusters directly.

3.  **Infrastructure as Code (IaC):**
    *   **Universal Recommendation:** All production infrastructure components (VMs, container configurations, orchestration settings, networks, IAM roles, storage buckets, etc.) must be defined and managed using IaC tools. Examples:
        *   Terraform (cloud-agnostic)
        *   AWS CloudFormation
        *   Azure Resource Manager (ARM) templates or Bicep
        *   Pulumi
    *   **Benefits:**
        *   **Reproducibility:** Ensures environments can be recreated consistently and reliably.
        *   **Version Control:** Infrastructure definitions are stored in Git, versioned, and subject to review and CI/CD processes.
        *   **Automation:** Automated provisioning, updates, and de-provisioning of infrastructure.
        *   **Reduced Manual Error:** Minimizes risks associated with manual configuration changes.
        *   **Disaster Recovery:** Facilitates quicker and more reliable re-creation of infrastructure in a DR scenario.

4.  **Security Configuration (Compute Layer):**
    *   **OS/Container Hardening:** Apply security best practices and hardening guides (e.g., CIS benchmarks) to all compute instances or base container images. Use minimal OS distributions where possible. Disable unnecessary services and ports.
    *   **Network Security (Micro-segmentation):** Implement strict firewall rules (Security Groups in AWS, Network Security Groups/NSGs in Azure) to restrict network traffic to only what is absolutely necessary for each component to function (e.g., only allow traffic from the secrets manager to compute instances on the required port for credential retrieval). Default to deny-all.
    *   **Internet Access:** Compute instances or containers handling sensitive data should generally not have direct outbound public internet access. If necessary (e.g., to download packages from official repositories during build time, not runtime), it should be via a NAT Gateway or proxy, with traffic filtered and logged. Inbound internet access should be prohibited.
    *   **Vulnerability Management:** Implement a continuous vulnerability management process:
        *   Regularly scan OS images, container images, and all software dependencies for known vulnerabilities.
        *   Apply security patches and updates promptly based on risk assessment.

5.  **Scalability & Resilience:**
    *   **Scalability:** Design the compute platform to accommodate potential increases in data volume or processing complexity.
        *   **VMs:** Use auto-scaling groups.
        *   **Containers:** Kubernetes Horizontal Pod Autoscaler (HPA) or equivalent scaling mechanisms in ECS/Fargate.
        *   **Managed/Serverless Services:** Leverage the inherent scalability of services like AWS Batch or Azure Batch, configuring job queues and compute environments appropriately.
    *   **Resilience & High Availability:**
        *   Deploy critical components across multiple Availability Zones (AZs) within a cloud region to protect against single AZ failures.
        *   Design the pipeline and its components for fault tolerance (e.g., if an R script runner fails, an orchestrator should be able to retry the task or assign it to another runner if applicable).
        *   Ensure state management (if any) is handled by durable services.

---

## II. Robust Monitoring, Alerting & Logging (Centralized)

**Objective:** Establish comprehensive observability into the HSMR pipeline's operational health, performance characteristics, and security posture, enabling proactive issue detection, rapid troubleshooting, and informed decision-making.

**Key Considerations & Conceptual Solutions:**

1.  **Centralized Logging:**
    *   **Mechanism:** Aggregate logs from all components of the HSMR pipeline into a centralized logging solution. This includes:
        *   GitHub Actions workflow execution logs.
        *   Application logs from R scripts (stdout, stderr, custom log files).
        *   Application logs from Python scripts (using the `logging` module).
        *   Infrastructure logs (VM system logs, container logs, load balancer logs if any).
        *   Database access logs (from the source data systems, if available).
        *   Storage access logs (for archived data).
    *   **Recommended Tools:** ELK Stack (Elasticsearch, Logstash, Kibana), Splunk, AWS CloudWatch Logs, Azure Monitor Logs, Datadog, Grafana Loki.
    *   **Structured Logging:** Enforce structured logging formats (preferably JSON) for all application-generated logs, as designed in the QA Framework (QA.2). This facilitates easier searching, filtering, correlation, and analysis.
    *   **Key Log Content:** Each log entry should, at a minimum, include:
        *   Accurate Timestamp (UTC).
        *   Severity Level (e.g., INFO, WARNING, ERROR, CRITICAL, DEBUG).
        *   Source Application/Script Name/Component ID.
        *   Function Name or specific operation being performed (if applicable).
        *   Correlation ID (a unique ID to trace a single HSMR publication run across all its logs and components).
        *   Clear, human-readable message.
        *   Relevant contextual data (e.g., filename being processed, configuration parameters in use, record identifiers if appropriate and safe to log).
        *   For errors: Detailed error messages, stack traces.
        *   For audit purposes: Hashes of input/output data files where relevant.

2.  **Metrics Collection (Monitoring):**
    *   **Pipeline Execution Metrics:**
        *   Status of each pipeline job and individual script/step (success, failure, duration).
        *   Overall pipeline run duration (end-to-end).
        *   Size of artifacts generated/transferred.
        *   Data validation success/failure rates (from Phase 4 QA scripts).
        *   Number of data quality issues or anomalies flagged.
    *   **Resource Metrics (for VMs, Containers, Managed Services):**
        *   CPU utilization, memory usage, disk I/O rates and capacity, network traffic.
    *   **Application-Specific Metrics (instrumented within R/Python scripts):**
        *   Number of records read from source / written to destination by key scripts.
        *   Time taken for specific critical data processing stages (e.g., SMR model fitting, data wrangling).
        *   Queue lengths if using message queues or job queues (e.g., in AWS/Azure Batch).
    *   **Recommended Tools:** Prometheus with Grafana for visualization, cloud provider native monitoring tools (AWS CloudWatch Metrics, Azure Monitor Metrics), Datadog APM, or other application performance monitoring (APM) solutions.

3.  **Alerting Strategy:**
    *   **Alert Triggers:** Configure automated alerts based on:
        *   **Pipeline Failures:** Any critical job or step in the HSMR pipeline fails.
        *   **Critical Log Events:** Occurrence of ERROR or CRITICAL severity log messages.
        *   **Metric Threshold Breaches:** Key performance indicators (KPIs) or resource metrics cross predefined thresholds (e.g., pipeline execution time exceeds expected baseline by X%, CPU utilization remains > Y% for an extended period, available disk space drops below Z%).
        *   **Data Validation Failures:** Critical data validation rules fail (e.g., input file schema mismatch, critical range check failure).
        *   **Security Events:** Detection of potential security incidents (e.g., unauthorized access attempts to sensitive data stores or services, if such monitoring is in place).
    *   **Notification Channels:** Route alerts to appropriate teams/individuals via:
        *   Email distribution lists.
        *   Team collaboration platforms (e.g., Slack, Microsoft Teams).
        *   Dedicated incident management tools (e.g., PagerDuty, Opsgenie).
        *   SMS (for highly critical alerts requiring immediate attention).
    *   **Actionable Alerts:** Alerts must provide sufficient context (e.g., what failed, when, relevant log snippets or links to dashboards) to enable recipients to start troubleshooting effectively. Define clear runbooks or standard operating procedures (SOPs) for responding to common alerts.

4.  **Dashboards & Visualization:**
    *   **Purpose:** Create centralized dashboards to visualize key metrics, log trends, and the overall health and performance of the HSMR pipeline over time.
    *   **Content Examples:**
        *   Pipeline execution status history (success/failure rates).
        *   Duration trends for key jobs and the overall pipeline.
        *   Resource utilization graphs.
        *   Data quality metrics trends (e.g., number of validation errors per run).
        *   Error rate trends.
    *   **Recommended Tools:** Grafana, Kibana (for ELK), AWS CloudWatch Dashboards, Azure Dashboards, Datadog Dashboards.

5.  **Security Monitoring (Specific to Production Environment):**
    *   **Integration with SIEM:** If an organizational Security Information and Event Management (SIEM) system is in place, ensure logs from the HSMR production environment (especially security-relevant logs like access attempts, IAM changes, critical errors) are ingested into the SIEM for correlation and analysis by the security operations team.
    *   **Regular Security Audits:** Conduct periodic security audits and penetration tests (if appropriate and scoped correctly) of the production environment to proactively identify and address potential vulnerabilities.
    *   **Configuration Drift Monitoring:** Implement mechanisms to detect and alert on any unauthorized or unexpected changes to production infrastructure configurations (IaC helps prevent this, but detective controls are also valuable).

---
This Production Environment Setup and Management Protocol provides a robust framework. The specific choice of technologies (e.g., VM vs. Containers vs. Serverless, specific monitoring tools) will depend on organizational standards, existing infrastructure, team expertise, and cost considerations. However, the principles outlined should guide the implementation to ensure a secure, reliable, and maintainable production HSMR pipeline.
---
