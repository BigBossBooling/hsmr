# HSMR Publication Pipeline: Human Integration & Collaboration Protocol

## Objective
This document outlines the conceptual design for integrating human review, approval, and knowledge management processes within the automated HSMR (Hospital Standardised Mortality Ratios) publication pipeline. It aims to ensure that human expertise provides oversight at critical junctures and that the pipeline remains understandable, operable, and maintainable.

## Guiding Principles
This protocol emphasizes transparency, accountability, the appropriate application of human expertise to complement automation, and the creation of a sustainable knowledge base for the team responsible for the HSMR publication. It aligns with "Stimulate Engagement, Sustain Impact" by ensuring human involvement and clear documentation.

---

## I. Human Review & Approval Gates

**Objective:** Define clear, auditable points in the automated HSMR pipeline where human expertise is required for review and explicit approval before the process continues or outputs are finalized for publication.

**Key Considerations & Conceptual Solutions:**

1.  **Critical Junctures for Review/Approval:**

    *   **A. Post Data Quality Assurance (Completion of Phase 4 - `quality_assurance` job):**
        *   **Trigger:** Successful completion of the `quality_assurance` job in the GitHub Actions workflow.
        *   **Review Items:**
            *   `schema_validation_report.json` (output from `qa_scripts/validate_schema.py`).
            *   `data_rules_validation_report.json` (output from `qa_scripts/validate_data_rules.py`).
            *   `anomaly_detection_report.json` (output from `qa_scripts/detect_anomalies.py`).
            *   Summary logs from the `quality_assurance` job.
        *   **Responsible Reviewers:** Data analysts, statisticians, subject matter experts (SMEs), potentially representatives from data providers if anomalies or data quality issues are traced back to source data.
        *   **Approval Criteria (Conceptual):**
            *   No critical schema validation failures (e.g., unexpected missing columns in key outputs).
            *   No critical data rule violations (e.g., SMR values wildly out of expected bounds, major internal inconsistencies not explained by data processing steps).
            *   All (conceptually) AI-flagged anomalies have been reviewed by an analyst. Each anomaly should be understood and either:
                *   Accepted with a documented justification (e.g., "This spike is due to known data characteristic X for this period").
                *   Marked as a true data quality issue requiring corrective action. Corrective action might involve:
                    *   Flagging issues to source data providers.
                    *   Re-running parts of the data extraction (Phase 2) or processing (Phase 3) if an error in those phases is identified.
                    *   In rare cases, acknowledging a known data quality limitation that will be noted in the publication.
        *   **Approval Mechanism & Workflow Impact:**
            *   **Notification:** Automated notification (e.g., email, Slack message, GitHub issue comment) sent to the designated review team with direct links to the QA reports (artifacts from the `quality_assurance` GHA job).
            *   **Recording Decision:**
                *   **Formal Sign-off:** A simple, formal sign-off mechanism is required. This could be a comment in a dedicated GitHub issue for the publication run (e.g., "QA Phase for YYYY_QN reviewed by [Analyst Name]. All anomalies investigated. Approved to proceed to document generation. Justification for anomaly X: [text].").
                *   **Checklist:** A digital checklist item that must be ticked off.
            *   **Pipeline Control:**
                *   **If Approved:** The pipeline can proceed to Phase 5 (Document Generation). In a fully automated GitHub Actions flow, this might involve a manual trigger (`workflow_dispatch`) for the Phase 5 job, or a specific commit/tag that triggers it.
                *   **If Rejected/Requires Action:** The pipeline HALTS progression to Phase 5. An issue is formally logged, and remediation actions are initiated. After remediation, the relevant preceding phases (e.g., Phase 2, 3, 4) would be re-run.

    *   **B. Pre-Publication (After Document Generation - Completion of Phase 5 - `generate_and_archive_publication` job, specifically after document knitting):**
        *   **Trigger:** Successful completion of the (simulated) document knitting step within the `generate_and_archive_publication` job.
        *   **Review Items:**
            *   The generated (simulated or actual) publication documents (PDFs, HTMLs, etc. from `publication_outputs/`).
            *   The checklist of manual finalization tasks presented by the `scripts/knit_hsmr_documents.R` script.
            *   Hashes of the generated documents.
        *   **Responsible Reviewers:** Publication lead, senior analysts, communications team, potentially a quality review group.
        *   **Approval Criteria (Conceptual):**
            *   (If documents are actual, not simulated): Documents are correctly formatted, all tables and figures render as expected, data represented in tables/charts is consistent with validated data from Phase 4.
            *   Narrative content is sound, clear, and accurate (this is a primarily human check).
            *   All manual finalization tasks identified by the pipeline (e.g., adding official cover pages, detailed formatting checks) have been acknowledged, and a plan for their completion is in place (or they have been completed if the workflow pauses for this).
            *   The overall presentation meets publication standards.
        *   **Approval Mechanism & Workflow Impact:**
            *   **Notification:** Similar to QA review, notification to the final review team.
            *   **Formal Sign-off:** This is a critical sign-off. It could involve a formal sign-off sheet (digital or physical, though digital is preferred for auditability) or a dedicated approval step in a workflow management tool.
            *   **Pipeline Control:** This approval signals that the archived outputs (from `scripts/archive_and_stage.py`) are considered the **official, approved version** for that publication period. Subsequent steps like making files publicly available or notifying stakeholders would only occur after this approval.

2.  **Approval Workflow & Tooling (Conceptual):**
    *   **GitHub-centric (Current Simulation):**
        *   Manual approval can be simulated by having a `workflow_dispatch` triggered job for the next major stage (e.g., a "Release Publication" job after Phase 5 approval).
        *   Using protected branches/tags in Git, where merges or pushes that trigger production runs require peer review and passing CI checks.
        *   Dedicated GitHub Issues for tracking each publication cycle, where reviewers post their approval comments.
    *   **Dedicated Workflow Orchestrators (e.g., Apache Airflow, Prefect, Dagster, Argo Workflows):**
        *   These tools often have built-in "sensor" tasks, "gate" tasks, or "manual approval" steps that can programmatically pause a workflow and wait for human input via a web UI before proceeding. This is ideal for formal approval gates.
    *   **Checklist/Sign-off Tools:** For formal review processes involving multiple stakeholders, external digital checklist tools (e.g., Microsoft Planner, Trello, Asana, or simple shared documents) can be used to track completion of review tasks, with a final confirmation fed back to the pipeline if needed.

3.  **Audit Trail for Approvals:**
    *   **Mandatory:** All review actions, comments, justifications for accepting anomalies, approvals, and rejections must be logged with user identities (e.g., GitHub username if using GitHub Issues/PRs) and timestamps.
    *   This approval log should be considered a critical part of the overall pipeline run's audit trail and should be archived alongside other logs and outputs for accountability and future reference.

4.  **Escalation Paths for Review & Approval:**
    *   **Defined Procedures:** Clear, documented procedures must be in place for situations where:
        *   Designated reviewers are unavailable within the required timeframe.
        *   Disagreements or contentious issues arise during the review process that cannot be resolved by the immediate reviewers.
    *   **Named Alternates/Backup Reviewers:** Identify and train backup personnel for critical review roles.
    *   **Clear Authority:** Define who has the final authority to resolve disputes or approve under exceptional circumstances.

---

## II. Documentation & Knowledge Transfer

**Objective:** Ensure that the HSMR automation pipeline is comprehensively documented to facilitate its effective operation, ongoing maintenance, troubleshooting, and continuous improvement by the responsible team. Enable efficient knowledge transfer to new or existing team members.

**Key Considerations & Conceptual Solutions:**

1.  **Types of Documentation:** A multi-layered approach to documentation is recommended:
    *   **A. System Architecture & Design Document:**
        *   The overall conceptual blueprint of the HSMR pipeline (covering Phases 1-5, QA, Security, Production Environment, Operations, Human Integration – essentially the content of these design documents).
        *   Provides a high-level overview, component interactions, data flow, and design rationale.
    *   **B. Standard Operating Procedures (SOPs) / Runbooks:**
        *   **Audience:** Operations team, analysts responsible for running/monitoring the pipeline.
        *   **Content:** Detailed, step-by-step instructions for:
            *   Manually triggering pipeline runs (e.g., via `workflow_dispatch` with parameters for specific quarters).
            *   Monitoring pipeline execution (e.g., how to view GitHub Actions runs, access centralized logs, interpret dashboards).
            *   Troubleshooting common errors and known failure scenarios (e.g., "What to do if Phase 2 database connection fails?", "Interpreting QA validation reports and common failure types").
            *   Emergency stop procedures for the pipeline.
            *   Rollback procedures (as defined in the Operationalization & Maintenance Protocol).
            *   Contact list for support, escalation, and subject matter experts for different components.
    *   **C. Technical Documentation for Each Pipeline Component:**
        *   **Audience:** Developers, maintainers, analysts needing to understand specific details.
        *   **Content (for each script: `.R`, `.py`, `.sh`, `.sql`, `.Rmd`, GHA workflow `.yml`):**
            *   **Purpose:** Clear statement of what the script/component does.
            *   **Inputs:** Expected input files, data structures, parameters, environment variables.
            *   **Outputs:** Generated files, artifacts, database changes (if any), key log messages.
            *   **Key Logic:** High-level description of the core algorithms or processing steps. Complex logic should have inline code comments.
            *   **Dependencies:** Required software, libraries (with versions), other scripts, system resources.
            *   **Error Handling:** Known exceptions/error conditions and how they are handled.
            *   **Configuration:** Relevant parameters from `hsmr_config.json` or environment variables.
        *   **Data Schema Definitions:** The JSON schema files in `schemas/` serve as documentation for expected data structures.
        *   **SQL Query Explanations:** Comments within the `.sql` files in `sql_queries/` explaining their purpose and key logic.
        *   **R Markdown Templates:** Documentation on the structure of `.Rmd` files, expected parameters, and how they consume data to produce reports.
    *   **D. Configuration Guide:**
        *   Detailed explanation of `hsmr_config.json`: each section, parameter, and its purpose/allowed values.
        *   Guidance on how `update_hsmr_config.py` generates this file.
    *   **E. CI/CD Pipeline Documentation:**
        *   Explanation of the GitHub Actions workflow (`hsmr_automation_ci.yml`): structure, jobs, key steps, triggers, artifact management.
        *   How to interpret CI/CD run results and logs.

2.  **Documentation Format & Storage:**
    *   **Primary Format:** Markdown is highly recommended for its ease of writing, editing, plain text diffing for version control, and readability. Diagrams can be embedded (e.g., using Mermaid syntax within Markdown, PlantUML, or by linking/embedding image files).
    *   **Primary Storage (Code-Adjacent):** Store all documentation within the same Git repository as the pipeline code (e.g., in a top-level `/docs` folder, or alongside components like `qa_scripts/README.md`).
        *   **Benefits:** Documentation is versioned with the code it describes, making it easier to keep them synchronized. Changes to documentation can be part of pull requests and code reviews.
    *   **Secondary Storage/Access (Optional, for wider audiences):**
        *   Rendered HTML versions of the Markdown documentation can be automatically generated (e.g., using MkDocs, Jekyll, Sphinx) and hosted on a GitHub Pages site, a corporate wiki (e.g., Confluence, SharePoint), or an internal documentation portal for easier browsing and access by non-technical stakeholders or operations teams.

3.  **Maintenance of Documentation ("Documentation as Code"):**
    *   **Living Document:** Documentation must be treated as a living and integral part of the HSMR pipeline system, not an afterthought.
    *   **Synchronized Updates:** Updates to pipeline code, scripts, configurations, or operational procedures *must* be accompanied by corresponding updates to the relevant documentation sections.
    *   **Part of Development/Release Cycle:** Include documentation review and update tasks as part of the definition of "done" for any new feature development or bug fix. Pull requests should ideally include documentation changes if relevant.
    *   **Periodic Review:** Schedule periodic reviews (e.g., bi-annually or annually, or after major pipeline changes) of all documentation to ensure accuracy, completeness, and continued relevance.

4.  **Knowledge Transfer & Training Strategies:**
    *   **Onboarding Program:** Develop a structured onboarding checklist and resource pack for new team members who will be involved in operating, maintaining, or developing the HSMR pipeline. This should heavily leverage the existing documentation.
    *   **Regular Refreshers & Cross-Training:** Conduct periodic refresher sessions or workshops, especially when significant changes are made to the pipeline. Encourage cross-training among team members to avoid single points of failure in knowledge.
    *   **"Fire Drill" Exercises (Operational Readiness):** Periodically simulate common or critical failure scenarios (e.g., a specific script failing, a QA check producing errors) to test the team's familiarity with SOPs/runbooks and their ability to troubleshoot and recover.
    *   **Collaborative Development Practices:** Encourage practices like pair programming and thorough code reviews during development, as these are excellent mechanisms for organic knowledge sharing and improving code quality.
    *   **Documentation "Sprints":** Occasionally dedicate time specifically for reviewing and improving documentation.

---
By implementing these human integration and collaboration protocols, the HSMR automation pipeline can become a more robust, transparent, and sustainable system, effectively balancing automated efficiency with essential human oversight and expertise.
---
