# Shared Terragrunt configuration for all apps/ modules.
#
# Include this alongside root.hcl in each app's terragrunt.hcl:
#
#   include "root" {
#     path = find_in_parent_folders("root.hcl")
#   }
#   include "apps" {
#     path = find_in_parent_folders("common.hcl")
#   }
#
# This declares the baseline dependencies every app module needs:
#   - vault/      Vault is configured (KV engine, auth backend, policies)
#   - vault-helm/ ESO and ClusterSecretStore are deployed

dependencies {
  paths = [
    "${get_terragrunt_dir()}/../../vault",
    "${get_terragrunt_dir()}/../../vault-helm",
  ]
}
