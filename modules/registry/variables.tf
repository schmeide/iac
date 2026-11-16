variable "name" {
  description = "Globally unique registry name, 5-50 alphanumerics. Becomes <name>.azurecr.io."
  type        = string
}

variable "resource_group_name" {
  description = "Existing resource group to create the registry in. The caller owns its lifecycle."
  type        = string
}

variable "location" {
  description = "Azure region for the registry. Same as the cluster, so pulls stay in region."
  type        = string
  default     = "centralus"
}

variable "sku" {
  description = "Registry SKU. Basic is enough for a demo; Premium is what private endpoints and geo-replication need."
  type        = string
  default     = "Basic"
}

variable "tags" {
  description = "Tags applied to every resource this module manages."
  type        = map(string)
  default     = {}
}
