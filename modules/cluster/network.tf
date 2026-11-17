# The control-plane identity has to be able to join the node subnet before the cluster is
# created. The cluster depends_on this assignment for that reason. Scoped to the subnet.
resource "azurerm_role_assignment" "control_network" {
  scope                            = var.nodes_subnet_id
  role_definition_name             = "Network Contributor"
  principal_id                     = azurerm_user_assigned_identity.control.principal_id
  principal_type                   = "ServicePrincipal"
  skip_service_principal_aad_check = true
}

# Traefik's LoadBalancer Service takes this address by name (gitops/schmeide/traefik
# values.yaml), so api.schmeide.app can point at an IP that outlives redeploys and node
# pool changes. Kept in the cluster's resource group, not the AKS-managed node group,
# which AKS deletes with the cluster. prevent_destroy: a new address breaks the DNS
# record at the registrar until someone edits it by hand.
resource "azurerm_public_ip" "ingress" {
  name                = local.ingress_ip_name
  resource_group_name = var.resource_group_name
  location            = var.location
  sku                 = "Standard"
  allocation_method   = "Static"
  tags                = var.tags

  lifecycle {
    prevent_destroy = true
  }
}

# Outside the node resource group, the cloud provider acts as the control-plane identity
# and needs to read and join the address. It lists public IPs at the resource-group level
# (Microsoft.Network/publicIPAddresses/read on .../resourceGroups/<rg>/providers/
# Microsoft.Network), so a grant on the address alone fails with AuthorizationFailed.
# Scoped to the cluster's resource group, as the AKS static-IP docs prescribe.
data "azurerm_resource_group" "cluster" {
  name = var.resource_group_name
}

resource "azurerm_role_assignment" "control_ingress_ip" {
  scope                            = data.azurerm_resource_group.cluster.id
  role_definition_name             = "Network Contributor"
  principal_id                     = azurerm_user_assigned_identity.control.principal_id
  principal_type                   = "ServicePrincipal"
  skip_service_principal_aad_check = true
}
