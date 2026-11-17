# Bootstrap

Two setup steps that have to happen before Terraform can do anything:

1. **`main.bicep`**: the Azure Storage account the root module keeps its state in.
2. **`github-oidc.bash`**: the Entra ID identity GitHub Actions authenticates as.

Both are one-time and idempotent. Both have been run for the `schmeide` subscription.

Every name is a parameter. `main.bicep` takes the location, resource group, storage account, container and SKU as
parameters with defaults; `main.bicepparam` sets the rest. `github-oidc.bash` takes `--subscription`, `--repo`,
`--app-name`, `--state-account`, `--state-rg` and `--environment`. The tenant is the one the subscription belongs to,
chosen by `az login --tenant <tenant-id>`. The subscription for `make bootstrap` is `BOOTSTRAP_SUB`, which defaults to
`SUBSCRIPTION`.

## Why this is Bicep and not Terraform

A Terraform backend has to exist before Terraform has anywhere to record what it built, so whatever creates the
backend cannot itself be a Terraform stack with a remote backend. `az deployment sub create` is idempotent and keeps
its own history in the subscription, so there is no state file to lose.

## What it creates

In the `schmeide` subscription:

| Resource | Name | Notes |
| --- | --- | --- |
| Resource group | `schmeide-tfstate` | |
| Storage account | `stschmeidetfstate` | `Standard_GRS`, TLS 1.2, no public blob access, no shared keys |
| Blob container | `tfstate` | private; one `.tfstate` blob per root module |
| Role assignment | Storage Blob Data Owner | for `principalId` in `main.bicepparam` |
| Management lock | `no-accidental-deletion` | `CanNotDelete` on the storage account |

`stschmeidetfstate` is global across Azure and was not checked for availability. If it is taken, change it in
`main.bicep`, `../azure/schmeide/backend.tf` and the `STATE_ACCOUNT` default in `github-oidc.bash`.

Blob versioning and 30-day blob and container soft delete are on, which is what makes a clobbered state file
recoverable.

## Step 1: deploy the state backend

Fill in `principalId` in `main.bicepparam` first (`az ad signed-in-user show --query id -o tsv`). It is marked
`PLACEHOLDER`.

```bash
make bootstrap/whatif   # preview
make bootstrap          # deploy
```

## Step 2: create the CI identity

`plan.yml` and `apply.yml` authenticate with OIDC, so there is no client secret. That needs an app registration with
federated credentials, which Bicep cannot create: app registrations are Microsoft Graph, not ARM.

```bash
./bootstrap/github-oidc.bash --help     # what it will do
./bootstrap/github-oidc.bash create
./bootstrap/github-oidc.bash doctor     # what exists now, and what is missing
```

It creates the `github-actions-schmeide-iac` app registration and service principal, three federated credentials
(`pull_request`, `ref:refs/heads/main`, `environment:production`), Contributor on the subscription, Storage Blob Data
Contributor on the state account, and Role Based Access Control Administrator on the subscription with a condition
that limits it to the four roles the Terraform assigns. It finishes by printing the `gh secret set` commands for
`AZURE_CLIENT_ID`, `AZURE_TENANT_ID` and `AZURE_SUBSCRIPTION_ID`. They are secrets so that Actions masks them in the
logs of this public repository; see "Secrets" in `README.md`.

The cluster module looks this service principal up by name (`github_actions_app_name`), so the name here and there
must match.

## Recovering a clobbered state file

```bash
STACK_KEY=azure/schmeide.tfstate

az storage blob list \
  --account-name stschmeidetfstate --container-name tfstate \
  --prefix "$STACK_KEY" --include v --auth-mode login \
  --query "[].{name:name, version:versionId, modified:properties.lastModified}" -o table

az storage blob copy start \
  --account-name stschmeidetfstate --destination-container tfstate \
  --destination-blob "$STACK_KEY" \
  --source-uri "https://stschmeidetfstate.blob.core.windows.net/tfstate/${STACK_KEY}?versionId=<version-id>" \
  --auth-mode login
```

A stale lease from an apply that died mid-flight is broken with `terraform force-unlock <lock-id>`.

## Deleting the account

The `CanNotDelete` lock has to come off by hand first:

```bash
az lock delete --name no-accidental-deletion \
  --resource-group schmeide-tfstate --resource-name stschmeidetfstate \
  --namespace Microsoft.Storage --resource-type storageAccounts
```
