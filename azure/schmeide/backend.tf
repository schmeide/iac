terraform {
  # Pinned to the minor, as in autobutler-org/iac. The whole repo runs one terraform
  # version, and CI reading a different one than a developer's desk is a class of bug worth
  # spending a pin to avoid. Ephemeral resources and write-only arguments, which the
  # Postgres and Forgejo passwords use, need 1.11 or later.
  required_version = "~> 1.16"

  # One state file for the schmeide subscription, kept in that same subscription.
  #
  # The account is created by bootstrap/main.bicep. See bootstrap/README.md.
  #
  # subscription_id and tenant_id are deliberately absent. They are not known yet, and a
  # backend block cannot take variables. The azurerm backend reads ARM_SUBSCRIPTION_ID and
  # ARM_TENANT_ID instead, which `make init` exports from the directory name and which
  # azure/login exports in CI. Once the IDs exist they may be written here as literals,
  # the way autobutler-org/iac does, but nothing requires it.
  #
  # use_azuread_auth: the state account sets allowSharedKeyAccess=false, so there is no
  # account key to look up and `resource_group_name` is deliberately omitted. That
  # argument exists only to drive the key lookup. Access is RBAC (Storage Blob Data Owner
  # or Contributor), and state locking is a native blob lease, so there is no lock table.
  backend "azurerm" {
    storage_account_name = "stschmeidetfstate"
    container_name       = "tfstate"
    key                  = "azure/schmeide.tfstate"
    use_azuread_auth     = true
  }

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 5.0"
    }
    # The cluster module looks up the CI service principal by name, so a local plan does
    # not grant cluster admin to whoever ran it.
    azuread = {
      source  = "hashicorp/azuread"
      version = "~> 3.0"
    }
    # Helm installs Argo CD and External Secrets. Auth is kubelogin, not the AKS admin
    # certificate. See providers.tf.
    helm = {
      source  = "hashicorp/helm"
      version = "~> 3.0"
    }
    # Ephemeral passwords for Postgres and the Forgejo admin. Ephemeral, so the value is
    # never in state or in the planfile. See modules/postgres/key_vault.tf.
    random = {
      source  = "hashicorp/random"
      version = "~> 3.7"
    }
  }
}
