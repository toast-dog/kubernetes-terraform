# ArgoCD AppProjects — one per app, created by Terraform so they exist before
# any child Application is synced. The root Application stays in "default".
#
# Each project locks down:
#   sourceRepos              — which repos/registries that app is allowed to pull from
#   destinations             — which namespace(s) that app is allowed to deploy into
#   clusterResourceWhitelist — which cluster-scoped resource types are allowed
#                              (derived by cross-referencing `helm template | grep "^kind:"``
#                               with `kubectl api-resources --namespaced=false`)

resource "kubernetes_manifest" "argocd_project_cloudnativepg" {
  manifest = {
    apiVersion = "argoproj.io/v1alpha1"
    kind       = "AppProject"
    metadata = {
      name      = "cloudnativepg"
      namespace = "argocd"
    }
    spec = {
      description = "CloudNativePG operator"
      sourceRepos = ["https://cloudnative-pg.github.io/charts"]
      destinations = [{
        namespace = "cnpg-system"
        server    = "https://kubernetes.default.svc"
      }]
      clusterResourceWhitelist = [
        { group = "",                              kind = "Namespace"                      },
        { group = "apiextensions.k8s.io",          kind = "CustomResourceDefinition"      },
        { group = "rbac.authorization.k8s.io",     kind = "ClusterRole"                   },
        { group = "rbac.authorization.k8s.io",     kind = "ClusterRoleBinding"            },
        { group = "admissionregistration.k8s.io",  kind = "MutatingWebhookConfiguration"  },
        { group = "admissionregistration.k8s.io",  kind = "ValidatingWebhookConfiguration" },
      ]
    }
  }
}
