# The control-plane identity has to be able to join the node subnet before the cluster is
# created. The cluster depends_on this assignment for that reason. Scoped to the subnet.
resource "azurerm_role_assignment" "control_network" {
  scope                            = var.nodes_subnet_id
  role_definition_name             = "Network Contributor"
  principal_id                     = azurerm_user_assigned_identity.control.principal_id
  principal_type                   = "ServicePrincipal"
  skip_service_principal_aad_check = true
}
