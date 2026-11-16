# A server with private access publishes its address in a private DNS zone, whose name
# must end in .postgres.database.azure.com. The privatelink. zone is left free for private
# endpoints. Linking the zone to the VNet is what lets pods resolve the server's FQDN to its
# private address.
resource "azurerm_private_dns_zone" "postgres" {
  name                = "${var.name_prefix}.private.postgres.database.azure.com"
  resource_group_name = var.resource_group_name
  tags                = var.tags
}

resource "azurerm_private_dns_zone_virtual_network_link" "postgres" {
  name                 = "${var.name_prefix}-vnet"
  private_dns_zone_id  = azurerm_private_dns_zone.postgres.id
  virtual_network_id   = azurerm_virtual_network.this.id
  registration_enabled = false
  tags                 = var.tags
}
