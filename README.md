# EPOS Helm Chart Generation

This repository contains a GitHub Actions workflow that automatically generates Helm charts from the Docker Compose configuration using [Katenary](https://github.com/metal-stack/katenary).

## 🚀 Quick Start

### Prerequisites

- GitHub repository with the workflow file
- Docker Compose file (`docker-compose.yml`)
- Environment variables file (`.env.example`)

### Workflow Triggers

The workflow runs automatically on:
- **Push** to `main` or `develop` branches when Docker Compose files change
- **Pull Requests** to `main` branch
- **Manual trigger** via GitHub Actions UI
- **Git tags** for releases

### Manual Trigger

You can manually trigger the workflow:

1. Go to the "Actions" tab in your GitHub repository
2. Select "Generate Helm Chart" workflow
3. Click "Run workflow"
4. Optionally specify a custom chart version
5. Click "Run workflow"

## 📦 Generated Artifacts

The workflow creates two types of artifacts:

### 1. Zipped Helm Chart (`epos-helm-chart-{version}-{timestamp}.zip`)
Contains:
- Complete Helm chart with all templates
- Values files for different environments
- Installation examples and scripts
- Chart metadata

### 2. Individual Chart Files (`helm-chart-files-{version}`)
Contains:
- Raw Helm chart directory structure
- Separate files for easy browsing

## 🛠 Using the Generated Helm Chart

### Download and Extract

```bash
# Download from GitHub Actions artifacts or releases
unzip epos-helm-chart-*.zip
cd epos-system/
```

### Basic Installation

```bash
# Install with default values
helm install epos-system ./

# Install with custom namespace
helm install epos-system ./ --namespace epos-production --create-namespace

# Install with custom values
helm install epos-system ./ --values examples/values-production.yaml
```

### Configuration Options

Key values you can override:

```yaml
# Kubernetes settings
namespace: epos-system
ingressClass: nginx

# Deployment paths
dataportalDeployPath: /portal
apiDeployPath: /api
backofficeDeployPath: /backoffice

# Database settings
postgresUser: epos_user
postgresPassword: epos_password
postgresDb: epos_metadata

# Image settings (all services support imagePullPolicy: Always)
images:
  dataportal: epos/dataportal:latest
  gateway: epos/gateway:latest
  # ... etc
```

### Environment-Specific Deployments

#### Production
```bash
helm install epos-prod ./ \
  --namespace epos-production \
  --values examples/values-production.yaml \
  --set postgresPassword=secure-production-password \
  --set rabbitmqPassword=secure-production-password
```

#### Development
```bash
helm install epos-dev ./ \
  --namespace epos-development \
  --values examples/values-development.yaml
```

#### Staging
```bash
helm install epos-staging ./ \
  --namespace epos-staging \
  --values examples/values-production.yaml \
  --set environmentType=staging
```

## 🔧 Customizing the Workflow

### Environment Variables

Create or modify `.env.example` with your default values:

```bash
# Copy and customize
cp .env.example .env
# Edit .env with your specific values
```

### Workflow Configuration

Edit `.github/workflows/helm-chart.yml` to customize:

- **Triggers**: Modify the `on:` section
- **Chart name**: Change `HELM_CHART_NAME` environment variable
- **Katenary version**: Update `KATENARY_VERSION` in the install step
- **Artifact retention**: Modify `retention-days`

### Chart Customization

The workflow automatically:
- Sets chart metadata from repository information
- Creates example values files
- Adds installation scripts
- Validates the generated chart

## 📋 Workflow Steps Overview

1. **Checkout**: Gets the repository code
2. **Environment Setup**: Prepares environment variables
3. **Install Katenary**: Downloads and installs the conversion tool
4. **Validate**: Checks Docker Compose file syntax
5. **Generate**: Converts Docker Compose to Helm chart
6. **Customize**: Adds metadata and examples
7. **Validate Chart**: Runs Helm lint and template tests
8. **Package**: Creates zip artifacts
9. **Upload**: Stores artifacts in GitHub
10. **Release**: Creates releases for tagged versions

## 🐛 Troubleshooting

### Common Issues

1. **Katenary Installation Fails**
   - Check if the version exists in releases
   - Verify download URL is accessible

2. **Chart Generation Fails**
   - Validate Docker Compose syntax
   - Check environment variable values
   - Ensure all required Katenary labels are present

3. **Chart Validation Fails**
   - Review generated templates
   - Check values.yaml syntax
   - Verify Kubernetes resource definitions

### Debug Mode

To debug chart generation locally:

```bash
# Install Katenary locally
wget -O katenary.tar.gz "https://github.com/metal-stack/katenary/releases/download/v1.0.0/katenary_Linux_x86_64.tar.gz"
tar -xzf katenary.tar.gz
sudo mv katenary /usr/local/bin/

# Generate chart
katenary convert --file docker-compose.yml --output ./helm-output

# Validate
helm lint ./helm-output/epos-system/
helm template test ./helm-output/epos-system/ --dry-run
```

## 📚 Additional Resources

- [Katenary Documentation](https://github.com/metal-stack/katenary)
- [Helm Documentation](https://helm.sh/docs/)
- [GitHub Actions Documentation](https://docs.github.com/en/actions)
- [Kubernetes Ingress Documentation](https://kubernetes.io/docs/concepts/services-networking/ingress/)

## 🤝 Contributing

1. Fork the repository
2. Create a feature branch
3. Modify Docker Compose or workflow files
4. Test the workflow
5. Submit a pull request

The workflow will automatically run on your PR to validate changes.

## 📄 License

This project is licensed under the GNU General Public License v3.0 - see the LICENSE file for details.