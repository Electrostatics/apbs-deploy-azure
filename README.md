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

## Deployment
This repo utilizes OpenTofu for deployment.
Additionally, we are using [OpenTofu Workspaces](https://opentofu.org/docs/language/state/workspaces/) to manage multiple deployments.
Deployment happens in multiple stages.

Stage 1: Deploy the registry
```sh
cd deploy/registry
tofu init
tofu plan tofu apply
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


