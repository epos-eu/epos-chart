# epos-chart

**EPOS Helm Chart for Kubernetes Deployment**

This repository hosts a GitHub Actions workflow that automatically generates Helm charts from a Docker Compose configuration using **Katenary**.

---

## 🛠️ Repository Structure

- `.github/workflows/`: workflow to generate Helm charts via GitHub Actions  
- `docker-compose.yaml`: service definitions to be converted  
- `.env` / `.env.example`: environment variables for template configuration  
- `helmcreationscript.sh`: custom script for chart creation  
- `LICENSE`: GPL-3.0 License  

---

## 🚀 Quick Start

### Prerequisites

- GitHub repository with the workflow `.github/workflows/helm-chart.yml`  
- `docker-compose.yml` file with the services to be converted  
- `.env.example` file containing example variables  

### Workflow Triggers

The workflow is automatically triggered on:

- Push to `main` or `develop` when `docker-compose.yml` changes  
- Pull requests targeting `main`  
- Manual trigger via GitHub Actions UI  
- Release tag  

### Manual Run

1. Navigate to **Actions** in the GitHub repository  
2. Select the **Generate Helm Chart** workflow  
3. Click **Run workflow**, optionally set a custom version  

---

## 📦 Workflow Outputs

### 1. Zipped Helm Chart

`epos-helm-chart-{version}-{timestamp}.zip` containing:

- Complete Helm chart with templates  
- `values.yaml` for different environments  
- Example installation scripts  
- Chart metadata  

### 2. Individual Chart Files

`helm-chart-files-{version}` containing:

- Structured chart directory with separate files for manual inspection  

---

## 🔧 Using the Generated Chart

```bash
# Download and unzip the snapshot from GitHub Actions or Releases
unzip epos-helm-chart-*.zip
cd epos-system/

# Basic installation
helm install epos-system ./

# With custom namespace
helm install epos-system ./ --namespace epos-production --create-namespace

# With custom values
helm install epos-system ./ --values examples/values-production.yaml


### Common Overrides

```yaml
namespace: epos-system
ingressClass: nginx
dataportalDeployPath: /portal
apiDeployPath: /api
backofficeDeployPath: /backoffice
postgresUser: epos_user
postgresPassword: epos_password
postgresDb: epos_metadata
images:
  dataportal: epos/dataportal:latest
  gateway: epos/gateway:latest
  # ...
```

### Environment-Specific Examples

```bash
# Production
helm install epos-prod ./ \
  --namespace epos-production \
  --values examples/values-production.yaml \
  --set postgresPassword=secure-production-password \
  --set rabbitmqPassword=secure-production-password

# Development
helm install epos-dev ./ \
  --namespace epos-development \
  --values examples/values-development.yaml

# Staging
helm install epos-staging ./ \
  --namespace epos-staging \
  --values examples/values-production.yaml \
  --set environmentType=staging
```

---

## ⚙️ Workflow Customization

### Environment Variables

Copy `.env.example` to `.env` and customize as needed:

```bash
cp .env.example .env
# Edit values as required
```

### Workflow File

In `.github/workflows/helm-chart.yml` you can configure:

* Workflow triggers (`on:`)
* Chart name (`HELM_CHART_NAME`)
* Katenary version (`KATENARY_VERSION`)
* Artifact retention duration (`retention-days`)

### Chart Customization

The workflow automatically:

* Sets chart metadata from the repository
* Generates example `values.yaml` files
* Adds installation scripts
* Performs chart validation (lint, template tests)

---

## 🔄 Workflow Steps

1. Checkout repository
2. Setup environment variables
3. Install Katenary
4. Validate Docker Compose file
5. Generate Helm chart
6. Add metadata and examples
7. Validate chart (lint, template)
8. Package chart (ZIP and directory)
9. Upload artifacts
10. Release creation (if tag present)

---

## 🛠️ Troubleshooting

1. **Katenary installation failure**

   * Check available version
   * Verify download URL accessibility

2. **Chart generation failure**

   * Validate syntax of `docker-compose.yml`
   * Ensure `.env` values are provided
   * Check Katenary-required labels

3. **Chart lint/template failure**

   * Inspect generated templates
   * Validate YAML syntax and Kubernetes resources

4. **Debug locally**

```bash
wget -O katenary.tar.gz "https://github.com/metal-stack/katenary/releases/download/v1.0.0/katenary_Linux_x86_64.tar.gz"
tar -xzf katenary.tar.gz
sudo mv katenary /usr/local/bin/
katenary convert --file docker-compose.yml --output ./helm-output
helm lint ./helm-output/epos-system/
helm template test ./helm-output/epos-system/ --dry-run
```

---

## 📚 Additional Resources

* [Katenary Documentation](https://github.com/metal-stack/katenary)
* [Helm Documentation](https://helm.sh/docs/)
* [GitHub Actions Documentation](https://docs.github.com/en/actions)

---

## 🤝 Contributing

1. Fork this repository
2. Create a feature branch
3. Modify `docker-compose.yml`, `.env`, workflow, etc.
4. Test locally and via PR (workflow runs automatically)
5. Submit a Pull Request (workflow will validate automatically)

---

## 📄 License

Distributed under the **GNU GPL-3.0 License**. See `LICENSE` for details.
