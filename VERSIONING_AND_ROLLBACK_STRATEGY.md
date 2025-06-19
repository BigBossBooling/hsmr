# HSMR Publication Pipeline: Versioning & Rollback Strategy

## Objective
This document outlines the conceptual strategy for versioning all components and outputs of the HSMR (Hospital Standardised Mortality Ratios) publication pipeline, and for managing rollbacks or corrections to published outputs in a controlled, auditable, and transparent manner.

## Guiding Principles
This strategy emphasizes reproducibility, traceability, data integrity, and clear communication. It aims to ensure that every HSMR publication can be linked to the exact code, data, and configuration that produced it, and that any necessary post-publication corrections are handled responsibly.

---

## I. Versioning Strategy for Pipeline Components & Outputs

**Objective:** To ensure every component and output of the HSMR pipeline is versioned to allow for reproducibility, auditing, and traceability of changes over time.

**Conceptual Solutions:**

1.  **Code & Configuration (Git-Based Version Control):**
    *   **A. Source Code Repository:**
        *   All scripts (R, Python, Shell), SQL queries, R Markdown (`.Rmd`) files, Infrastructure as Code (IaC) templates (e.g., Terraform, CloudFormation), and the GitHub Actions workflow file (`hsmr_automation_ci.yml`) will be stored and versioned in a dedicated Git repository (e.g., hosted on GitHub, GitLab, Azure Repos).
    *   **B. Branching Strategy:**
        *   A standard branching strategy (e.g., GitFlow with `main`, `develop`, feature branches (`feature/`), release branches (`release/`), and hotfix branches (`hotfix/`)) is recommended.
        *   The `main` branch represents production-ready code. All changes merged into `main` must go through Pull Requests (PRs), requiring code reviews and successful CI checks.
    *   **C. Tagging & Releases:**
        *   Git tags (e.g., `v1.0.0`, `v1.0.1-2023Q4_RunID12345`) must be used to mark specific commits on the `main` branch that correspond to a deployed version of the pipeline or a version used for a specific production HSMR publication run.
        *   GitHub Releases (or equivalent features in other Git platforms) can be used to bundle these tags with release notes detailing changes, bug fixes, and known issues for each version.
    *   **D. `hsmr_config.json` (Configuration File):**
        *   **Generation Logic:** The Python script responsible for generating `hsmr_config.json` (i.e., `update_hsmr_config.py`) is version-controlled in Git.
        *   **Run-Specific Instances:** The actual `hsmr_config.json` file generated for each pipeline run (containing dynamic dates, hashes of reference files, etc.) is versioned by being included as part of that specific pipeline run's artifacts (e.g., associated with the `github.run_id`). This ensures the exact configuration for any given output can be retrieved.
    *   **E. Lookup/Reference Files (`reference_files/`):**
        *   These files (e.g., `lookup_hospital_codes.csv`, `hsmr_report_template.csv`) should be version-controlled directly in Git if they are relatively small and change infrequently. Changes to these files must go through the PR and review process.
        *   The SHA256 hash of each version used in a run is recorded in that run's `hsmr_config.json`, linking the pipeline execution to specific versions of these reference files.
    *   **F. Schema Definitions (`schemas/`):**
        *   JSON schema files (e.g., `smr_output_schema.json`) defining the structure of data outputs must be version-controlled in Git.

2.  **Input Data (Raw Data Extracts from Source Systems):**
    *   **"Version" by Extraction Time:** The primary "version" identifier for raw data extracted from operational source systems is the precise timestamp of its extraction.
    *   **Archival of Raw Extracts:** If raw data extracts are stored long-term (as per the Data Security & Privacy Protocol), they must be archived with comprehensive metadata, including:
        *   The pipeline run ID that performed the extraction.
        *   The exact timestamp of extraction (start and end).
        *   The version of the SQL queries or API parameters used for extraction (traceable via the Git commit hash of the pipeline code for that run).
        *   The SHA256 hash of the extracted raw data file.
    *   **Naming Convention for Archived Raw Data:** A clear naming convention should be used, e.g., `[source_system]_[table_or_dataset_name]_extract_RunID[run_id]_Extracted[YYYYMMDDTHHMMSSZ].csv.gz`.

3.  **Processed Data & QA Reports (Intermediate Pipeline Artifacts):**
    *   **GitHub Actions Artifacts:** As currently designed, these artifacts (e.g., `raw-data-phase2-run-${{ github.run_id }}`, `processed-data-phase3-run-${{ github.run_id }}`, `validation-reports-phase4-run-${{ github.run_id }}`) are inherently versioned by the unique `github.run_id`.
    *   **Long-Term Archive:** When these critical intermediate artifacts are moved to long-term secure storage (e.g., S3, Azure Blob), they must retain this `github.run_id` (or an equivalent unique pipeline execution ID) in their storage path or metadata. This allows for complete traceability from a final publication back to the exact intermediate data and QA reports that produced it.

4.  **Statistical/AI Models (If Applicable in the Future):**
    *   **Context:** While the current HSMR pipeline uses established methodologies and rule-based (conceptual) anomaly detection, if pre-trained statistical or machine learning models were to be incorporated (e.g., for more advanced predictive modeling or anomaly detection):
    *   **Model Versioning:** Models must be versioned. This can be achieved using:
        *   A dedicated model registry (e.g., MLflow Model Registry, Kubeflow MLMD, Azure Machine Learning Model Registry, AWS SageMaker Model Registry).
        *   A clear file naming convention (e.g., `hsmr_prediction_model_v1.2.3.pkl`) in a version-controlled storage location (like S3 with versioning).
    *   **Traceability:** The `hsmr_config.json` for any pipeline run utilizing such a model must specify the exact version of the model(s) used. The model itself, its training script, and the data used for its training should also be version-controlled.

5.  **Final Publication Outputs (Documents & Publicly Released Data):**
    *   **Unique Publication Version Identifier:** Each distinct set of HSMR publication outputs (e.g., the main PDF report, summary HTML, public data CSVs) released for a given quarter must be assigned a clear, human-understandable, and unique version identifier. This should be distinct from just the pipeline run ID, as a single period might be re-published with corrections.
        *   **Format Example:** `[PublicationName]_[ReportingPeriod]_[VersionType]_vMAJOR.MINOR.PATCH`
            *   E.g., `HSMR_Full_Report_2023_Q4_Official_v1.0.0`
            *   E.g., `HSMR_Public_Data_2023_Q4_Official_v1.0.0.csv`
            *   If a correction is issued: `HSMR_Full_Report_2023_Q4_Corrected[YYYYMMDD]_v1.0.1` or `HSMR_Full_Report_2023_Q4_Restated[YYYYMMDD]_v1.1.0`.
    *   **Immutable Storage:** Each version of the final, approved publication set must be stored in the designated secure, version-enabled object storage (e.g., `s3://hsmr-archive/publications/HSMR_Full_Report_2023_Q4_v1.0.0/HSMR_Full_Report_2023_Q4_v1.0.0.pdf`). This ensures that once published, a version cannot be altered.
    *   **Publication Manifest:** The `archive_manifest_{publication_reference_period}.json` (conceptually generated by `scripts/archive_and_stage.py`) should list all individual files that constitute a specific version of the publication set, along with their individual SHA256 hashes. This manifest itself should be versioned and stored with the publication set.

---

## II. Publication Rollback Strategy

**Objective:** To define a clear, controlled, and auditable process for retracting or correcting an officially released HSMR publication if a critical error is discovered post-publication.

**Key Principles:** Prioritize transparency with stakeholders, ensure timely corrective action, maintain the integrity of historical records, and learn from errors to improve the pipeline.

**Conceptual Procedure:**

1.  **Error Detection & Initial Assessment:**
    *   **Reporting Channels:** Establish clear channels for reporting potential errors (e.g., internal QA findings post-release, feedback from data consumers, public inquiries).
    *   **Validation Team:** A designated team (e.g., data analysts, statisticians, SMEs, publication lead) validates the reported error to confirm its existence and understands its nature.
    *   **Impact Assessment:** This team assesses the impact of the error on the interpretation of the HSMR figures, public health implications, and stakeholder trust. They determine if the error is critical enough to warrant a rollback or formal correction.

2.  **Decision to Rollback / Correct / Restate:**
    *   **Governance Body:** A predefined governance body or senior management group makes the formal decision to retract, correct, or restate a publication based on the impact assessment.
    *   **Documentation:** This decision, along with its justification, must be formally documented.

3.  **Communication Plan (Internal & External):**
    *   **Internal Communication:** Immediately notify all relevant internal teams (e.g., data providers, web team, communications department, senior management) of the error and the planned corrective action.
    *   **External (Public) Communication:**
        *   Prepare a clear, concise, and transparent public statement. This statement should:
            *   Acknowledge the error in the specific HSMR publication (citing its version and publication date).
            *   Briefly explain the nature of the error and its potential impact on the data/interpretation (without overly technical jargon).
            *   State the corrective action being taken (e.g., "The publication dated [Original Date] has been retracted. A corrected version is being prepared and is expected by [New Date].").
            *   Provide contact information for inquiries.
        *   Distribute this notice prominently through the same channels where the original report was made available (e.g., official website, mailing lists).

4.  **Technical Steps for Rollback (Retraction of Erroneous Version):**
    *   **Identify Erroneous Version:** Clearly identify the unique Publication Version ID of the erroneous publication set.
    *   **Prevent Further Access/Distribution:**
        *   **Website/Portals:** Remove the erroneous files from public download locations or replace them with the retraction notice. Update any links pointing to the erroneous version.
        *   **Content Delivery Networks (CDN):** If a CDN is used, invalidate its cache for the erroneous files.
    *   **Mark as Retracted in Archive:** In the secure, immutable archive (e.g., S3 bucket):
        *   Clearly flag the specific version as "RETRACTED" or "SUPERSEDED" in its metadata or by moving it to a specific "retracted_publications" prefix/folder within the archive.
        *   **Crucially, do NOT delete the retracted version.** It must be preserved as part of the complete audit history and for understanding the context of the error. Link it to the corrected version once available.

5.  **Correction and Re-publication Process:**
    *   **A. Root Cause Analysis & Correction:**
        *   A thorough investigation is conducted to identify the root cause of the error (e.g., bug in an R script, incorrect lookup file version, flawed data processing logic, error in source data).
        *   Implement and test the necessary corrections in the pipeline code, configuration, or input data (if source data was re-supplied).
    *   **B. Deploy Correction:** Deploy the fix through the standard CI/CD pipeline, including all automated testing and QA stages.
    *   **C. Re-run Pipeline for Affected Period:**
        *   Execute the corrected HSMR automation pipeline for the affected publication period. This run will use the corrected code/config/data.
        *   The output will be a new, corrected set of publication files and data. This new set must receive a **new, distinct Publication Version ID** (e.g., incrementing a minor or patch version, like `HSMR_Full_Report_2023_Q4_v1.0.1`, or `HSMR_Full_Report_2023_Q4_Corrected_[Date]_v1.1.0`).
    *   **D. Publish Corrected Version:**
        *   The newly generated, corrected publication outputs must go through all standard human review and approval steps (as per the Human Integration & Collaboration Protocol).
        *   Once approved, publish the corrected documents and data files.
        *   Update the original retraction notice with a link to the new, corrected version and explain that it supersedes the previous one.
        *   Archive the corrected version with its new Publication Version ID in the immutable storage.

6.  **Post-Mortem Review & Process Improvement:**
    *   After the corrected version is published, conduct a post-mortem review involving all relevant teams.
    *   Analyze why the error occurred, why it was not caught by existing QA processes before the initial publication, and what improvements can be made to code, processes, QA checks, or monitoring to prevent similar errors in the future (aligning with the "Law of Constant Progression").
    *   Update SOPs, documentation, and the pipeline itself based on these lessons learned.

---

## III. Handling Data Corrections from Upstream Source Systems

**Scenario:** Data providers (e.g., hospitals, national data repositories) issue a formal correction or resupply of source data that was used in a previously published HSMR report.

**Conceptual Procedure:**

1.  **Notification & Initial Assessment:**
    *   Receive notification of the source data correction and understand its scope (e.g., which time periods, which data elements are affected).
    *   Evaluate the potential impact of this source data correction on the already published HSMR figures for the affected period(s). This requires re-running at least the core SMR calculations with the corrected source data (perhaps in a staging/analytical environment initially).

2.  **Decision on Restatement:**
    *   Based on the magnitude and significance of the changes to HSMR figures resulting from the corrected source data, a formal decision is made by the governance body on whether a full restatement of the past publication(s) is necessary.
    *   Minor source data changes that have a negligible impact on published HSMRs might only warrant an errata note or an update in a subsequent publication's methodology section, rather than a full restatement.

3.  **If Restatement is Deemed Necessary:**
    *   **A. Obtain Corrected Source Data:** Securely ingest the corrected source data.
    *   **B. Pipeline Configuration for Historical Run:**
        *   Configure the HSMR automation pipeline to run for the specific historical period(s) affected. This leverages the parameterization capabilities designed for `workflow_dispatch` (allowing specification of `target_year` and `target_quarter`).
        *   **Code Version:** Decide whether to use:
            *   The version of the pipeline code that was active at the time of the original publication (if precisely known and restorable, to purely reflect the impact of the data change).
            *   The current, most up-to-date version of the pipeline code (which includes any subsequent bug fixes or methodology improvements). This is often the preferred approach unless the goal is a very specific "what-if" analysis with old code. This choice should be documented.
    *   **C. Execute Pipeline & Generate Restated Outputs:** Run the pipeline. The outputs will constitute a new, restated publication set. This set must receive a **new, distinct Publication Version ID** that clearly indicates it is a restatement (e.g., `HSMR_Full_Report_YYYY_QN_Restated_[DateOfRestatement]_vX.Y.Z`).
    *   **D. Review & Approve Restated Outputs:** The restated outputs must go through the full internal QA, human review, and approval process.
    *   **E. Publish Restated Version:**
        *   Communicate clearly to stakeholders and the public that this is a restated version due to updated source data, explaining the nature of the changes.
        *   Replace the previous version on public platforms with the restated version, or provide clear links from the old version to the new restated one.
        *   Archive the restated version in immutable storage. The original version should also be retained in the archive, clearly marked as "Superseded by Restatement vX.Y.Z".

---
This Versioning & Rollback Strategy aims to ensure accountability, transparency, and a commitment to maintaining the integrity of HSMR publications over time, even when errors or source data corrections occur. It relies on robust versioning of all components and clear, documented procedures.
---
