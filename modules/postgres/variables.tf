variable "name" {
  description = "Globally unique server name. The FQDN is <name>.postgres.database.azure.com."
  type        = string
}

variable "resource_group_name" {
  description = "Existing resource group to create the server in. The caller owns its lifecycle."
  type        = string
}

variable "location" {
  description = "Azure region for the server. Must match the VNet the delegated subnet is in."
  type        = string
  default     = "centralus"
}

variable "postgres_version" {
  description = "PostgreSQL major version."
  type        = string
  default     = "17"
}

variable "sku_name" {
  description = "Compute SKU, <tier>_<size>. B_ is Burstable, GP_ General Purpose."
  type        = string
  default     = "B_Standard_B2s"
}

variable "storage_mb" {
  description = "Allocated storage in MiB. Auto-grow is on, so this is the starting size."
  type        = number
  default     = 32768
}

variable "backup_retention_days" {
  description = "Point-in-time restore window, 7-35 days. Backups are always on; this sets how far back they reach."
  type        = number
  default     = 7
}

variable "delegated_subnet_id" {
  description = "Subnet delegated to Microsoft.DBforPostgreSQL/flexibleServers."
  type        = string
}

variable "private_dns_zone_id" {
  description = "Private DNS zone ending in postgres.database.azure.com, already linked to the VNet."
  type        = string
}

variable "administrator_login" {
  description = "Admin login name. The password is generated, never set here."
  type        = string
  default     = "schmeideadmin"
}

variable "administrator_password_version" {
  description = "Bump to rotate the admin password. The next apply generates a new one and writes it to the server and the vault."
  type        = number
  default     = 1
}

variable "key_vault_id" {
  description = "Key Vault the admin password is written to. The apply identity needs Set on it."
  type        = string
}

variable "key_vault_secret_name" {
  description = "Name of the Key Vault secret holding the admin password."
  type        = string
  default     = "postgres-admin-password"
}

variable "databases" {
  description = "Platform databases to create. Per-project databases are created by the platform at runtime, not here."
  type        = list(string)
}

variable "tags" {
  description = "Tags applied to every resource this module manages."
  type        = map(string)
  default     = {}
}
