# The schmeide virtual network: a subnet for AKS nodes, a subnet delegated to Azure
# Database for PostgreSQL flexible server, and the private DNS zone that server registers
# its address in. Address plan and sizing are in README.md.
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
  }
}
