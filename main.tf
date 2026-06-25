locals {
  # Intercept deployment group: auto-wired from ZTGW or explicit
  intercept_deployment_group = (var.deploy_ztgw
    ? ztc_forwarding_gateway.gcp_ztgw[0].intercept_deployment_group
    : var.intercept_deployment_group
  )

  # Security profile parent scope
  security_profile_parent = (var.security_profile_scope == "project"
    ? "projects/${var.project_id}"
    : "organizations/${var.organization_id}"
  )

  # Resource names with optional overrides
  consumer_fw_policy             = var.consumer_fw_policy != "" ? var.consumer_fw_policy : "${var.deploy_key}-consumer-policy"
  consumer_fw_policy_association = var.consumer_fw_policy_association != "" ? var.consumer_fw_policy_association : "${var.deploy_key}-consumer-policy-association"
  security_profile               = var.security_profile != "" ? var.security_profile : "${var.deploy_key}-custom-intercept-profile"
  security_profile_group         = var.security_profile_group != "" ? var.security_profile_group : "${var.deploy_key}-security-profile-group"
  endpoint_group                 = var.endpoint_group != "" ? var.endpoint_group : "${var.deploy_key}-intercept-endpoint-group"
  endpoint_group_association     = var.endpoint_group_association != "" ? var.endpoint_group_association : "${var.deploy_key}-intercept-endpoint-group-association"
}

# ---------------------------------------------------------------------------
# Provider side: GCP Zero Trust Gateway
# ---------------------------------------------------------------------------

data "ztc_location_template" "default" {
  count = var.deploy_ztgw ? 1 : 0
  name  = "Default Location Template"
}

resource "ztc_forwarding_gateway" "gcp_ztgw" {
  count    = var.deploy_ztgw ? 1 : 0
  name     = var.gateway_name
  platform = "GCP"
  region   = var.gcp_region

  prov_data {
    location_name = var.location_name

    location_template {
      id = data.ztc_location_template.default[0].id
    }

    iam_principals {
      type  = "USER"
      value = var.iam_principal_email
    }
  }
}

resource "ztc_activation_status" "activate" {
  count      = var.deploy_ztgw ? 1 : 0
  depends_on = [ztc_forwarding_gateway.gcp_ztgw]
}

# ---------------------------------------------------------------------------
# Consumer side: GCP NSI resources
# ---------------------------------------------------------------------------

data "google_compute_network" "consumer" {
  name    = var.consumer_network
  project = var.project_id
}

resource "google_compute_network_firewall_policy" "consumer" {
  name        = local.consumer_fw_policy
  project     = var.project_id
  description = "Consumer firewall policy for Zscaler GCP NSI intercept integration."
}

resource "google_compute_network_firewall_policy_association" "consumer" {
  name              = local.consumer_fw_policy_association
  project           = var.project_id
  attachment_target = data.google_compute_network.consumer.id
  firewall_policy   = google_compute_network_firewall_policy.consumer.id
}

resource "google_network_security_intercept_endpoint_group" "consumer" {
  provider = google-beta

  intercept_endpoint_group_id = local.endpoint_group
  project                     = var.project_id
  location                    = var.location
  intercept_deployment_group  = local.intercept_deployment_group
}

resource "google_network_security_intercept_endpoint_group_association" "consumer" {
  provider = google-beta

  intercept_endpoint_group_association_id = local.endpoint_group_association
  project                                 = var.project_id
  location                                = var.location
  network                                 = data.google_compute_network.consumer.id
  intercept_endpoint_group                = google_network_security_intercept_endpoint_group.consumer.id

  depends_on = [
    google_network_security_intercept_endpoint_group.consumer
  ]
}

resource "google_network_security_security_profile" "custom_intercept" {
  provider = google-beta

  name        = local.security_profile
  parent      = local.security_profile_parent
  location    = var.location
  description = "Custom intercept security profile for Zscaler GCP NSI integration."
  type        = "CUSTOM_INTERCEPT"

  custom_intercept_profile {
    intercept_endpoint_group = google_network_security_intercept_endpoint_group.consumer.id
  }

  depends_on = [
    google_network_security_intercept_endpoint_group.consumer
  ]
}

resource "google_network_security_security_profile_group" "consumer" {
  provider = google-beta

  name                     = local.security_profile_group
  parent                   = local.security_profile_parent
  location                 = var.location
  description              = "Security profile group for Zscaler GCP NSI integration."
  custom_intercept_profile = google_network_security_security_profile.custom_intercept.id

  depends_on = [
    google_network_security_security_profile.custom_intercept
  ]
}

resource "google_compute_network_firewall_policy_rule" "ingress_allow" {
  project         = var.project_id
  firewall_policy = google_compute_network_firewall_policy.consumer.name
  priority        = var.allow_ingress_rule_priority
  direction       = "INGRESS"
  action          = "allow"
  enable_logging  = var.enable_firewall_logging
  description     = "Allow trusted ingress sources without Zscaler inspection."

  match {
    src_ip_ranges = var.allow_ingress_source_ranges

    layer4_configs {
      ip_protocol = "all"
    }
  }

  depends_on = [
    google_compute_network_firewall_policy_association.consumer
  ]
}

resource "google_compute_network_firewall_policy_rule" "ingress_intercept" {
  project                = var.project_id
  firewall_policy        = google_compute_network_firewall_policy.consumer.name
  priority               = var.ingress_rule_priority
  direction              = "INGRESS"
  action                 = "apply_security_profile_group"
  security_profile_group = "//networksecurity.googleapis.com/${google_network_security_security_profile_group.consumer.id}"
  enable_logging         = var.enable_firewall_logging
  description            = "Apply Zscaler GCP NSI security profile group to ingress traffic."

  match {
    src_ip_ranges = var.ingress_source_ranges

    layer4_configs {
      ip_protocol = "all"
    }
  }

  depends_on = [
    google_compute_network_firewall_policy_association.consumer,
    google_network_security_security_profile_group.consumer
  ]
}

resource "google_compute_network_firewall_policy_rule" "egress_intercept" {
  project                = var.project_id
  firewall_policy        = google_compute_network_firewall_policy.consumer.name
  priority               = var.egress_rule_priority
  direction              = "EGRESS"
  action                 = "apply_security_profile_group"
  security_profile_group = "//networksecurity.googleapis.com/${google_network_security_security_profile_group.consumer.id}"
  enable_logging         = var.enable_firewall_logging
  description            = "Apply Zscaler GCP NSI security profile group to egress traffic."

  match {
    dest_ip_ranges = var.egress_destination_ranges

    layer4_configs {
      ip_protocol = "all"
    }
  }

  depends_on = [
    google_compute_network_firewall_policy_association.consumer,
    google_network_security_security_profile_group.consumer
  ]
}
