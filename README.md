# apbs-deploy-azure
This repo holds OpenTofu modules for deploying pdb2pqr and apbs on Azure.

## Repo structure
```
─ container-apps -> Containerized applications
  └── apbs -> The main job runner
─ deploy -> Deployment scripts using OpenTofu
  ├── backend -> Backend deployment
  └── registry -> Registry deployment
─ modules
  ├── apbs-backend -> Modules used for deploying the backend
  │   ├── storage -> Used to abstract storage containes
  │   ├── storage-account -> Storage account module
  │   ├── container-app -> Manages the container app deployment
  ├── apbs-web
  │   ├── cdn -> CDN module (not used, but kept for reference)
  │   ├── github_oidc -> GitHub OIDC module (not used, but kept for reference)
  │   └── static_site -> Static site module (not used, but kept for reference)
  └── registry -> Azure Container Registry module
```

## Prerequisites
To get started, you will need to setup a storage backend to hold the state of this project. This should be done first.
To do this, follow the instructions found [here](https://learn.microsoft.com/en-us/azure/developer/terraform/store-state-in-azure-storage?tabs=azure-cli). Since storage accounts are globally unique, you will also need to update the backend configuration in both the `backend` and `registry` modules.

You will additionally want to setup a deployment role that looks something like this:
```json
{
    "properties": {
        "roleName": "TerraformDeploy",
        "description": "",
        "assignableScopes": [],
        "permissions": [
            {
                "actions": [
                    "Microsoft.Resources/subscriptions/resourceGroups/read",
                    "Microsoft.Resources/subscriptions/resourceGroups/write",
                    "Microsoft.Resources/deployments/*",
                    "Microsoft.ServiceBus/namespaces/*",
                    "Microsoft.ServiceBus/namespaces/queues/*",
                    "Microsoft.ServiceBus/namespaces/topics/*",
                    "Microsoft.ServiceBus/namespaces/authorizationRules/*",
                    "Microsoft.Network/frontdoors/*",
                    "Microsoft.Network/frontdoorWebApplicationFirewallPolicies/*",
                    "Microsoft.Cdn/profiles/*",
                    "Microsoft.Cdn/profiles/endpoints/*",
                    "Microsoft.Storage/storageAccounts/*",
                    "Microsoft.Storage/operations/read",
                    "Microsoft.Storage/checkNameAvailability/read",
                    "Microsoft.ServiceBus/register/action",
                    "Microsoft.Network/register/action",
                    "Microsoft.Storage/register/action",
                    "Microsoft.Authorization/roleAssignments/*",
                    "Microsoft.ManagedIdentity/userAssignedIdentities/read",
                    "Microsoft.ManagedIdentity/userAssignedIdentities/write",
                    "Microsoft.ManagedIdentity/userAssignedIdentities/federatedIdentityCredentials/read",
                    "Microsoft.ManagedIdentity/userAssignedIdentities/federatedIdentityCredentials/write",
                    "Microsoft.ManagedIdentity/userAssignedIdentities/federatedIdentityCredentials/delete",
                    "Microsoft.ManagedIdentity/userAssignedIdentities/delete",
                    "Microsoft.ManagedIdentity/userAssignedIdentities/listAssociatedResources/action",
                    "Microsoft.ManagedIdentity/userAssignedIdentities/assign/action",
                    "Microsoft.ManagedIdentity/userAssignedIdentities/revokeTokens/action",
                    "Microsoft.Authorization/roleAssignments/read",
                    "Microsoft.Authorization/roleAssignments/delete",
                    "Microsoft.Authorization/roleAssignments/write",
                    "Microsoft.Storage/storageAccounts/queueServices/write",
                    "Microsoft.Storage/storageAccounts/queueServices/read",
                    "Microsoft.Storage/storageAccounts/queueServices/queues/delete",
                    "Microsoft.Storage/storageAccounts/queueServices/queues/read",
                    "Microsoft.Storage/storageAccounts/queueServices/queues/write",
                    "Microsoft.Storage/storageAccounts/queueServices/queues/setAcl/action",
                    "Microsoft.Storage/storageAccounts/queueServices/queues/getAcl/action",
                    "Microsoft.ContainerRegistry/register/action",
                    "Microsoft.ContainerRegistry/unregister/action",
                    "Microsoft.ContainerRegistry/registries/read",
                    "Microsoft.ContainerRegistry/registries/write",
                    "Microsoft.ContainerRegistry/registries/delete",
                    "Microsoft.ContainerRegistry/registries/listCredentials/action",
                    "Microsoft.ContainerRegistry/registries/regenerateCredential/action",
                    "Microsoft.ContainerRegistry/registries/generateCredentials/action",
                    "Microsoft.ContainerRegistry/registries/importImage/action",
                    "Microsoft.ContainerRegistry/registries/listBuildSourceUploadUrl/action",
                    "Microsoft.ContainerRegistry/registries/scheduleRun/action",
                    "Microsoft.ContainerRegistry/registries/privateEndpointConnectionsApproval/action",
                    "Microsoft.ContainerRegistry/registries/operationStatuses/read",
                    "microsoft.app/jobs/write",
                    "microsoft.app/jobs/delete",
                    "microsoft.app/jobs/start/action",
                    "microsoft.app/jobs/stop/action",
                    "microsoft.app/jobs/suspend/action",
                    "microsoft.app/jobs/resume/action",
                    "microsoft.app/jobs/listsecrets/action",
                    "microsoft.app/jobs/read",
                    "microsoft.app/jobs/authtoken/action",
                    "microsoft.app/jobs/getauthtoken/action",
                    "microsoft.app/managedenvironments/join/action",
                    "microsoft.app/managedenvironments/read",
                    "microsoft.app/managedenvironments/write",
                    "microsoft.app/managedenvironments/delete",
                    "microsoft.app/managedenvironments/getauthtoken/action",
                    "microsoft.app/managedenvironments/checknameavailability/action",
                    "Microsoft.OperationalInsights/workspaces/write",
                    "Microsoft.OperationalInsights/workspaces/read",
                    "Microsoft.OperationalInsights/workspaces/delete",
                    "Microsoft.OperationalInsights/workspaces/sharedkeys/action",
                    "Microsoft.OperationalInsights/workspaces/listKeys/action",
                    "Microsoft.OperationalInsights/workspaces/regenerateSharedKey/action",
                    "Microsoft.OperationalInsights/workspaces/search/action",
                    "Microsoft.OperationalInsights/workspaces/purge/action",
                    "Microsoft.OperationalInsights/workspaces/customfields/action",
                    "Microsoft.OperationalInsights/workspaces/failback/action",
                    "Microsoft.Authorization/roleDefinitions/read",
                    "Microsoft.Authorization/roleDefinitions/write",
                    "Microsoft.Authorization/roleDefinitions/delete",
                    "Microsoft.Web/sites/Read",
                    "Microsoft.Web/sites/Write",
                    "Microsoft.Web/sites/Delete",
                    "Microsoft.Web/serverfarms/Read",
                    "Microsoft.Web/serverfarms/Write",
                    "Microsoft.Web/serverfarms/Delete",
                    "Microsoft.Web/serverfarms/Join/Action",
                    "Microsoft.Web/serverfarms/restartSites/Action",
                    "Microsoft.Web/sites/config/Read",
                    "Microsoft.Web/sites/config/list/Action",
                    "Microsoft.Web/sites/config/Write",
                    "microsoft.web/sites/config/delete",
                    "microsoft.web/sites/config/web/appsettings/read",
                    "microsoft.web/sites/config/web/appsettings/write",
                    "microsoft.web/sites/config/web/appsettings/delete",
                    "microsoft.web/sites/config/web/connectionstrings/read",
                    "microsoft.web/sites/config/web/connectionstrings/write",
                    "microsoft.web/sites/config/web/connectionstrings/delete",
                    "microsoft.web/sites/config/appsettings/read",
                    "microsoft.web/sites/config/snapshots/read",
                    "microsoft.web/sites/config/snapshots/listsecrets/action",
                    "microsoft.web/unregister/action",
                    "microsoft.web/validate/action",
                    "microsoft.web/register/action",
                    "microsoft.web/verifyhostingenvironmentvnet/action",
                    "Microsoft.Resources/subscriptions/resourceGroups/delete",
                    "Microsoft.ContainerRegistry/registries/tasks/read",
                    "Microsoft.ContainerRegistry/registries/tasks/write",
                    "Microsoft.ContainerRegistry/registries/tasks/delete",
                    "Microsoft.ContainerRegistry/registries/tasks/listDetails/action"
                ],
                "notActions": [],
                "dataActions": [
                    "Microsoft.ContainerRegistry/registries/repositories/metadata/read",
                    "Microsoft.ContainerRegistry/registries/repositories/content/read",
                    "Microsoft.ContainerRegistry/registries/repositories/metadata/write",
                    "Microsoft.ContainerRegistry/registries/repositories/content/write",
                    "Microsoft.ContainerRegistry/registries/repositories/metadata/delete",
                    "Microsoft.ContainerRegistry/registries/repositories/content/delete"
                ],
                "notDataActions": []
            }
        ]
    }
}
```

Create a User Assigned Managed Identity and apply the role. This can be done by first creating the role from above in the subscription's IAM. Then, create a User Assigned Managed Identity using the wizard and apply it.

You will then need to create a federated credential for the identity configured for this repo (or more likely, your fork).

## Deployment
This repo utilizes OpenTofu for deployment.
Additionally, we are using [OpenTofu Workspaces](https://opentofu.org/docs/language/state/workspaces/) to manage multiple deployments.
Deployment happens in multiple stages.

Stage 1: Deploy the registry
```sh
cd deploy/registry
tofu init
tofu plan
tofu apply
```

Stage 2: Deploy the backend
```sh
cd deploy/backend
tofu init
tofu workspace select <default/dev>
tofu plan
tofu apply
```

## Deleting the project

Stage 1: Remove both backends
```sh
cd deploy/backend
tofu workspace select <default/dev>
tofu destroy
```

Stage 2: Remove the registry
```sh
cd deploy/registry
tofu destroy
```

Stage 3: Remove your storage backend from Azure
