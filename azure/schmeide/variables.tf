# PLACEHOLDER: the schmeide subscription and its tenant do not exist yet. No default on
# purpose: a missing value fails the plan rather than touching some other subscription.
# `make` sets both from `az account show --subscription schmeide`. CI gets the same values
# from the AZURE_SUBSCRIPTION_ID and AZURE_TENANT_ID repository variables through
# azure/login. For bare terraform, copy terraform.tfvars.example to terraform.tfvars
# (gitignored) and fill it in.
variable "subscription_id" {
  description = "ID of the schmeide Azure subscription. Required, no default. See terraform.tfvars.example."
  type        = string

  validation {
    condition     = can(regex("^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$", var.subscription_id))
    error_message = "subscription_id must be a lowercase GUID. Get it with: az account show --subscription schmeide --query id -o tsv"
  }
}

variable "tenant_id" {
  description = "ID of the Entra ID tenant that holds the schmeide subscription. Required, no default. See terraform.tfvars.example."
  type        = string

  validation {
    condition     = can(regex("^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$", var.tenant_id))
    error_message = "tenant_id must be a lowercase GUID. Get it with: az account show --subscription schmeide --query tenantId -o tsv"
  }
}

variable "location" {
  description = "Default Azure region for resources in this subscription."
  type        = string
  default     = "eastus"
}

variable "tags" {
  description = "Extra tags merged over the defaults in main.tf and applied to everything here."
  type        = map(string)
  default     = {}
}
