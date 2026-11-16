# 10.16.0.0/16. Not 10.0.0.0/16 or 10.8.0.0/16, which autobutler-org/iac uses. Those
# networks are not peered with this one, and keeping the ranges apart keeps a later
# peering possible. See README.md for the full address plan.
resource "azurerm_virtual_network" "this" {
  name                = "${var.name_prefix}-vnet"
  resource_group_name = var.resource_group_name
  location            = var.location
  address_space       = [var.address_space]
  tags                = var.tags
}

# AKS nodes and the internal load balancer addresses the cluster creates. Azure CNI
# overlay takes pod addresses from the cluster's pod CIDR, not from here, so a node costs
# one address. A /20 holds about 4,000 nodes.
resource "azurerm_subnet" "nodes" {
  name                 = "nodes"
  resource_group_name  = var.resource_group_name
  virtual_network_name = azurerm_virtual_network.this.name
  address_prefixes     = [var.nodes_subnet_prefix]
}

# Delegated to PostgreSQL flexible server, which is the only thing the subnet may hold.
# One server uses one address, and a standby or read replica one more each. A /24 leaves
# room for those and for a second server if the platform databases ever move off the
# shared one.
resource "azurerm_subnet" "postgres" {
  name                 = "postgres"
  resource_group_name  = var.resource_group_name
  virtual_network_name = azurerm_virtual_network.this.name
  address_prefixes     = [var.postgres_subnet_prefix]

  delegation {
    name = "postgres-flexible-server"

    service_delegation {
      name = "Microsoft.DBforPostgreSQL/flexibleServers"
      actions = [
        "Microsoft.Network/virtualNetworks/subnets/join/action",
      ]
    }
  }
}
