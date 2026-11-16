# The one shared Azure Database for PostgreSQL flexible server: a database per project,
# created by the platform at runtime, plus the platform's own databases, which are here.
# Private access only, in the delegated subnet from modules/network.
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
    random = {
      source  = "hashicorp/random"
      version = ">= 3.7"
    }
  }
}
