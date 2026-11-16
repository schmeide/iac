output "vnet_id" {
  description = "ARM id of the virtual network."
  value       = azurerm_virtual_network.this.id
}

output "nodes_subnet_id" {
  description = "Subnet the AKS node pools join. The cluster's control-plane identity needs Network Contributor here."
  value       = azurerm_subnet.nodes.id
}

output "postgres_subnet_id" {
  description = "Subnet delegated to PostgreSQL flexible server."
  value       = azurerm_subnet.postgres.id
}

output "postgres_private_dns_zone_id" {
  description = "Private DNS zone the PostgreSQL server registers in. Depends on the VNet link, so a server created from this output waits for it."
  value       = azurerm_private_dns_zone.postgres.id

  # A server created in a zone that is not yet linked to its VNet fails to provision.
  depends_on = [azurerm_private_dns_zone_virtual_network_link.postgres]
}
