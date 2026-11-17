output "cluster_name" {
  description = "AKS cluster name."
  value       = azurerm_kubernetes_cluster.this.name
}

output "cluster_id" {
  description = "ARM id of the AKS cluster."
  value       = azurerm_kubernetes_cluster.this.id
}

output "oidc_issuer_url" {
  description = "OIDC issuer URL of the cluster. Federated credentials for workload identity use this as the issuer."
  value       = azurerm_kubernetes_cluster.this.oidc_issuer_url
}

output "key_vault_id" {
  description = "ARM id of the platform Key Vault. Taken from the apply identity's access policy, so a secret written through this id waits until terraform can write it."
  value       = azurerm_key_vault_access_policy.github_actions.key_vault_id
}

output "key_vault_name" {
  description = "Name of the platform Key Vault."
  value       = azurerm_key_vault.this.name
}

output "key_vault_uri" {
  description = "Vault URI, which External Secrets' ClusterSecretStore points at."
  value       = azurerm_key_vault.this.vault_uri
}

output "cluster_host" {
  description = "Kubernetes API host for a Helm provider. Connection info, not a client credential."
  value       = azurerm_kubernetes_cluster.this.kube_config[0].host
  sensitive   = true
}

output "cluster_ca_certificate" {
  description = "Base64 cluster CA certificate for a Helm provider. The azurerm provider marks the attribute sensitive. It is not a client credential."
  value       = azurerm_kubernetes_cluster.this.kube_config[0].cluster_ca_certificate
  sensitive   = true
}

output "ingress_ip_address" {
  description = "Static public IP Traefik's LoadBalancer Service is pinned to. DNS A records for the cluster point here."
  value       = azurerm_public_ip.ingress.ip_address
}

output "ingress_ip_id" {
  description = "ARM id of that public IP, for DNS alias records that follow it."
  value       = azurerm_public_ip.ingress.id
}
