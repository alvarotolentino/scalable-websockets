terraform {
  required_version = ">= 1.5"
  required_providers {
    latitudesh = {
      source  = "latitudesh/latitudesh"
      version = ">= 2.5.0"
    }
  }
}

provider "latitudesh" {
  # Authenticates via LATITUDESH_AUTH_TOKEN environment variable.
}
