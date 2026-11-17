# The schmeide AKS cluster: the platform (API, Temporal, Forgejo, sandbox pods, check
# Jobs) and every tenant's generated backends, one namespace per tenant. Also the Key
# Vault the cluster's workloads read secrets from, and the identities that tie them
# together. Argo CD and External Secrets are installed from the root module, not here.
#
# A shared module has no backend, so unlike a root module (where the terraform block lives
# in backend.tf) this module's terraform block lives in main.tf. The constraints are floors,
# not pins. The root module in azure/<subscription>/ is where versions actually get set.
terraform {
  required_version = ">= 1.16"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = ">= 5.0"
    }
    azuread = {
      source  = "hashicorp/azuread"
      version = ">= 3.0"
    }
  }
}

# Tenant id for the vault and for AKS Entra integration. This is the identity running
# terraform, which is fine for a tenant id and is the wrong principal to grant cluster
# admin. The GitHub Actions grants look the service principal up by name instead. See
# cluster.tf.
data "azurerm_client_config" "current" {}

locals {
  control_identity_name = "id-${var.name}-control"
  ingress_ip_name       = "pip-${var.name}-ingress"
}
