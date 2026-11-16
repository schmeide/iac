# Terraform Coding Standards

This repository is the Azure infrastructure for Schmeide: Terraform against the `azurerm` provider, a Bicep template
in `bootstrap/` that creates the storage account Terraform keeps its state in, and the Argo CD manifests in `gitops/`.
There is no application code here.

The layout and conventions are those of [autobutler-org/iac](https://github.com/autobutler-org/iac). When this file is
silent, do what that repo does.

## Read `README.md` first

`README.md` is the design record: why a subscription is a directory, where state lives, how secrets stay out of state,
and the checklist for bringing the `schmeide` subscription online. `bootstrap/README.md` covers the state backend and
the CI identity. `gitops/README.md` covers what Argo CD installs and every placeholder still to fill in.

## The subscription is live

Everything is applied, in `centralus`; `README.md`, "Current state", has what runs and what is still open.
Do not run `make apply-*`, `make bootstrap` or any `az` command that changes Azure unless the user asks for it in that
message. Changes reach Azure through a merge to `main`. `make check` needs no Azure access and is always safe.

## File layout

```text
azure/<subscription>/     one Azure subscription, one root module, one state file
modules/<name>/           shared modules, referenced with a relative source
bootstrap/                Bicep for the terraform state backend, and the CI identity script
gitops/<subscription>/    Argo CD Applications and manifests, and Helm values beside them
```

**Every directory under `azure/` is an Azure subscription.** The Makefile turns the directory name into
`ARM_SUBSCRIPTION_ID`, `ARM_TENANT_ID` and the `subscription_id` and `tenant_id` variables, so the path decides which
subscription gets touched. Never put a non-subscription directory under `azure/`.

Inside a module, each resource type gets its own file, named after the type minus the provider prefix: every
`azurerm_storage_account` goes in `storage.tf`, every `azurerm_virtual_network` in `network.tf`. Supporting files stay
single-purpose:

- `backend.tf`: the `terraform` block for a **root** module: `required_version`, `required_providers`, and the
  `backend "azurerm"` block.
- `main.tf`: `locals` in a root module; the `terraform` block in a **shared** module, which has no backend.
- `providers.tf`: provider blocks.
- `variables.tf`, `outputs.tf`, `imports.tf` (`import` blocks).

In the root module, each component gets one file that creates its resource group and calls its module
(`cluster.tf`, `postgres.tf`, ...). There is no empty file. If a file would have nothing in it, do not create it.

Shared modules declare version constraints as floors (`>= 5.0`), not pins; the root module pins.

## Use the Makefile, not bare `terraform`

Every command lives in the root `Makefile`, run from the repo root:

```bash
make                                   # help: every target, with descriptions
make init                              # terraform init -reconfigure
make plan                              # writes planfile.tfplan
make check                             # format + lint + markdown + bicep + validate; no credentials
make check/validate                    # init -backend=false + validate; no credentials
make plan/show                         # print the planfile in readable form
make lock                              # regenerate the four-platform provider lock
make bootstrap/whatif                  # preview the state backend deployment
make bootstrap                         # create the state backend (once, before anything)
```

The Makefile needs GNU Make 3.82+ for `.ONESHELL:`. macOS ships 3.81 as `/usr/bin/make`, so use `gmake` there.

`SUBSCRIPTION` defaults to `schmeide`, the only one.

Everything that talks to Azure needs `az login`; the `az-login` guard says so. `check/*` and `plan/show` need no
credentials.

`make plan` does not fail on exit code 2 (changes present with `-detailed-exitcode`), and always passes `-lock=false`.
The apply targets do not; an apply must lock.

## Variables and secrets

`subscription_id` and `tenant_id` are required root variables with no defaults. `make` and CI fill them through
`TF_VAR_*`. For bare terraform, copy `azure/schmeide/terraform.tfvars.example` to `terraform.tfvars`, which is
gitignored. Never commit a real subscription or tenant ID: this repo is public.

Never put a secret in a variable, an output, or a resource argument that is stored in state. Generate it with an
ephemeral resource and send it through a write-only argument (`*_wo` with a `*_wo_version`), as
`modules/postgres/key_vault.tf` does, or have a person set it in Key Vault by hand.

## CI

| Workflow | Trigger | What it does |
| --- | --- | --- |
| `check.yml` | PR to `main`, push to `main`, manual | `make check/format`, `check/lint`, `check/markdown`, `check/bicep`, `check/validate` |
| `plan.yml` | PR to `main`, `workflow_call` | `make init` + `make plan`; uploads the planfile and posts the plan to the summary and a PR comment |
| `apply.yml` | push to `main`, manual | calls `plan.yml`, then `make apply-from-planfile` on that planfile |
| `codeql.yml` | PR to `main`, push to `main`, weekly, manual | CodeQL on the `actions` language only |

`plan.yml` and `apply.yml` are gated on the `AZURE_ENABLED` repository variable and show as skipped until it is
`true`. Keep that gate on every job that reaches Azure. `check.yml` needs no Azure credentials; keep it that way.

Authentication is OIDC via `azure/login`. `AZURE_CLIENT_ID`, `AZURE_TENANT_ID` and `AZURE_SUBSCRIPTION_ID` are
repository variables. No workflow reads an Actions secret.

## Dependency updates

Renovate, configured entirely in `renovate.json` (no shared preset). It needs the Renovate GitHub App installed on the
repo. When it bumps a Terraform provider, check that `.terraform.lock.hcl` still has four `h1:` hashes per provider;
if it shrank, run `make lock` on the branch.

## Plan locally, apply through CI

State is shared. Apply from `main` through CI, where every change has been reviewed. `make apply-from-source`,
`make apply-from-planfile` and `make destroy` exist for CI and for recovery.

## Never commit

`*.tfplan`, `generated.tf`, `.terraform/`, `*override.tf.json`, `terraform.tfvars`, and anything matching
`*.tfstate*`. All are in `.gitignore`. If you see an `errored.tfstate`, tell the user rather than deleting it.

`.terraform.lock.hcl` **is** committed and covers `linux_amd64`, `linux_arm64`, `darwin_amd64` and `darwin_arm64`.
Regenerate it with `make lock`, never a plain `terraform init`.

## Linting

`.tflint.hcl` runs the full `terraform` ruleset plus the `azurerm` ruleset with the strict rules on. Do not disable a
rule to make a change pass; fix the code. `azurerm_resources_missing_prevent_destroy` will fire on anything holding
data, and `lifecycle { prevent_destroy = true }` is usually the answer.

Markdown is linted by `markdownlint-cli2` against `.markdownlint.yaml` (`make check/markdown`), pinned in
`package.json` and installed with `npm ci`.

## Placeholders

Anything that depends on a choice not yet made is marked `PLACEHOLDER` in a comment, and listed in `README.md` or
`gitops/README.md`. Keep both in step: add to the list when you add a placeholder, and remove from it when you fill one.

## Maintaining this document

**AGENTS.md** is the rules and the commands, **README.md** is the reasoning. Update this file when you add a Makefile
target, change the credential flow, add a linter rule, or introduce a new convention.
