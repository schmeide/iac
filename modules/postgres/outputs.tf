output "fqdn" {
  description = "Server FQDN. Resolves to the private address from inside the VNet only."
  value       = azurerm_postgresql_flexible_server.this.fqdn
}

output "administrator_login" {
  description = "Admin login name. The password is in the Key Vault secret named by admin_password_secret_name."
  value       = azurerm_postgresql_flexible_server.this.administrator_login
}

output "admin_password_secret_name" {
  description = "Key Vault secret holding the admin password."
  value       = azurerm_key_vault_secret.admin_password.name
}
