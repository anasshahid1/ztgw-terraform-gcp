# ---------------------------------------------------------------------------
# Provider-side outputs (ZTGW)
# ---------------------------------------------------------------------------

output "gateway_id" {
  description = "ID of the GCP ZTGW."
  value       = var.deploy_ztgw ? data.external.ztgw[0].result["gateway_id"] : null
}

output "gateway_name" {
  description = "Name of the GCP ZTGW."
  value       = var.deploy_ztgw ? data.external.ztgw[0].result["gateway_name"] : null
}

output "gateway_region" {
  description = "GCP region where the ZTGW is deployed."
  value       = var.deploy_ztgw ? data.external.ztgw[0].result["region"] : null
}

output "gateway_health_status" {
  description = "Health status of the GCP ZTGW."
  value       = var.deploy_ztgw ? data.external.ztgw[0].result["health_status"] : null
}

output "intercept_deployment_group" {
  description = "GCP NSI Intercept Deployment Group."
  value       = local.intercept_deployment_group
}

# ---------------------------------------------------------------------------
# Consumer-side outputs
# ---------------------------------------------------------------------------

output "firewall_policy_name" {
  description = "Created global network firewall policy name."
  value       = google_compute_network_firewall_policy.consumer.name
}

output "intercept_endpoint_group_id" {
  description = "Created intercept endpoint group resource ID."
  value       = google_network_security_intercept_endpoint_group.consumer.id
}

output "intercept_endpoint_group_association_id" {
  description = "Created intercept endpoint group association resource ID."
  value       = google_network_security_intercept_endpoint_group_association.consumer.id
}

output "security_profile_id" {
  description = "Created custom intercept security profile resource ID."
  value       = google_network_security_security_profile.custom_intercept.id
}

output "security_profile_group_id" {
  description = "Created security profile group resource ID."
  value       = google_network_security_security_profile_group.consumer.id
}
