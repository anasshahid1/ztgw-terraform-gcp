terraform {
  required_version = ">= 1.5.0"

  required_providers {
    ztc = {
      source  = "zscaler/ztc"
      version = ">= 0.1.0"
    }

    google = {
      source  = "hashicorp/google"
      version = ">= 7.27.0, < 8.0.0"
    }

    google-beta = {
      source  = "hashicorp/google-beta"
      version = ">= 7.27.0, < 8.0.0"
    }
  }
}
