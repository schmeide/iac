# Attaches the registry: the kubelet identity, which AKS creates, can pull. The registry
# uses ABAC repository permissions, where AcrPull is not honored, so the role is
# Container Registry Repository Reader. The kubelet identity may not have replicated
# through Entra when this is written, so the AAD check is skipped. Push is not granted.
resource "azurerm_role_assignment" "kubelet_acr" {
  scope                            = var.registry_id
  role_definition_name             = "Container Registry Repository Reader"
  principal_id                     = azurerm_kubernetes_cluster.this.kubelet_identity[0].object_id
  principal_type                   = "ServicePrincipal"
  skip_service_principal_aad_check = true
}
