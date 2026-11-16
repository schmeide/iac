# `frontends` module

A storage account for generated frontends. Each project's frontend is a static bundle, built by the platform and
uploaded here, then served to visitors through a CDN.

**The CDN service is not decided.** Front Door is the obvious Azure choice, but the planning repo leaves it open, so
nothing here serves traffic yet. Choosing it also decides how the CDN reads the bundles: through the account's static
website endpoint, or as a private origin it authenticates to. The account is laid out so either works.

## Layout

One private container, `bundles`, with one prefix per build:

```text
bundles/<tenant>/<project>/<build>/index.html
```

A deploy uploads a new `<build>/` prefix and then points the project's CDN route at it. Nothing is overwritten in
place, so a rollback is a route change and a CDN purge is never a correctness issue.

## Access

Shared keys are off, so every writer authenticates with Entra ID. The platform's deploy step will need its own identity
with Storage Blob Data Contributor on this account; that grant is not here yet, because the deploy step does not
exist. Adding it means adding Storage Blob Data Contributor to the bootstrap script's role allow list.
