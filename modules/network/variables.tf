variable "name_prefix" {
  description = "Prefix for the VNet and the DNS zone link names."
  type        = string
}

variable "resource_group_name" {
  description = "Existing resource group to create the network in. The caller owns its lifecycle."
  type        = string
}

variable "location" {
  description = "Azure region for the VNet."
  type        = string
  default     = "centralus"
}

variable "address_space" {
  description = "VNet address space. Must not overlap the cluster's pod or service CIDR. See README.md."
  type        = string
  default     = "10.16.0.0/16"
}

variable "nodes_subnet_prefix" {
  description = "Subnet for AKS nodes. With Azure CNI overlay a node takes one address here."
  type        = string
  default     = "10.16.0.0/20"
}

variable "postgres_subnet_prefix" {
  description = "Subnet delegated to PostgreSQL flexible server."
  type        = string
  default     = "10.16.16.0/24"
}

variable "tags" {
  description = "Tags applied to every resource this module manages."
  type        = map(string)
  default     = {}
}
