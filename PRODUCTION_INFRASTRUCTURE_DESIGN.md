# HSMR Publication Pipeline: Dedicated Production Infrastructure (Cloud-Based Conceptualization)

## Objective
This document outlines the conceptual design for a dedicated, secure, scalable, and resilient cloud-based production infrastructure for hosting and executing the automated HSMR (Hospital Standardised Mortality Ratios) publication pipeline. It covers cloud provider selection, compute and storage resource definition, and an Infrastructure as Code (IaC) strategy.

## Guiding Principles
The infrastructure design prioritizes security, compliance with health data regulations, operational efficiency, scalability to handle data growth, resilience for high availability, and cost-effectiveness. It aims to leverage cloud-native capabilities where appropriate to reduce management overhead.

---

## I. Cloud Provider Selection & Justification

**Objective:** To select a suitable cloud provider for hosting the HSMR production pipeline, aligning with security, compliance, operational, and cost requirements.

**Key Selection Criteria:**

1.  **Compliance & Certifications:**
    *   **Criticality:** Paramount due to the handling of sensitive health data.
    *   **Considerations:** The provider must offer a comprehensive suite of services that are independently verified to be compliant with relevant regulations (e.g., HIPAA in the US, GDPR in Europe, specific UK/Scottish health data protection acts like DPA 2018, and NHS Digital Technology Assessment Criteria - DTAC if applicable). Look for certifications such as ISO 27001, ISO 27017, ISO 27018, SOC 2 Type II, and potentially HITRUST or other health-specific attestations.
    *   **Business Associate Agreement (BAA):** A formal BAA (or equivalent Data Processing Addendum for GDPR) with the cloud provider will be mandatory if Protected Health Information (PHI) or equivalent sensitive personal data is processed or stored on their services.

2.  **Security Services & Features:**
    *   **Considerations:** Availability and maturity of native security services, including:
        *   **Identity and Access Management (IAM):** Granular control over user and service identities and their permissions.
        *   **Key Management Services (KMS):** For creating and managing encryption keys (both provider-managed and customer-managed keys - CMK).
        *   **Network Security:** Robust Virtual Private Cloud (VPC/VNet) capabilities, firewalls (Security Groups, NSGs, WAFs), private connectivity options (PrivateLink, Private Endpoints, VPN Gateways).
        *   **Threat Detection & Monitoring:** Services like AWS GuardDuty, Azure Sentinel, Google Security Command Center for intelligent threat detection.
        *   **Encryption:** Strong support for encryption at rest for all storage and database services, and encryption in transit for all data movement.

3.  **Data Residency & Sovereignty:**
    *   **Considerations:** The provider must offer the ability to select specific geographic regions for data storage and processing, ensuring compliance with data sovereignty laws and policies that may require health data to remain within national or specific jurisdictional boundaries (e.g., within the UK or EEA).

4.  **Managed Services Availability:**
    *   **Considerations:** A rich portfolio of managed services can significantly reduce operational overhead. Key services include:
        *   **Databases:** Managed relational database services (e.g., AWS RDS, Azure SQL Database, Google Cloud SQL). *While primary HSMR data sources are likely external existing systems, the pipeline itself might benefit from a small operational database for metadata, job tracking, or temporary staging if complex transformations require it.*
        *   **Container Orchestration:** Managed Kubernetes (AWS EKS, Azure AKS, Google GKE) or simpler serverless container platforms (AWS ECS with Fargate, Azure Container Instances, Google Cloud Run).
        *   **Batch Processing:** Services like AWS Batch or Azure Batch, which are well-suited for running R and Python scripts as containerized jobs.
        *   **Secrets Management:** AWS Secrets Manager, Azure Key Vault, Google Secret Manager.
        *   **Logging & Monitoring:** AWS CloudWatch, Azure Monitor, Google Cloud Operations Suite (formerly Stackdriver).
        *   **Workflow Orchestration:** AWS Step Functions, Azure Logic Apps, Google Cloud Workflows (if not using a self-managed orchestrator like Airflow).

5.  **Scalability & Reliability:**
    *   **Considerations:** The provider's global infrastructure footprint, the design of their regions and Availability Zones (AZs), proven track record of reliability, and clear Service Level Agreements (SLAs) for key services. Support for auto-scaling of compute and storage resources.

6.  **Cost-Effectiveness:**
    *   **Considerations:** Transparent and predictable pricing models. Availability of pay-as-you-go options, reserved instances/savings plans for committed workloads, and spot instances for fault-tolerant batch jobs. Tools for cost monitoring, management, and optimization.

7.  **Existing Organizational Expertise & Strategic Alignment:**
    *   **Considerations:** If the parent organization (e.g., PHS or NHS Scotland) has an existing strategic partnership with a specific cloud provider, established infrastructure, or significant in-house skills, this can heavily influence the selection to leverage existing investments and expertise.

**Conceptual Choice Justification (Example - Assuming a UK context, AWS as a hypothetical choice):**

> "AWS is provisionally selected as the conceptual cloud provider. This choice is based on its comprehensive suite of services that can be configured to meet UK health data governance and security requirements (including services covered by BAAs and supporting data processing within UK regions). AWS offers robust security features (e.g., KMS for encryption key management, IAM for granular access control, GuardDuty for threat detection, VPC for network isolation), mature managed services relevant to this pipeline (such as AWS Batch for running containerized R/Python scripts, Amazon S3 for secure archival storage with versioning and lifecycle policies, AWS Secrets Manager for credential handling, and the CloudWatch suite for logging and monitoring). Furthermore, AWS provides extensive options for data residency within the UK, supporting compliance with data sovereignty policies. Its strong support for Infrastructure as Code (IaC) via CloudFormation and third-party tools like Terraform aligns with the goal of automated and reproducible environment management. A formal Business Associate Agreement would be established with AWS to cover the processing of any sensitive health data."

*(Similar justifications could be drafted for Microsoft Azure or Google Cloud Platform, highlighting their respective strengths in these areas, particularly their UK regions and compliance offerings for health data.)*

---

## II. Compute & Storage Resource Selection

**Objective:** Define the appropriate types of cloud compute and storage resources for each component and data type within the HSMR pipeline, balancing performance, cost, security, and manageability.

**A. Compute Resources (for R & Python script execution, potentially self-hosted GHA runners):**

1.  **Containerization (Primary Recommended Strategy):**
    *   **Approach:** Package R and Python script execution environments, including all specific library versions and dependencies, into Docker containers. This ensures consistency across development, staging, and production.
    *   **Orchestration/Execution Platform Options:**
        *   **Managed Batch Processing Services (e.g., AWS Batch, Azure Batch):**
            *   **Recommendation:** **Strongly recommended for the core HSMR analytical scripts (R and Python).** These services are designed for running batch computing workloads, can manage containerized jobs (from Docker images stored in a registry like ECR or ACR), handle dependencies, manage job queues, and provide scalable compute environments (e.g., based on EC2 Spot or On-Demand instances for AWS Batch) often with cost optimization benefits.
        *   **Serverless Containers (e.g., AWS Fargate with ECS or EKS, Azure Container Instances, Google Cloud Run):**
            *   **Suitability:** Excellent for running individual containerized tasks without managing the underlying server infrastructure. Could be used for shorter-lived Python scripts (e.g., `update_hsmr_config.py`, QA validation scripts) or potentially for R scripts if their execution time and resource needs fit within the service limits.
        *   **Full Kubernetes (e.g., AWS EKS, Azure AKS, Google GKE):**
            *   **Suitability:** Offers maximum flexibility and control for complex, multi-container applications that might require sophisticated networking, service discovery, or custom scaling logic. This is likely overkill for the HSMR pipeline if its components are primarily linear batch jobs but remains an option if a microservices-style architecture is pursued for different parts of the pipeline or if the organization has existing Kubernetes expertise and infrastructure.
    *   **Instance Types (if underlying VMs are configured, e.g., for AWS Batch with EC2, or direct VMs):**
        *   Select instance types based on the specific needs of the scripts. For R scripts, which can be memory-intensive and sometimes benefit from strong single-core performance (though some packages allow parallelism), memory-optimized (e.g., AWS R-family) or compute-optimized (e.g., AWS C-family) instances might be relevant. Python scripts are generally more flexible. Cost-effective general-purpose instances (e.g., AWS M-family, Azure D-series) might be sufficient. Leverage spot instances where appropriate for fault-tolerant batch workloads to reduce costs.

2.  **Virtual Machines (Alternative, or for specific components like Self-Hosted GHA Runners):**
    *   **Use Case:** If certain legacy components cannot be easily containerized, or for hosting self-hosted GitHub Actions runners if more control over the runner environment (e.g., specific OS, pre-installed software, enhanced security hardening, VNet integration for DB access) is required than what GitHub-hosted runners offer.
    *   **Instance Types:** Choose appropriate sizes based on workload (general purpose, compute-optimized, memory-optimized).
    *   **Operating System:** Standardized Linux distribution (e.g., Ubuntu LTS, Amazon Linux 2, RHEL), hardened according to security best practices.
    *   **Configuration Management:** If managing a fleet of VMs, use tools like Ansible, AWS Systems Manager, or Azure VM extensions for automated configuration, patching, and software deployment. (Containerization significantly reduces this need).

**B. Storage Resources:**

1.  **For Pipeline Operational/Temporary Data (e.g., intermediate files within a job run, if not purely processed in-memory):**
    *   **Compute-Attached Storage:** VMs or container hosts will have boot disks. Additional ephemeral or persistent block storage (e.g., AWS EBS, Azure Managed Disks, GCP Persistent Disks) can be attached.
    *   **Performance:** Choose SSD-backed storage for performance if I/O is intensive for intermediate files.
    *   **Encryption:** All compute-attached storage must be encrypted at rest using provider-managed or customer-managed keys.

2.  **For Input Data Staging (if data from source systems is landed before processing):**
    *   **Secure Object Storage (Recommended):** AWS S3, Azure Blob Storage, or Google Cloud Storage. Data can be landed here via secure transfer mechanisms (see Data Security Protocol). This storage should be temporary, with strict lifecycle policies to delete data after successful ingestion and processing. Must be encrypted at rest and have restricted access.
    *   **Alternative:** Encrypted block storage attached to a dedicated staging VM, if object storage is not suitable for the specific ingestion workflow.

3.  **For Output Artifacts (Generated by the pipeline: Raw Data extracts, Processed Data, Final Tables, Publication Documents, Logs - for Archival & Sharing):**
    *   **Object Storage (Primary Choice for Archival and intermediate pipeline artifacts):**
        *   AWS S3, Azure Blob Storage, Google Cloud Storage.
        *   **Configuration:** As detailed in the `DATA_SECURITY_AND_PRIVACY_PROTOCOL.md`:
            *   Server-side encryption enabled (SSE-S3, SSE-KMS, or equivalent).
            *   Object versioning enabled.
            *   Strict access control policies (IAM, bucket policies).
            *   Lifecycle policies for transitioning to archival tiers (e.g., S3 Glacier, Azure Archive) or for deletion according to retention schedules.
            *   Access logging enabled.

4.  **For GitHub Actions Artifacts (Workflow-Specific):**
    *   **GitHub Storage:** GitHub Actions has its own built-in artifact storage, used by `actions/upload-artifact` and `actions/download-artifact`. This is suitable for passing data between jobs within a workflow run.
    *   **Retention:** Default retention for GitHub Actions artifacts is 90 days (configurable).
    *   **Critical Long-Term Archival:** For critical outputs that need to be retained long-term (e.g., official publication documents, final datasets for audit, raw extracts for reprocessing), the pipeline must explicitly copy these from the GitHub Actions runner environment to the dedicated, secure object storage solution (e.g., S3, Azure Blob) defined for long-term archival. The `scripts/archive_and_stage.py` script is designed for this purpose.

---

## III. Infrastructure as Code (IaC) Strategy

**Objective:** To automate the provisioning, configuration, and management of all production (and staging) infrastructure components, ensuring consistency, reproducibility, version control, and auditable changes.

**Key Components & Recommendations:**

1.  **Tool Selection:**
    *   **Terraform (HashiCorp):**
        *   **Pros:** Cloud-agnostic (supports AWS, Azure, GCP, and others), declarative DSL (HCL), large community, extensive module registry, manages state effectively.
        *   **Recommendation:** **Often a strong choice, especially if there's a possibility of multi-cloud deployment or a desire for a standardized IaC language across different cloud providers.**
    *   **AWS CloudFormation:**
        *   **Pros:** Native AWS solution, deep integration with AWS services, managed service (no infrastructure to run the IaC tool itself).
        *   **Cons:** AWS-specific (YAML/JSON templates).
    *   **Azure Resource Manager (ARM) Templates / Bicep:**
        *   **Pros:** Native Azure solution, deep integration. Bicep offers a cleaner DSL on top of ARM JSON.
        *   **Cons:** Azure-specific.
    *   **Google Cloud Deployment Manager / Config Connector:**
        *   **Pros:** Native GCP solutions. Config Connector allows Kubernetes-style management of GCP resources.
        *   **Cons:** GCP-specific.
    *   **Pulumi:**
        *   **Pros:** Allows defining infrastructure using general-purpose programming languages (Python, TypeScript, Go, C#).
        *   **Cons:** May require more developer-centric skills for infrastructure management.
    *   **Decision Factor:** The choice often depends on existing team skills, organizational standards, and whether a single-cloud or multi-cloud strategy is in place. For a new, cloud-native project, Terraform is a common and robust starting point.

2.  **Version Control for IaC:**
    *   **Git Repository:** All IaC code (e.g., Terraform `.tf` files, CloudFormation templates, Ansible playbooks) must be stored in a dedicated Git repository or a clearly defined monorepo structure alongside the application code.
    *   **Best Practices:** Apply standard software development best practices to IaC:
        *   Branching strategies (e.g., GitFlow or feature branching).
        *   Code reviews for all infrastructure changes.
        *   Versioning and tagging of IaC releases.

3.  **IaC Structure & Modularity:**
    *   **Reusable Modules:** Organize IaC code into reusable, composable modules (e.g., a Terraform module for setting up a standard VPC, a module for deploying an EKS cluster, a module for configuring an S3 bucket with specific security and lifecycle policies). This promotes consistency and reduces code duplication.
    *   **Environment Isolation:** Use separate state files (e.g., for Terraform) and distinct configuration parameters for different environments (Dev, Staging, Prod) to maintain strict isolation and allow for environment-specific configurations. Workspace features in tools like Terraform are designed for this.

4.  **Automated Deployment of Infrastructure (CI/CD for Infrastructure):**
    *   **Pipeline Integration:** Integrate IaC deployment into a CI/CD pipeline (this can be the same GitHub Actions workflow used for application code or a separate, dedicated pipeline for infrastructure changes).
    *   **Workflow:**
        *   On changes to IaC code (e.g., merge to `main` branch of IaC repo):
            1.  **Lint & Validate:** Lint the IaC code (e.g., `terraform fmt`, `terraform validate`, `cfn-lint`).
            2.  **Plan/Preview:** Generate an execution plan showing the changes that will be made (e.g., `terraform plan`). This plan should be reviewed by a human.
            3.  **Approval (Manual Gate):** A manual approval step before applying changes to sensitive environments like Production.
            4.  **Apply:** Automatically apply the changes (e.g., `terraform apply -auto-approve` after the plan is approved).
    *   **State Management:** Securely manage and store IaC state files (e.g., using Terraform Cloud, AWS S3 with DynamoDB for locking, Azure Storage Account for backend state).

5.  **Scope of Infrastructure Defined by IaC:**
    *   **Networks:** VPCs/VNets, subnets, route tables, internet gateways, NAT gateways, security groups/NSGs, network ACLs, private endpoints.
    *   **Compute Resources:** Kubernetes clusters (EKS, AKS), Batch compute environments, VM launch templates/configurations, auto-scaling groups/scale sets.
    *   **Storage Resources:** Object storage buckets (S3, Azure Blob) with all configurations (encryption, versioning, lifecycle policies, access policies). Block storage configurations.
    *   **IAM (Identity & Access Management):** Roles, policies, user groups (though user management itself might be federated with an external IdP).
    *   **Monitoring & Logging Resources:** Configuration of logging sinks (e.g., CloudWatch Log groups), metric filters, basic alarm definitions if supported by the IaC provider for the chosen monitoring tools.
    *   **Secrets Management:** Provisioning of the secrets manager instance itself and core access policies to it (though the secrets *within* the manager are usually populated manually or via a separate secure process).

---
This conceptual design for the production infrastructure provides a foundation for building a secure, scalable, and manageable environment. The specific implementation details will depend on the chosen cloud provider and the detailed requirements of the HSMR pipeline as it evolves.
---
