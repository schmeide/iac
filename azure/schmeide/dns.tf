# The apps.schmeide.com zone, where built apps get their hosts (schmeide.app's
# docs/stage2.md, "Previews and domains"). schmeide.com itself stays at Porkbun and is not
# managed here; the owner delegates only the apps label to this zone's name servers
# (README.md, "DNS").
resource "azurerm_dns_zone" "apps" {
  name                = "apps.schmeide.com"
  resource_group_name = azurerm_resource_group.network.name
  tags                = local.tags
}

# An alias to Traefik's static IP rather than its address, so the record follows the
# resource.
resource "azurerm_dns_a_record" "apps_wildcard" {
  name                = "*"
  zone_name           = azurerm_dns_zone.apps.name
  resource_group_name = azurerm_dns_zone.apps.resource_group_name
  ttl                 = 300
  target_resource_id  = module.cluster.ingress_ip_id
  tags                = local.tags
}

# cert-manager's identity, for DNS-01 on that zone: the letsencrypt-dns ClusterIssuer in
# gitops/schmeide/apps/cluster-issuer-dns.jsonnet. Same shape as the gitops identity in
# gitops.tf, including the replacement on a tenant change.
resource "azurerm_user_assigned_identity" "cert_manager" {
  name                = "id-schmeide-cert-manager"
  resource_group_name = azurerm_resource_group.cluster.name
  location            = var.location
  tags                = local.tags

  lifecycle {
    replace_triggered_by = [terraform_data.tenant]
  }
}

# gitops/schmeide/cert-manager/values.yaml names the service account explicitly, so this
# subject cannot drift from a chart helper change.
resource "azurerm_federated_identity_credential" "cert_manager" {
  name                      = "cert-manager"
  user_assigned_identity_id = azurerm_user_assigned_identity.cert_manager.id
  audience                  = ["api://AzureADTokenExchange"]
  issuer                    = module.cluster.oidc_issuer_url
  subject                   = "system:serviceaccount:cert-manager:cert-manager"
}

# This zone only. bootstrap/github-oidc.bash allow-lists the role for CI.
resource "azurerm_role_assignment" "cert_manager_dns" {
  scope                            = azurerm_dns_zone.apps.id
  role_definition_name             = "DNS Zone Contributor"
  principal_id                     = azurerm_user_assigned_identity.cert_manager.principal_id
  principal_type                   = "ServicePrincipal"
  skip_service_principal_aad_check = true
}
