// Let's Encrypt production, DNS-01 on the apps.schmeide.com Azure DNS zone, for the
// wildcard Certificate in apps-wildcard-certificate.yaml. HTTP-01 cannot issue a wildcard;
// cluster-issuer.yaml stays for api.schmeide.app.
//
// Jsonnet, not YAML, because the identity's client id and the subscription id come from
// terraform and the repository does not commit them: azure/schmeide/gitops.tf passes them
// to the root Application as the top-level argument certManager. Until it has, this
// renders nothing.
//
// cert-manager authenticates as id-schmeide-cert-manager through workload identity
// (gitops/schmeide/cert-manager/values.yaml), which holds DNS Zone Contributor on this
// zone only.
function(certManager={})
  if std.length(certManager) == 0 then [] else [
    {
      apiVersion: 'cert-manager.io/v1',
      kind: 'ClusterIssuer',
      metadata: {
        name: 'letsencrypt-dns',
        annotations: {
          'argocd.argoproj.io/sync-wave': '1',
          // The ClusterIssuer CRD arrives with cert-manager in the same sync.
          'argocd.argoproj.io/sync-options': 'SkipDryRunOnMissingResource=true',
        },
      },
      spec: {
        acme: {
          server: 'https://acme-v02.api.letsencrypt.org/directory',
          privateKeySecretRef: {
            name: 'letsencrypt-dns-account-key',
          },
          solvers: [
            {
              dns01: {
                azureDNS: {
                  environment: 'AzurePublicCloud',
                  subscriptionID: certManager.subscriptionId,
                  resourceGroupName: certManager.resourceGroup,
                  hostedZoneName: certManager.zone,
                  managedIdentity: {
                    clientID: certManager.clientId,
                  },
                },
              },
            },
          ],
        },
      },
    },
  ]
