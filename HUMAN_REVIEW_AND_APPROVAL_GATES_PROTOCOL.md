# HSMR Publication Pipeline: Human Review & Approval Gates Protocol

## Objective
This document outlines the conceptual design for integrating mandatory human review and approval gates within the automated HSMR (Hospital Standardised Mortality Ratios) publication pipeline. The purpose is to ensure that human expertise and judgment are applied at critical checkpoints before the pipeline proceeds to subsequent stages or before final outputs are released, thereby enhancing quality, accountability, and trust in the published results.

## Guiding Principles
*   **Risk-Based Intervention:** Human review gates are strategically placed at points where automated checks may be insufficient to cover all nuances, or where qualitative expert judgment is essential for interpreting results or validating outputs.
*   **Clear Accountability:** Specific roles and responsibilities are assigned for each review and approval step.
*   **Auditability:** All review and approval actions, including justifications for decisions, must be logged to maintain a transparent and auditable trail.
*   **Efficiency:** While thorough, the review process should be designed to be as efficient as possible to not unduly delay timely publication. Clear information and streamlined mechanisms are key.

---

## I. Definition of Mandatory Review & Approval Gates

**Objective:** To identify and define specific checkpoints in the HSMR automation pipeline where human intervention is mandatory for review and explicit approval before the pipeline can proceed to subsequent critical stages or final output release.

**Identified Gates:**

1.  **Gate 1: Post-Quality Assurance (QA) Data Validation Review & Approval**
    *   **Trigger Point:** This gate is activated after the `quality_assurance` job (conceptually, Phase 4 of the pipeline) in the GitHub Actions workflow completes successfully.
    *   **Purpose:** To have designated human experts (data analysts, statisticians) review the automated QA findings. The goal is to determine if the processed data (from Phase 3) is deemed fit for use in generating the final HSMR publication documents and other outputs.
    *   **Information/Artifacts for Review:**
        *   `schema_validation_report.json` (output from `qa_scripts/validate_schema.py`).
        *   `data_rules_validation_report.json` (output from `qa_scripts/validate_data_rules.py`).
        *   `anomaly_detection_report.json` (output from `qa_scripts/detect_anomalies.py` - conceptual AI/statistical anomaly flags).
        *   Direct links to the underlying data artifacts if deeper inspection is required (e.g., `processed-data-phase3-run-[run_id]` and `final-tables-phase3-run-[run_id]`).
        *   Summary logs or key warnings from the preceding Phase 3 (`process_and_analyze_data`) and Phase 4 (`quality_assurance`) job executions.
    *   **Designated Reviewers/Approvers:**
        *   Lead Data Analyst for HSMR.
        *   Lead Statistician for HSMR.
        *   Optionally, a representative from a data governance body or a relevant Subject Matter Expert (SME) group, especially if significant anomalies or data quality concerns are flagged.
    *   **Approval Criteria (Illustrative):**
        *   No "FAILED" status in `schema_validation_report.json` for critical data files.
        *   No "FAILED" status in `data_rules_validation_report.json` for critical data integrity rules.
        *   If "FAILED" statuses exist for non-critical checks, they must be reviewed, understood, and explicitly acknowledged with justification if the decision is to proceed.
        *   All "detected_anomalies" (from `anomaly_detection_report.json`) must be reviewed. Each flagged anomaly should be:
            *   Dismissed as a false positive or an acceptable/explainable variation (with documented justification).
            *   Confirmed as a genuine data issue that requires remediation. This would typically lead to a "Rejected/Rework Required" decision for this gate.
        *   Reviewers express overall confidence that the data is sound and appropriate for use in the publication.
    *   **Pipeline Response to Approval/Rejection:**
        *   **If Approved:** The pipeline is authorized to proceed to Phase 5 (`generate_and_archive_publication` job for document knitting and final archiving).
        *   **If Rejected (or Rework Required):** The pipeline HALTS its progression to Phase 5. Automated notifications are sent to the relevant development/data teams detailing the reasons for rejection. Remediation might involve:
            *   Addressing issues in source data (if feasible and the root cause).
            *   Correcting data processing logic in Phase 2 (Data Acquisition) or Phase 3 (Core Analysis) scripts.
            *   Updating or refining QA rules in Phase 4 scripts.
            *   After corrections are made and committed, the pipeline (or relevant preceding jobs) must be re-run, leading back to this QA review gate.

2.  **Gate 2: Pre-Publication Document Finalization & Release Approval**
    *   **Trigger Point:** This gate is activated after the (simulated) R Markdown document knitting step within the `generate_and_archive_publication` job (Phase 5) completes, and the "Manual Finalization Checklist" (generated by `scripts/knit_hsmr_documents.R`) is available.
    *   **Purpose:** To have designated human experts perform final quality checks on the generated publication documents (e.g., PDF reports, HTML summaries) for content accuracy, formatting, narrative coherence, and to confirm that all necessary manual finalization tasks have been completed before the documents are considered "official" and are fully archived for release and potential public distribution.
    *   **Information/Artifacts for Review:**
        *   The generated publication documents (e.g., `HSMR_Main_Report_YYYY_QN.pdf`, `HSMR_Main_Report_YYYY_QN.html`, etc., from the `publication-docs-phase5-run-[run_id]` artifact).
        *   The "Manual Finalization Checklist" as outputted by the `scripts/knit_hsmr_documents.R` script.
        *   (Optionally) The `archive_manifest_{publication_reference_period}.json` if it's generated locally by `scripts/archive_and_stage.py` before its final (simulated) "remote" write, to confirm the list of files being archived.
    *   **Designated Reviewers/Approvers:**
        *   Publication Lead / Senior Manager responsible for the HSMR publication.
        *   Representatives from the Communications team (for clarity, branding, style guide adherence).
        *   Lead Data Analyst and/or Statistician (for a final check on data representation and interpretation accuracy).
        *   Relevant governance or oversight body, if applicable.
    *   **Approval Criteria (Illustrative):**
        *   All items on the "Manual Finalization Checklist" (e.g., adding cover pages, verifying table formatting, proofreading) have been satisfactorily completed and signed off (conceptually, or via an actual checklist process).
        *   Visual inspection of the documents confirms acceptable quality, correct formatting, and no obvious errors in data presentation, charts, or tables.
        *   The narrative content, interpretations, and any caveats are sound, clear, and appropriate for the intended audience.
        *   All necessary internal sign-offs (e.g., from senior management, ethics review if applicable) have been obtained.
    *   **Pipeline Response to Approval/Rejection:**
        *   **If Approved:** The `scripts/archive_and_stage.py` script proceeds with its full archival and staging operations (if it was designed to wait for this formal approval, or if this approval triggers that script as a subsequent step). The approved documents and associated data are now considered the **official version of record** for that publication period. A notification of successful finalization and readiness for publication can be sent.
        *   **If Rejected (or Rework Required):** The pipeline (or at least the final archival, staging, and public distribution steps) HALTS. Documents are not promoted to "official" status. Issues identified (e.g., formatting errors, necessary changes to narrative, data misinterpretations) are documented and assigned for correction. This might involve:
            *   Manual edits to the source R Markdown files, followed by re-knitting (re-running the relevant parts of the Phase 5 job).
            *   If critical data errors are somehow discovered at this very late stage (which should be rare if Gate 1 was thorough), it might necessitate going back to earlier pipeline phases for correction and reprocessing.

---

## II. Mechanism for Signaling, Recording, and Responding to Review/Approval Gates

**Objective:** To define how the HSMR automation pipeline communicates that a review gate has been reached, how human approvals or rejections are formally captured, and how the pipeline programmatically acts upon these decisions.

**Conceptual Solutions:**

1.  **Signaling Review Readiness & Notification:**
    *   **Automated Notifications:** Upon successful completion of a GitHub Actions job that precedes a review gate (e.g., the `quality_assurance` job before Gate 1, or the document knitting step within `generate_and_archive_publication` before Gate 2), the workflow should automatically send notifications to the designated review group(s).
    *   **Notification Channels:**
        *   **Email:** Send emails to a distribution list of reviewers.
        *   **Team Collaboration Platforms:** Post messages to a dedicated Slack or Microsoft Teams channel.
        *   **GitHub Issues/Comments:** Create or update a specific GitHub Issue associated with the publication run (e.g., "HSMR YYYY QN - Gate 1: Data QA Review Required"). Actions like `peter-evans/create-or-update-comment` can be used if the workflow is tied to a Pull Request or a specific commit.
    *   **Notification Content:** Messages must be clear and actionable, including:
        *   The specific publication period (e.g., YYYY QN).
        *   The review gate that has been reached.
        *   Direct links to the relevant artifacts to be reviewed (e.g., QA reports, draft publication documents from GitHub Actions artifacts).
        *   A deadline for the review, if applicable.
        *   Instructions on how to record the approval/rejection decision.

2.  **Recording Approval/Rejection Decisions:**
    *   **Option A (GitHub-Centric - Simpler for current GHA-based design):**
        *   **For PR-Based Workflows (if used for promoting changes that trigger runs):** Require formal PR approvals from designated individuals or teams. The merge event itself signifies approval.
        *   **For `workflow_dispatch` or Scheduled Runs:**
            *   A subsequent `workflow_dispatch` event could serve as the approval mechanism. A designated person with appropriate GitHub permissions would manually trigger a "Proceed_to_Phase5" or "Approve_Publication_Release" workflow, potentially with an input parameter like `status: approved` or `status: rejected_for_rework_X`.
            *   **Issue/Comment Tracking:** Reviewers post their approval/rejection (with mandatory justification for rejection or conditional approval) as a comment in a predefined GitHub Issue for that run. A specific keyword (e.g., `/approve-qa-YYYYQN`, `/reject-qa-YYYYQN reason="..."`) could be used. A subsequent workflow step (potentially manually triggered or on a short schedule) could parse these comments. This is more complex to automate reliably.
    *   **Option B (Dedicated Workflow Orchestrator - e.g., Airflow, Prefect, Argo Workflows):**
        *   These tools often provide native UI-based "approval" or "gate" tasks. The workflow pauses at such a task, sends notifications, and waits for a user to log into the orchestrator's UI and explicitly approve or reject the step. This is a very robust and auditable method.
    *   **Option C (External Checklist / Sign-off System):**
        *   The pipeline logs that it is "Awaiting [GateName] Approval in [ExternalSystemLink]".
        *   Once approval is recorded in the external system (e.g., a SharePoint list, a dedicated QA tool, a signed PDF checklist uploaded to a known location), a responsible individual manually triggers the next stage of the pipeline (e.g., via `workflow_dispatch`), potentially providing a reference to the external approval record.
    *   **Justification Requirement:** For all approval/rejection decisions, especially rejections or approvals that override automated warnings (like accepting AI-flagged anomalies), a brief written justification must be recorded as part of the decision log.

3.  **Pipeline Response Logic (within GitHub Actions Workflow):**
    *   **Conditional Job Execution:** The progression to subsequent jobs in the GitHub Actions workflow will be made conditional on the approval received at a gate.
        *   **If using `workflow_dispatch` for approval signaling:** The workflow that receives the approval `workflow_dispatch` (e.g., "Proceed_to_Phase5") would then execute the next set of jobs. The main pipeline might be structured as multiple, smaller, interdependent workflows.
        *   **If using PR approvals:** The merge event to a specific branch (e.g., `staging` or `main`) would trigger the next job sequence.
        *   **If parsing comments/issues (more complex):** A dedicated workflow step might query the GitHub API. Its output (approved/rejected) could then be used in `if` conditions for subsequent steps/jobs. `if: steps.approval_check.outputs.status == 'approved'`
    *   **Timeout for Approvals:** Implement a reasonable timeout period for awaiting human approval at each gate. If no approval or rejection is recorded within this period (e.g., 2-3 business days), the system should:
        *   Send automated reminder notifications.
        *   Escalate to a secondary reviewer or manager if the primary reviewer is unresponsive.

4.  **Audit Trail for Human Actions:**
    *   **Automatic Logging by Platform:** GitHub Actions inherently logs all workflow triggers, including `workflow_dispatch` events with their inputs and the user who triggered them. Pull Request approvals and merges are also part of the Git/GitHub audit trail.
    *   **Explicit Logging by Workflow:** If using mechanisms like parsing issue comments or specific approval workflow parameters, the GitHub Actions workflow step that processes these must explicitly log:
        *   The decision (Approved/Rejected).
        *   The identity of the approver(s) (e.g., GitHub username).
        *   The timestamp of the approval.
        *   Any provided justification comments.
    *   **Archival:** This human approval audit trail must be captured and archived alongside all other pipeline logs and generated artifacts for the specific HSMR publication run. It forms a critical part of the overall governance and accountability record.

---
This protocol for Human Review & Approval Gates aims to integrate necessary human oversight into the automated HSMR pipeline, ensuring that expert judgment validates critical stages and outputs. The specific tooling for implementing these gates can range from simpler GitHub-native mechanisms to more sophisticated external workflow orchestrators, depending on organizational requirements and technical infrastructure.
---
