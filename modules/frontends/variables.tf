variable "name" {
  description = "Globally unique storage account name, 3-24 lowercase alphanumerics."
  type        = string
}

variable "resource_group_name" {
  description = "Existing resource group to create the account in. The caller owns its lifecycle."
  type        = string
}

variable "location" {
  description = "Azure region for the account."
  type        = string
  default     = "eastus"
}

variable "tags" {
  description = "Tags applied to every resource this module manages."
  type        = map(string)
  default     = {}
}
