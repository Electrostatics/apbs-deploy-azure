# apbs-deploy-azure
This repo holds OpenTofu modules for deploying pdb2pqr and apbs on Azure.

## Repo structure
```
├── container-apps -> Containerized applications
│   └── apbs -> The main job runner
├── deploy -> Deployment scripts using OpenTofu
│   ├── backend -> Backend deployment
│   └── registry -> Registry deployment
├── modules
│   ├── apbs-backend -> Modules used for deploying the backend
│   │   ├── storage -> Used to abstract storage containes
│   │   ├── storage-account -> Storage account module
│   ├── apbs-web
│   │   ├── cdn -> CDN module (not used, but kept for reference)
│   │   ├── github_oidc -> GitHub OIDC module (not used, but kept for reference)
│   │   └── static_site -> Static site module (not used, but kept for reference)
│   └── registry -> Azure Container Registry module
```

## Deployment
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
tofu plan tofu apply
```
