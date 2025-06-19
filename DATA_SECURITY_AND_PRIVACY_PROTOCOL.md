# HSMR Publication Pipeline: Data Security & Privacy Protocol

## Objective
This document outlines the conceptual design for a robust Data Security and Privacy Protocol for the automated HSMR (Hospital Standardised Mortality Ratios) publication pipeline. It covers the secure ingestion of sensitive health data and its secure long-term storage and archiving, ensuring compliance and protecting data integrity and confidentiality throughout its lifecycle.

## Guiding Principles
This protocol adheres to principles of data minimization, least privilege, defense-in-depth, encryption everywhere (in transit and at rest), and comprehensive auditability. It aims to meet or exceed relevant regulatory requirements (e.g., HIPAA, GDPR, or specific national/local health data regulations).

---

## I. Secure Data Ingestion

**Objective:** Define a robust and secure process for extracting sensitive health data from production source systems into the HSMR automation pipeline.

**Key Considerations & Conceptual Solutions:**

1.  **Connection Method & Encryption:**
    *   **Primary Recommendation (API-based):**
        *   Utilize secure, audited APIs exposed by production source systems for data extraction.
        *   **Benefits:** Abstracts database-level complexities, often includes built-in logging, rate limiting, and standardized authentication/authorization. Data transfer must use HTTPS (TLS).
    *   **Alternative (Direct SQL Connection):**
        *   If direct SQL access is unavoidable, connections must be encrypted using industry-standard protocols (e.g., TLS/SSL for the database connection).
        *   Database accounts used by the pipeline must be dedicated, read-only, and granted the minimum necessary privileges (e.g., SELECT on specific tables/views).
    *   **Network Security:**
        *   All connections from the automation environment (e.g., GitHub Actions runners, dedicated ETL servers) to production data sources must occur over a secure, private network. This can be achieved via:
            *   Virtual Private Network (VPN).
            *   Dedicated private network connections (e.g., AWS Direct Connect, Azure ExpressRoute, or equivalent cloud provider solutions).
            *   Ensuring source systems are not directly exposed to the public internet.

2.  **Credentials Management:**
    *   **Mechanism:** Employ a dedicated secrets management service. Examples:
        *   HashiCorp Vault
        *   AWS Secrets Manager
        *   Azure Key Vault
        *   GitHub Actions Encrypted Secrets (for credentials used directly within GHA workflows).
    *   **Access Protocol:** The HSMR automation pipeline (specifically the data extraction script, e.g., `scripts/extract_database_data.R` or its Python equivalent) retrieves credentials programmatically and dynamically at runtime.
    *   **NO Hardcoding:** Credentials (passwords, API keys, tokens, connection strings with sensitive parts) must **never** be hardcoded in scripts, configuration files (like `hsmr_config.json`), or version control.
    *   **Rotation Policy:** Implement and enforce regular, automated rotation of all database credentials and API keys used by the pipeline. The secrets management system should facilitate this.

3.  **Data Minimization & Anonymization/Pseudonymization:**
    *   **Principle of Data Minimization:** Only extract the specific data fields absolutely necessary for HSMR calculations and any required linkage or demographic stratification. Avoid extracting extraneous sensitive information. This is a "Know Your Core" application.
    *   **Anonymization/Pseudonymization Strategy (Prioritize at Source):**
        *   **Ideal Scenario:** Perform anonymization (removal of direct identifiers) or pseudonymization (replacement of direct identifiers with a reversible or irreversible token) *before* the data leaves the source system's security boundary or as close to the source as feasible. This significantly reduces the risk associated with data in transit and in the pipeline's initial processing stages.
        *   **Considerations:** The feasibility depends on source system capabilities and the specific requirements of HSMR calculation (e.g., if linkage via a pseudonymized ID is necessary across datasets).
        *   **Pipeline-Level (If Necessary):** If de-identification cannot occur at the source, it must be the very first step after data ingestion into a secure, isolated processing environment within the HSMR pipeline. This processing should occur before the data is widely used or stored, even in raw form.
    *   **Governance:** The level of de-identification must be appropriate for the data's use and comply with all relevant privacy regulations and ethical guidelines.

4.  **Secure Transport & Staging:**
    *   **Encryption in Transit:** All data movement must be over encrypted channels (HTTPS, TLS/SSL for DB connections, SFTP if applicable).
    *   **Initial Staging Area (If Required):** If raw, sensitive data needs temporary staging after extraction (before full processing or de-identification), this staging area must be:
        *   Encrypted at rest (e.g., encrypted disk on a runner, encrypted S3 bucket with strict lifecycle policies).
        *   Subject to strict, minimal access controls.
        *   Designed for minimal data residency (data processed and moved/deleted as quickly as possible).
    *   **GitHub Actions Considerations:**
        *   If using GitHub-hosted runners, understand that the runner environment is temporary. Data written to the runner filesystem (e.g., `data/raw/`) is isolated per job run.
        *   Artifacts created by GitHub Actions should be handled carefully. If they contain sensitive data, ensure retention policies are appropriate. Consider encrypting artifacts before upload if they are stored by GitHub for extended periods and contain highly sensitive information (though this adds complexity). Self-hosted runners allow for more control over disk encryption and logging at the runner level.

5.  **Auditing & Logging for Ingestion:**
    *   **Pipeline Logs:** Log all data extraction attempts (both success and failure), including the source system, timestamp, volume of data requested/retrieved, and user/service principal performing the extraction. These logs must be sent to a centralized, secure logging system.
    *   **Source System Auditing:** Ensure that the source data systems have comprehensive auditing enabled and that access attempts by the HSMR pipeline's credentials are logged on the source side. This provides an independent audit trail.

---

## II. Secure Data Storage & Archiving

**Objective:** Ensure the secure, compliant, and integrity-preserving long-term storage of sensitive HSMR-related data, including historical raw extracts (for potential reprocessing) and processed analytical datasets (for audit and longitudinal analysis).

**Key Considerations & Conceptual Solutions:**

1.  **Storage Solution Selection:**
    *   **Primary Recommendation:** Utilize secure, managed, and scalable cloud storage services. Examples:
        *   AWS S3 (Simple Storage Service)
        *   Azure Blob Storage
        *   Google Cloud Storage
    *   **Benefits:** These services typically offer high durability, availability, scalability, and a rich set of built-in security features (encryption, access control, logging).
    *   **Bucket/Container Configuration Best Practices:**
        *   **Block Public Access:** Enforce "block all public access" at the bucket/container level unless explicitly and safely justified for a specific, non-sensitive dataset.
        *   **Versioning:** Enable object versioning to protect against accidental deletions or overwrites and to maintain an audit history of changes.
        *   **Lifecycle Policies:** Implement data lifecycle policies to automatically:
            *   Transition older data to more cost-effective archival storage tiers (e.g., AWS S3 Glacier, Azure Archive Storage).
            *   Enforce data retention schedules (e.g., automate deletion of data after its mandated retention period expires).

2.  **Encryption at Rest:**
    *   **Mandatory Requirement:** All HSMR-related data stored at rest, regardless of its stage (raw, processed, archived), must be encrypted.
    *   **Key Management Options:**
        *   **Provider-Managed Keys (Default):** Use server-side encryption with provider-managed keys (e.g., SSE-S3 in AWS, default service-side encryption in Azure Blob). This is the simplest to implement.
        *   **Customer-Managed Keys (CMK):** For enhanced control and compliance requirements, use customer-managed keys via a key management service (e.g., AWS KMS, Azure Key Vault). This allows for centralized management and auditing of key usage.

3.  **Access Control (Identity and Access Management - IAM):**
    *   **Principle of Least Privilege:** Implement granular IAM policies to ensure that users, roles, and service principals (e.g., the HSMR pipeline's automation components) have only the minimum necessary permissions required to perform their tasks.
        *   Example: The archiving script (`scripts/archive_and_stage.py`) might have write access to a specific archive path, while a data reprocessing job might only have read access to historical raw data.
    *   **Role-Based Access Control (RBAC):** Define roles based on job functions (e.g., DataPipelineExecutor, DataAuditor, ArchiveManager).
    *   **No Routine Human Access to Sensitive Archives:** Direct human access to archived sensitive raw or processed data should be highly restricted and logged. Access should typically be granted only via break-glass procedures or under specific, time-bound, and approved change management requests for defined purposes (e.g., critical data audits, authorized reprocessing scenarios).

4.  **Data Retention Policies:**
    *   **Formal Definition:** Establish and document clear data retention policies based on:
        *   Legal and regulatory mandates (e.g., specific health data laws).
        *   Organizational policies and data governance standards.
        *   Analytical or research value of historical data.
    *   **Automated Enforcement:** Leverage storage service lifecycle policies (see point 1c) to automate the enforcement of these retention schedules (e.g., transition to archive, then delete).

5.  **Auditability of Storage Access:**
    *   **Access Logging:** Enable detailed server access logging for all storage buckets/containers. All operations (e.g., GET, PUT, LIST, DELETE) on data objects should be logged.
    *   **Log Centralization:** Forward these storage access logs to the centralized, secure logging system for monitoring, alerting on suspicious activity, and long-term audit.

6.  **Integrity of Archived Data:**
    *   **Store Checksums:** Store strong cryptographic hashes (e.g., SHA256) alongside the archived data files. This can be done by:
        *   Storing a separate `.sha256` sidecar file for each data file.
        *   Including hashes as object metadata if the storage service supports it.
        *   Maintaining a separate, versioned manifest file within the archive that lists all files and their corresponding hashes. The `archive_manifest.json` (conceptually created by `archive_and_stage.py`) serves this purpose.
    *   **Periodic Integrity Validation (Optional but Recommended for Critical Archives):** For very critical, long-term archives, consider implementing a periodic process to:
        *   Retrieve a sample of archived files (or all files if feasible).
        *   Recalculate their hashes.
        *   Compare with the stored hashes to detect any silent data corruption or tampering.

7.  **Backup & Disaster Recovery (DR):**
    *   **Cloud Provider Durability:** Standard cloud storage services (like S3, Azure Blob) are designed for high durability by automatically replicating data across multiple physical devices and availability zones within a region.
    *   **Cross-Region Replication (for enhanced DR):** If business continuity and disaster recovery requirements are stringent (e.g., recovery needed even in the event of a full regional outage), configure cross-region replication for critical archived data to a secondary, geographically distant region. This incurs additional cost but provides a higher level of resilience.

---
This Data Security and Privacy Protocol provides a conceptual framework. Specific technology choices, policy details, and implementation steps must be further refined based on the actual production environment, available resources, organizational policies, and applicable regulatory landscape for the HSMR data.
---
