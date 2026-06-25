# Zscaler Zero Trust Cloud (ZTC) provider
provider "ztc" {
  client_id     = var.client_id
  client_secret = var.client_secret
  vanity_domain = var.vanity_domain
  cloud         = var.cloud
}

# Google Cloud provider
provider "google" {
  project               = var.project_id
  region                = var.region
  billing_project       = var.billing_project_id
  user_project_override = true
}

# Google Cloud Beta provider (required for NSI resources)
provider "google-beta" {
  project               = var.project_id
  region                = var.region
  billing_project       = var.billing_project_id
  user_project_override = true
}
