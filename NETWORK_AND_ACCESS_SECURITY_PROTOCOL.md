# HSMR Publication Pipeline: Network Security & Access Control Protocol

## Objective
This document outlines the conceptual design for network security and access control for the HSMR (Hospital Standardised Mortality Ratios) publication pipeline's production environment. It aims to establish a secure, isolated network foundation and ensure that all access to cloud resources is strictly governed by the principle of least privilege.

## Guiding Principles
This protocol is based on defense-in-depth, zero-trust network concepts (where applicable), explicit permissioning, and comprehensive auditability of access and network traffic. It aligns with industry best practices and requirements for handling sensitive data.

---

## I. Virtual Network Design (e.g., AWS VPC, Azure VNet, Google Cloud VPC)

**Objective:** To create a private, isolated network environment in the cloud for the HSMR production pipeline, shielding it from public internet access by default and enabling fine-grained control over data traffic flow.

**Key Components & Conceptual Solutions:**

1.  **Dedicated Virtual Network:**
    *   **Action:** Provision a new, dedicated Virtual Private Cloud (VPC) / Virtual Network (VNet) specifically for the HSMR production environment.
    *   **Rationale:** This ensures complete network isolation from other workloads, including development and staging environments, minimizing the risk of cross-environment contamination or unauthorized access.
    *   **IP Addressing:** Choose an appropriate private IP address range (CIDR block) for the VPC/VNet. This range must be carefully planned to avoid overlap with any on-premise networks or other cloud networks that might require peering or VPN connectivity in the future.

2.  **Subnetting Strategy (Implementing Layered Security / Defense-in-Depth):**
    *   **A. Private Subnets (Primary Location for Resources):**
        *   **Deployment:** All core application resources, including compute instances/container services (e.g., for R/Python script execution, self-hosted GitHub Actions runners if used), and any operational databases specific to the pipeline, should be deployed into private subnets.
        *   **Characteristics:** Private subnets, by definition, do *not* have a direct route to an Internet Gateway. Instances within private subnets are not directly reachable from the public internet.
        *   **High Availability:** Distribute private subnets across multiple Availability Zones (AZs) within the chosen cloud region to ensure resilience against single AZ failures.
    *   **B. Public Subnets (Restricted Use):**
        *   **Purpose:** Public subnets are only used for resources that *must* have direct internet connectivity. For a backend processing pipeline like HSMR, this is typically limited to:
            *   **NAT Gateways (AWS) / Azure NAT Gateway / Azure Firewall / Cloud NAT (GCP):** These allow instances in private subnets to initiate outbound connections to the internet (e.g., for downloading software packages from official repositories, accessing specific public APIs if required by the pipeline, or GitHub Actions runners communicating with GitHub.com) without exposing the instances to inbound connections from the internet.
            *   **Bastion Hosts / Jump Boxes (Optional, with strict security):** If direct SSH/RDP access to instances in private subnets is ever required for emergency troubleshooting (routine access should be via systems management tools), a hardened bastion host in a public subnet can be used as a controlled entry point. Access to the bastion host must be strictly controlled (e.g., specific source IPs, MFA, just-in-time access).
        *   **Security:** Resources in public subnets (like NAT Gateways) must be protected by Security Groups/NSGs and Network ACLs.
    *   **C. Database Subnets (Optional, for Enhanced Segmentation):**
        *   **Purpose:** If the pipeline utilizes an internal operational database (distinct from the main source databases), these can be placed in dedicated database subnets.
        *   **Access Control:** These subnets would have even stricter Network ACLs and Security Group rules, allowing inbound database connections only from specific application subnets/security groups where the pipeline's compute resources reside.

3.  **Routing Tables:**
    *   **Configuration:** Define explicit route tables for each subnet to control traffic flow.
    *   **Private Subnet Routing:**
        *   Route default internet-bound traffic (0.0.0.0/0) to the NAT Gateway (or equivalent service) located in a public subnet.
        *   Define routes for internal traffic within the VPC/VNet.
        *   If connecting to on-premise data sources, routes would point to a Virtual Private Gateway (AWS VPN/Direct Connect) or ExpressRoute Gateway (Azure).
    *   **Public Subnet Routing:**
        *   Route default internet-bound traffic (0.0.0.0/0) to an Internet Gateway (IGW) attached to the VPC/VNet.

4.  **Network Access Control Lists (NACLs):**
    *   **Function:** Apply NACLs as a stateless, secondary firewall layer at the subnet level for both inbound and outbound traffic.
    *   **Rules:** Define rules based on IP address, protocol, and port. NACLs should be more restrictive than Security Groups/NSGs where feasible, providing an additional barrier.
    *   **Default Deny:** Start with a default deny rule and explicitly allow only necessary traffic.
    *   **Stateless Nature:** Remember that NACLs are stateless, meaning both inbound and corresponding outbound (return) rules must be explicitly defined.

5.  **Domain Name System (DNS) Resolution:**
    *   **Private DNS:** Utilize private DNS zones within the cloud provider's DNS service (e.g., AWS Route 53 Private Hosted Zones, Azure Private DNS Zones, Google Cloud DNS private zones). This allows for internal name resolution of resources (e.g., database endpoints, internal service addresses) within the VPC/VNet using custom domain names, without exposing these names to the public DNS system.

---

## II. Firewall Rules & Security Groups (e.g., AWS Security Groups, Azure Network Security Groups - NSGs)

**Objective:** To implement stateful, instance-level (or service-level where applicable, e.g., for Lambda functions, load balancers) firewalls that precisely control inbound and outbound network traffic to and from the individual components of the HSMR pipeline.

**Key Principles & Conceptual Solutions:**

1.  **Default Deny:** All Security Groups (SGs) / Network Security Groups (NSGs) must be configured with a default-deny rule for all inbound traffic. Outbound traffic should also start as default-deny and only allow specific necessary connections.
2.  **Principle of Least Privilege for Network Traffic:** Only open the specific ports and protocols that are absolutely essential for a component to perform its function and communicate with other explicitly authorized components or services.
3.  **Stateful Inspection:** Leverage the stateful nature of SGs/NSGs. If an outbound connection is allowed (e.g., from an application runner to a database), the return traffic for that established connection is automatically permitted, simplifying rule creation.
4.  **Application-Specific or Role-Specific Groups:**
    *   **Granularity:** Create distinct SGs/NSGs for different logical roles or components of the pipeline (e.g., a group for the compute instances running R scripts, another for Python validation scripts if they have different access needs, a specific group for any internal operational database).
    *   **Example Naming & Rules:**
        *   `HSMR-DataProcessing-SG`:
            *   **Inbound:** Potentially no inbound rules if these instances only initiate connections. If they need to be triggered (e.g., by an orchestrator within the VPC), allow inbound from the orchestrator's SG on a specific port.
            *   **Outbound:** Allow access to specific database ports (if connecting to source DBs over a private network link), to secrets manager endpoints (HTTPS), to logging/monitoring service endpoints (HTTPS), and to package repositories (via NAT Gateway on HTTP/HTTPS).
        *   `HSMR-SelfHostedGHARunner-SG` (if self-hosted runners are used):
            *   **Inbound:** Typically no inbound rules from outside the VPC.
            *   **Outbound:** Access to GitHub.com services (HTTPS), package repositories (via NAT Gateway), secrets manager, logging/monitoring services.
        *   `HSMR-InternalDB-SG` (if an operational database is used by the pipeline itself):
            *   **Inbound:** Allow traffic only from the `HSMR-DataProcessing-SG` (or other specific application SGs) on the database listener port (e.g., TCP 5432 for PostgreSQL).
            *   **Outbound:** Minimal, perhaps only to logging/monitoring or for OS updates via NAT Gateway if it's a VM-based DB.
5.  **Source/Destination Specificity in Rules:**
    *   **Prefer Security Group/NSG IDs:** When defining rules, use other SG/NSG IDs or Application Security Group (ASG) IDs as the source or destination where possible, instead of IP addresses or CIDR ranges. This creates more dynamic and maintainable rules that automatically adapt if instances within those source/destination groups change their IP addresses.
    *   **IP Addresses/CIDRs:** Use specific IP addresses or narrow CIDR ranges only when necessary (e.g., for connecting to specific on-premise resources via VPN/Direct Connect, or for bastion host access).
6.  **Regular Review & Audit of Firewall Rules:**
    *   Firewall rules (SGs/NSGs and NACLs) must be regularly reviewed (e.g., quarterly or annually) and audited to:
        *   Remove any rules that are no longer necessary (e.g., for decommissioned components or temporary access).
        *   Ensure all rules still align with the principle of least privilege and current security best practices.
        *   Verify that documentation for the rules is accurate.
    *   Utilize cloud provider tools (e.g., AWS VPC Network Access Analyzer, Azure Network Watcher) to help analyze network reachability and identify overly permissive rules.

---

## III. Identity and Access Management (IAM) Policies (Cloud Provider Specific)

**Objective:** To ensure that all actions performed on cloud resources by users (administrators, developers, operators) and by automated services or pipeline components are authenticated and authorized based on the principle of least privilege.

**Key Components & Conceptual Solutions:**

1.  **Roles for Compute Services & Pipeline Components:**
    *   **Dedicated IAM Roles:** Define specific IAM roles that will be assumed by the cloud compute services running the HSMR pipeline components. Examples:
        *   EC2 Instance Profiles (if using VMs for self-hosted runners or other tasks).
        *   Task Roles for AWS ECS/Fargate.
        *   Execution Roles for AWS Lambda (if used).
        *   Roles for AWS Batch compute environments/jobs.
        *   Service Accounts for Kubernetes pods (which can be mapped to cloud IAM roles, e.g., IAM Roles for Service Accounts - IRSA in EKS).
    *   **Least Privilege Permissions:** These roles must be configured with IAM policies granting *only* the minimum necessary permissions for that component to perform its specific tasks. Examples:
        *   Read access to specific secrets (e.g., database credentials, API keys) in AWS Secrets Manager or Azure Key Vault.
        *   Write access to specific S3 buckets/prefixes for storing logs and output artifacts (e.g., `s3:PutObject` to `arn:aws:s3:::hsmr-artifacts-bucket/logs/*`).
        *   Read access to S3 buckets/prefixes for retrieving input data, R Markdown files, or configuration files (e.g., `s3:GetObject` from `arn:aws:s3:::hsmr-input-data-bucket/*`).
        *   Permissions to publish metrics to the monitoring service (e.g., `cloudwatch:PutMetricData`).
        *   Permissions to interact with database services at a control plane level if needed (e.g., to describe RDS instances), but generally *not* direct data access permissions (which are handled by the database's own user credentials retrieved from Secrets Manager).
        *   Permissions for services to assume other roles if a federated access or cross-account access pattern is required (use with caution and specific trust policies).

2.  **User Access (for Human Administrators, Developers, Operators):**
    *   **IAM Users & Groups:**
        *   Define individual IAM users for each person requiring access to the cloud environment. Avoid using shared user accounts.
        *   Assign users to IAM groups based on their job functions and required access levels (e.g., `HSMR-Administrators`, `HSMR-Pipeline-Developers`, `HSMR-Data-Analysts-ReadOnly`).
    *   **Role-Based Access Control (RBAC):** Assign IAM policies (permissions) to groups rather than directly to individual users. Users then inherit permissions based on their group memberships. This simplifies user management and permission consistency.
    *   **Multi-Factor Authentication (MFA):** Enforce MFA for all IAM users, especially for those with privileged access (administrative roles). This is a critical security control.
    *   **Federated Access (Preferred for Organizations):** If the organization uses an existing Identity Provider (IdP) like Azure AD, Okta, or Active Directory, configure IAM federation. This allows users to access cloud resources using their existing corporate credentials, centralizing user management and policy enforcement. Users would assume IAM roles upon federated login.
    *   **Minimize Long-Lived Access Keys for Users:** Discourage or prohibit the creation and use of long-lived IAM access keys (Access Key ID and Secret Access Key) for human users. Instead, users should interact with the cloud environment via:
        *   The management console (which requires MFA).
        *   The Command Line Interface (CLI) using temporary credentials obtained by assuming an IAM role (e.g., via `aws sts assume-role` or by configuring the CLI to use federated login).

3.  **Service Permissions & Resource-Based Policies:**
    *   In addition to IAM roles for compute, ensure that cloud services themselves (e.g., S3 buckets, KMS keys, SQS queues if used) have appropriate resource-based policies. These policies can further restrict access to specific principals (users, roles, services) or based on conditions (e.g., source VPC endpoint, encryption status).

4.  **Policy Granularity & Conditions:**
    *   **Avoid Wildcards (`*`):** Do not use overly broad permissions like `*` for actions or resources in IAM policies.
    *   **Specify Actions & Resources:** Explicitly list individual allowed actions (e.g., `s3:GetObject`, `s3:PutObject`, `secretsmanager:GetSecretValue`) and define the specific resource ARNs (Amazon Resource Names, or equivalent cloud provider identifiers) to which these actions apply.
    *   **Use Condition Keys:** Leverage condition keys in IAM policies to add further restrictions based on context, such as:
        *   Source IP address or VPC endpoint.
        *   Time of day.
        *   MFA status of the session.
        *   Specific tags on resources.

5.  **Regular Audits and Reviews of IAM Policies:**
    *   **Periodic Reviews:** Regularly (e.g., quarterly or semi-annually) review all IAM users, groups, roles, and their attached policies.
    *   **Remove Unused Credentials/Permissions:** Identify and remove any unused IAM users, roles, or credentials. Revoke unnecessary permissions to maintain least privilege.
    *   **Leverage IAM Tools:** Utilize cloud provider tools (e.g., AWS IAM Access Analyzer, Azure AD Access Reviews) to help identify overly permissive configurations, unused roles, or external access risks.

---
Implementing this Network Security & Access Control Protocol is fundamental to protecting the HSMR pipeline and the sensitive data it processes. It requires careful planning, ongoing management, and regular review to adapt to evolving threats and requirements.
---
