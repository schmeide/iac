# subscription_id and tenant_id are required variables with no defaults, because the
# schmeide subscription does not exist yet and no ID is committed to this public repo.
# `make` fills them from the directory name (TF_VAR_subscription_id and TF_VAR_tenant_id,
# see the Makefile's arm_subscription). Running terraform directly needs a
# terraform.tfvars copied from terraform.tfvars.example.
provider "azurerm" {
  subscription_id = var.subscription_id
  tenant_id       = var.tenant_id

  features {}
}

# Same Azure CLI or OIDC login as azurerm. No separate credential.
provider "azuread" {
  tenant_id = var.tenant_id
}

# kubelogin, not a client certificate. local_account_disabled means the cluster does not
# issue an admin kubeconfig, so the Helm provider cannot use client_certificate or
# client_key. host and the CA come from the cluster module. The CA attribute is base64,
# and the provider wants PEM. The server id is the well-known AKS Microsoft Entra app.
provider "helm" {
  kubernetes = {
    host                   = module.cluster.cluster_host
    cluster_ca_certificate = base64decode(module.cluster.cluster_ca_certificate)
    exec = {
      api_version = "client.authentication.k8s.io/v1beta1"
      command     = "kubelogin"
      args = [
        "get-token",
        "--login",
        "azurecli",
        "--server-id",
        "6dae42f8-4368-4678-94ff-3960e28e3630",
      ]
    }
  }
}
