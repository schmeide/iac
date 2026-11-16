output "id" {
  description = "ARM id of the registry. The cluster module grants its kubelet pull here."
  value       = azurerm_container_registry.this.id
}

output "login_server" {
  description = "Registry login server, <name>.azurecr.io."
  value       = azurerm_container_registry.this.login_server
}
