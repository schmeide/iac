using './main.bicep'

// Defaults in main.bicep cover location, names and SKU. Every one of them is a parameter,
// so a different name (say, if stschmeidetfstate turns out to be taken) is a line here,
// not an edit to the template. The storage account name is global across Azure and was not
// checked for availability, because nothing here calls Azure before the subscription exists.

// PLACEHOLDER: object ID granted Storage Blob Data Owner on the state account, so the
// person running Terraform can read, write and lease the state blobs. Empty skips the
// role assignment. Fill it in before `make bootstrap`. Find your own with:
//   az ad signed-in-user show --query id -o tsv
// The CI service principal does not go here: bootstrap/github-oidc.bash grants it
// Storage Blob Data Contributor on its own.
param principalId = ''
