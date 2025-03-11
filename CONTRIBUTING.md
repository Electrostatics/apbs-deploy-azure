# Contributing to apbs-deploy-azure

This document outlines the process for contributing to the `apbs-deploy-azure` repository, which contains the infrastructure as code (IaC) for deploying the APBS system to Azure.

## Project Overview

The APBS Deploy repository contains Terraform/OpenTofu configurations that define the Azure infrastructure for the APBS system. This includes storage accounts, function apps, container registries, and other resources needed to run the system.

## Access Restrictions

**Important**: Infrastructure deployment is restricted to project maintainers only. Contributors cannot directly test infrastructure changes as access to the Azure subscription is limited to the project maintainers.

## Development Environment Setup

### Prerequisites

- Git
- GitHub account
- Knowledge of Terraform/OpenTofu (for understanding the infrastructure code)

### Getting Started

1. Fork the repository
2. Clone your fork:
   ```bash
   git clone https://github.com/your-username/apbs-deploy-azure.git
   cd apbs-deploy-azure
   ```

## Repository Structure

- Terraform modules for different components of the infrastructure
- Workspace configurations for different environments
- GitHub Action workflows for deployment

## Branch Structure

- `main`: Production branch - deployed to the production environment
- `dev`: Development branch - deployed to the development environment
- Feature branches should be created from `dev`

## Proposing Infrastructure Changes

1. Create a feature branch from `dev`:
   ```bash
   git checkout dev
   git pull origin dev
   git checkout -b feature/your-infrastructure-change
   ```

2. Make your changes to the Terraform/OpenTofu files

3. Commit your changes with detailed explanations:
   ```bash
   git commit -m "Description of infrastructure changes"
   ```

4. When creating a pull request, provide a detailed description of:
   - What infrastructure resources you're modifying
   - Why these changes are necessary
   - Expected impact on the system
   - Any potential risks or considerations

## Pull Request Process

1. Push your feature branch to your fork:
   ```bash
   git push origin feature/your-infrastructure-change
   ```

2. Create a pull request to the `dev` branch of the main repository

3. Your PR should include:
   - A thorough description of the infrastructure changes
   - Any relevant issue numbers
   - Context for why these changes are needed

4. Project maintainers will:
   - Review your proposed changes
   - Run Terraform/OpenTofu plans to validate the changes
   - Provide feedback if modifications are needed
   - Handle the actual application of changes

## Review and Deployment Process

- All infrastructure changes undergo thorough review by maintainers
- Only maintainers can run `tofu plan` and `tofu apply`
- Maintainers use a workspace-based approach for deployment:
  - `default` workspace: Production environment
  - `dev` workspace: Development environment
- Changes are first applied to the `dev` environment for testing
- After verification in `dev`, changes can be promoted to production

## Workspace Configuration

The repository uses Terraform/OpenTofu workspaces to manage environment-specific configurations:

- Remote state ensures separate deployments
- Environment-specific variables are defined in the workspace configurations
- Common configurations are shared between workspaces

## Security Considerations

- Infrastructure changes require thorough review by maintainers
- Sensitive values are managed through secure methods and not committed to the repository
- Role assignments follow the principle of least privilege
- Default to using managed identities wherever possible

## Role Management

Roles for resources are defined centrally:
- Cross-module roles are at the root level
- Module-specific roles are within their respective modules

## Best Practices for Contributors

Even though you cannot apply infrastructure changes directly:

1. **Be declarative**: Make your intention clear in the code and documentation
2. **Follow existing patterns**: Maintain consistency with the existing infrastructure code
3. **Minimize scope**: Keep changes focused and minimal
4. **Document thoroughly**: Provide context for why changes are necessary
5. **Consider security**: Be mindful of security implications of your changes

## Questions and Support

If you have questions or need help, please open an issue in the repository or contact the project maintainers.

