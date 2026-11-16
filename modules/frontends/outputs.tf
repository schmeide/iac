output "storage_account_id" {
  description = "ARM id of the account. A writer role for the platform's deploy identity, and later a CDN origin, attach here."
  value       = azurerm_storage_account.this.id
}

output "bundles_container_url" {
  description = "HTTPS URL of the private bundles container."
  value       = "${azurerm_storage_account.this.primary_blob_endpoint}${azurerm_storage_container.bundles.name}"
}
