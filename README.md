# EPOS Helm Chart Generator

> Convert Docker Compose configurations to production-ready Helm charts for the EPOS (European Plate Observing System) platform.

## Overview

This repository provides tools and automation to convert a complex multi-service EPOS application from Docker Compose format into a production-ready Kubernetes Helm chart. The generated chart includes proper image pull secrets, ingress configuration, health checks, and service dependencies.

### What is EPOS?

EPOS (European Plate Observing System) is a comprehensive platform for geoscientific data management and access, consisting of multiple microservices including:

- **Data Portal** - Web frontend for data discovery and access
- **Backoffice UI** - Administrative interface
- **API Gateway** - Central API management and routing
- **Resource Service** - Metadata and resource management
- **Ingestor Service** - Data ingestion and validation
- **Converter Services** - Data format conversion
- **External Access Service** - External API integrations
- **Email Sender Service** - Notification system
- **Sharing Service** - Data sharing capabilities
- **PostgreSQL Database** - Metadata storage
- **RabbitMQ** - Message broker for service communication

## Features

✅ **Automated Conversion** - Convert docker-compose.yml to Helm chart using Katenary  
✅ **Image Pull Secrets** - Automatic setup for private container registries  
✅ **Ingress Configuration** - Production-ready ingress with path-based routing  
✅ **Health Checks** - Kubernetes readiness and liveness probes  
✅ **Service Dependencies** - Proper startup order and dependency management  
✅ **CI/CD Integration** - GitHub Actions workflow for automated chart generation  
✅ **Multi-Registry Support** - Docker Hub, GHCR, and custom private registries  
✅ **Flexible Configuration** - Environment-based configuration management  

## Quick Start

### Prerequisites

- [Katenary](https://katenary.io) - Docker Compose to Helm converter
- [Helm 3+](https://helm.sh) - Kubernetes package manager
- Kubernetes cluster (for deployment)

### 1. Generate Helm Chart

Run the automated script to convert your Docker Compose configuration:

```bash
# Make the script executable
chmod +x add-imagepullsecrets.sh

# Generate the chart (uses default secret name: epos-registry-secret)
./add-imagepullsecrets.sh

# Or specify a custom secret name
./add-imagepullsecrets.sh my-custom-secret
```

This will:
- Convert `docker-compose.yml` to Helm chart in `./epos-chart/`
- Add image pull secrets configuration
- Create docker-registry secret template
- Update `values.yaml` with global configuration

### 2. Deploy to Kubernetes

#### For Public Images (No Authentication)
```bash
helm install epos-system ./epos-chart \
  --set global.imagePullSecrets.enabled=false
```

#### For Private Docker Hub Registry
```bash
helm install epos-system ./epos-chart \
  --set global.imagePullSecrets.registry.server="https://index.docker.io/v1/" \
  --set global.imagePullSecrets.registry.username="your-dockerhub-username" \
  --set global.imagePullSecrets.registry.password="your-dockerhub-token" \
  --set global.imagePullSecrets.registry.email="your-email@example.com"
```

#### For GitHub Container Registry
```bash
helm install epos-system ./epos-chart \
  --set global.imagePullSecrets.registry.server="ghcr.io" \
  --set global.imagePullSecrets.registry.username="your-github-username" \
  --set global.imagePullSecrets.registry.password="your-github-token" \
  --set global.imagePullSecrets.registry.email="your-email@example.com"
```

#### For Custom Private Registry
```bash
helm install epos-system ./epos-chart \
  --set global.imagePullSecrets.registry.server="your-registry.example.com" \
  --set global.imagePullSecrets.registry.username="your-username" \
  --set global.imagePullSecrets.registry.password="your-password" \
  --set global.imagePullSecrets.registry.email="your-email@example.com"
```

## Configuration

### Environment Variables

The system uses environment variables for configuration. Key variables include:

| Variable | Description | Default |
|----------|-------------|---------|
| `POSTGRES_USER` | Database username | `postgres` |
| `POSTGRES_PASSWORD` | Database password | `changeme` |
| `RABBITMQ_USERNAME` | RabbitMQ username | `rabbitmq-user` |
| `RABBITMQ_PASSWORD` | RabbitMQ password | `changeme` |
| `INGRESS_CLASS` | Ingress controller class | `nginx` |
| `MONITORING` | Enable monitoring | `false` |

### Using Values Override File

Create a `values-override.yaml` file for custom configuration:

```yaml
global:
  imagePullSecrets:
    enabled: true
    secretName: "my-registry-secret"
    registry:
      server: "ghcr.io"
      username: "my-username"
      password: "my-token"
      email: "me@example.com"

# Override specific service configurations
dataportal:
  environment:
    BASE_URL: "/custom-portal/"

gateway:
  environment:
    SECURITY_KEY: "your-secure-key"
```

Then deploy:
```bash
helm install epos-system ./epos-chart -f values-override.yaml
```

## CI/CD Automation

### GitHub Actions Workflow

The repository includes an automated GitHub Actions workflow (`.github/workflows/generatehelm.yaml`) that:

1. **Triggers on:**
   - Push to `main` or `develop` branches
   - Tag creation (`v*`, `*.*.*`)
   - Pull requests to `main`
   - Manual dispatch
   - Release publication

2. **Automated Tasks:**
   - Validates Docker Compose configuration
   - Generates Helm chart using Katenary
   - Validates generated chart with Helm lint
   - Packages chart with proper versioning
   - Creates GitHub releases with chart assets
   - Uploads artifacts for download

### Versioning Strategy

- **Release/Tag Push:** Uses the tag name as chart version
- **Manual Dispatch:** Uses provided version or auto-generates
- **Other Events:** Uses `0.0.0+<shortsha>` format

### Downloading Pre-built Charts

Charts are automatically built and attached to GitHub releases:

```bash
# Download latest release
gh release download latest -p 'epos-chart-*.tgz'

# Install downloaded chart
helm install epos-system epos-chart-*.tgz
```

## Project Structure

```
├── add-imagepullsecrets.sh      # Main chart generation script
├── docker-compose.yml           # Source Docker Compose configuration
├── .env                         # Environment variables template
├── .github/workflows/
│   └── generatehelm.yaml       # GitHub Actions CI/CD workflow
├── epos-chart/                 # Generated Helm chart (after running script)
│   ├── Chart.yaml
│   ├── values.yaml
│   └── templates/
│       ├── deployment.yaml
│       ├── service.yaml
│       ├── ingress.yaml
│       └── docker-registry-secret.yaml
└── README.md
```

## Development

### Customizing the Chart Generation

To modify the chart generation process:

1. **Update Docker Compose:** Modify `docker-compose.yml`
2. **Environment Config:** Update `.env` file
3. **Script Customization:** Modify `add-imagepullsecrets.sh`
4. **CI/CD Changes:** Update `.github/workflows/generatehelm.yaml`

### Testing Changes

```bash
# Validate Docker Compose
docker compose config --quiet

# Generate and validate chart
./add-imagepullsecrets.sh
helm lint ./epos-chart
helm template test-release ./epos-chart --dry-run
```

## Troubleshooting

### Common Issues

**Chart Generation Fails:**
```bash
# Ensure Katenary is installed
katenary version

# Check Docker Compose syntax
docker compose config
```

**Image Pull Errors:**
```bash
# Verify registry credentials
kubectl get secret epos-registry-secret -o yaml

# Check image pull policy
kubectl describe pod <pod-name>
```

**Service Dependencies:**
```bash
# Check service startup order
kubectl get pods -w

# View service logs
kubectl logs -f deployment/<service-name>
```

### Debugging Deployment

```bash
# Check all resources
kubectl get all -l app.kubernetes.io/instance=epos-system

# View pod events
kubectl describe pods

# Check ingress configuration
kubectl get ingress
```

## Contributing

1. Fork the repository
2. Create a feature branch: `git checkout -b feature/my-feature`
3. Make your changes and test thoroughly
4. Commit your changes: `git commit -am 'Add my feature'`
5. Push to the branch: `git push origin feature/my-feature`
6. Submit a pull request

## License

This project is licensed under GPLv3.


**Note:** Ensure you review and customize the generated `values.yaml` file according to your specific deployment requirements, especially security-related configurations like passwords, secrets, and ingress settings.