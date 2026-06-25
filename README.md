# ZTGW Terraform GCP

Unified Terraform configuration for deploying **GCP Zero Trust Gateways** (Zscaler provider side) and connecting **consumer VPCs** (GCP NSI consumer side) — end-to-end.

One `terraform apply` provisions the entire Zscaler GCP NSI chain:

```
ZTGW (Zscaler GCP) → Intercept Deployment Group → Intercept Endpoint Group → Security Profile → Security Profile Group → Firewall Rules → Consumer VPC
```

---

## Table of Contents

- [Architecture](#architecture)
- [Prerequisites](#prerequisites)
- [Deployment Modes](#deployment-modes)
- [Usage](#usage)
- [Variables](#variables)
- [Outputs](#outputs)
- [Cleanup](#cleanup)
- [References](#references)

---

## Architecture

This configuration creates two sets of resources across two clouds:

### Provider Side (Zscaler)

| Resource | Provider | Description |
|----------|----------|-------------|
| `ztc_forwarding_gateway` | `zscaler/ztc` | GCP Zero Trust Gateway appliance in Zscaler-managed GCP |
| `ztc_activation_status` | `zscaler/ztc` | Activates the ZTGW configuration |
| `ztc_location_template` | `zscaler/ztc` | Data source for default location template |

### Consumer Side (GCP)

| Resource | Provider | Description |
|----------|----------|-------------|
| `google_compute_network` | `hashicorp/google` | Data source — existing consumer VPC |
| `google_compute_network_firewall_policy` | `hashicorp/google` | Global network firewall policy |
| `google_compute_network_firewall_policy_association` | `hashicorp/google` | Associates policy to consumer VPC |
| `google_network_security_intercept_endpoint_group` | `hashicorp/google-beta` | NSI endpoint group bound to ZTGW |
| `google_network_security_intercept_endpoint_group_association` | `hashicorp/google-beta` | Associates endpoint group to consumer VPC |
| `google_network_security_security_profile` | `hashicorp/google-beta` | Custom intercept security profile |
| `google_network_security_security_profile_group` | `hashicorp/google-beta` | Security profile group (referenced by firewall rules) |
| `google_compute_network_firewall_policy_rule` | `hashicorp/google` | Ingress allow, ingress intercept, and egress intercept rules |

### Traffic Flow

```
External Traffic
     │
     ▼
Consumer VPC ──► Firewall Policy ──► Security Profile Group ──►
                                          │
                                          ▼
                              Security Profile (CUSTOM_INTERCEPT)
                                          │
                                          ▼
                              Intercept Endpoint Group
                                          │
                                          ▼
                              Intercept Deployment Group
                                          │
                                          ▼
                              ZTGW (Zscaler GCP) ──► Zscaler Cloud
```

---

## Prerequisites

| Requirement | Details |
|---|---|
| Terraform 1.5+ | [Install Terraform](https://developer.hashicorp.com/terraform/downloads) |
| Zscaler OneAPI credentials | `client_id`, `client_secret`, `vanity_domain` from the Zidentity portal |
| GCP project with APIs enabled | `compute.googleapis.com`, `networksecurity.googleapis.com` |
| GCP authenticated identity | Permissions to create firewall policies, NSI resources, and org-level security profiles |
| Existing consumer VPC | This configuration reads an existing VPC — it does not create one |

---

## Deployment Modes

### Mode 1: Full Deployment (default)

Deploys a new ZTGW **and** all consumer-side resources in one run. The `intercept_deployment_group` is auto-wired from the ZTGW output.

```hcl
deploy_ztgw = true
```

### Mode 2: Consumer-Only

Connect an existing ZTGW's intercept deployment group to a consumer VPC. Skips ZTGW creation.

```hcl
deploy_ztgw                = false
intercept_deployment_group = "projects/.../locations/global/interceptDeploymentGroups/..."
```

---

## Usage

### 1. Clone the repository

```bash
git clone https://github.com/anasshahid1/ztgw-terraform-gcp.git
cd ztgw-terraform-gcp
```

### 2. Configure variables

```bash
cp terraform.tfvars.example terraform.tfvars
```

Edit `terraform.tfvars` with your values. At minimum:

```hcl
# ZTC auth
client_id     = "<your-client-id>"
client_secret = "<your-client-secret>"
vanity_domain = "<your-vanity-domain>"
cloud         = "zscaler"

# GCP consumer project
project_id         = "my-gcp-project"
organization_id    = "123456789012"
billing_project_id = "my-gcp-project"
consumer_network   = "my-vpc-network"

# ZTGW (only needed for deploy_ztgw = true)
iam_principal_email = "user@example.com"
```

### 3. Initialize

```bash
terraform init
```

### 4. Review the plan

```bash
terraform plan
```

### 5. Apply

```bash
terraform apply
```

Type `yes` when prompted.

### 6. Verify outputs

After apply, Terraform displays:

```
Outputs:

gateway_id                        = "12345678"
gateway_name                      = "gcp-ztgw-demo"
gateway_region                    = "us-central1"
intercept_deployment_group        = "projects/.../interceptDeploymentGroups/..."
firewall_policy_name              = "ztgw-nsi-consumer-policy"
intercept_endpoint_group_id       = "projects/.../interceptEndpointGroups/..."
intercept_endpoint_group_association_id = "projects/.../interceptEndpointGroupAssociations/..."
security_profile_id               = ".../securityProfiles/..."
security_profile_group_id         = ".../securityProfileGroups/..."
```

---

## Variables

### Deployment Mode

| Variable | Type | Default | Description |
|----------|------|---------|-------------|
| `deploy_ztgw` | `bool` | `true` | Deploy a new ZTGW. Set `false` for consumer-only. |

### Zscaler Authentication

| Variable | Type | Required | Description |
|----------|------|----------|-------------|
| `client_id` | `string` | Yes | OneAPI OAuth2 client ID |
| `client_secret` | `string` | Yes | OneAPI OAuth2 client secret (sensitive) |
| `vanity_domain` | `string` | Yes | Zscaler vanity domain (e.g. `acme`) |
| `cloud` | `string` | No | Cloud name (`zscaler`, `zscalerone`, etc.) |

### GCP ZTGW

| Variable | Type | Default | Description |
|----------|------|---------|-------------|
| `gateway_name` | `string` | `"gcp-ztgw-demo"` | Name of the ZTGW |
| `gcp_region` | `string` | `"us-central1"` | GCP region for the ZTGW |
| `location_name` | `string` | `"gcp-ztgw-demo-location"` | Zscaler location name |
| `iam_principal_email` | `string` | `""` | IAM principal email |

### Consumer Side

| Variable | Type | Default | Description |
|----------|------|---------|-------------|
| `intercept_deployment_group` | `string` | `""` | Existing ID (required when `deploy_ztgw = false`) |
| `security_profile_scope` | `string` | `"organization"` | `"organization"` or `"project"` |
| `project_id` | `string` | — | GCP consumer project |
| `organization_id` | `string` | `""` | GCP org ID (required for org-scoped profiles) |
| `billing_project_id` | `string` | — | Billing/quota project |
| `region` | `string` | `"us-central1"` | Default GCP region |
| `location` | `string` | `"global"` | NSI resource location |
| `consumer_network` | `string` | — | Existing VPC network name |
| `deploy_key` | `string` | `"ztgw-nsi"` | Naming prefix for all consumer resources |

### Resource Name Overrides

All optional — leave as `""` to auto-generate from `deploy_key`:

`consumer_fw_policy`, `consumer_fw_policy_association`, `endpoint_group`, `endpoint_group_association`, `security_profile`, `security_profile_group`

### Firewall Rules

| Variable | Type | Default | Description |
|----------|------|---------|-------------|
| `ingress_rule_priority` | `number` | `100` | Ingress intercept rule priority |
| `allow_ingress_rule_priority` | `number` | `90` | Ingress allow rule priority |
| `egress_rule_priority` | `number` | `101` | Egress intercept rule priority |
| `ingress_source_ranges` | `list(string)` | `["10.1.0.0/16"]` | CIDRs for ingress inspection |
| `allow_ingress_source_ranges` | `list(string)` | `["34.117.59.81/32"]` | CIDRs exempt from inspection |
| `egress_destination_ranges` | `list(string)` | `["0.0.0.0/0"]` | CIDRs for egress inspection |
| `enable_firewall_logging` | `bool` | `true` | Enable firewall rule logging |

---

## Outputs

| Output | Description |
|--------|-------------|
| `gateway_id` | ZTGW ID (null when `deploy_ztgw = false`) |
| `gateway_name` | ZTGW name |
| `gateway_region` | ZTGW GCP region |
| `intercept_deployment_group` | NSI intercept deployment group resource ID |
| `firewall_policy_name` | Created firewall policy name |
| `intercept_endpoint_group_id` | Created endpoint group resource ID |
| `intercept_endpoint_group_association_id` | Created endpoint group association ID |
| `security_profile_id` | Created security profile resource ID |
| `security_profile_group_id` | Created security profile group resource ID |

---

## Cleanup

```bash
terraform destroy
```

Terraform will tear down resources in reverse dependency order: firewall rules first, then security profile group, security profile, endpoint group association, endpoint group, firewall policy association, firewall policy, and finally the ZTGW.

---

## References

- [Zscaler ZTC Terraform Provider](https://registry.terraform.io/providers/zscaler/ztc/latest)
- [Google Cloud NSI Terraform Resources](https://registry.terraform.io/providers/hashicorp/google-beta/latest)
- [OneAPI Getting Started](https://automate.zscaler.com/docs/getting-started/getting-started)
