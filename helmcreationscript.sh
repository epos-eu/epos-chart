#!/bin/bash
# add-imagepullsecrets.sh
# Script to add runtime docker-registry secret and imagePullSecrets to Katenary-generated deployments

CHART_DIR="./epos-chart"
SECRET_NAME="${1:-epos-registry-secret}"
VERSION=${CHART_VERSION:-0.0.1}

echo "🚀 Converting docker-compose to Helm chart..."
katenary convert -c docker-compose.yml --app-version $VERSION --chart-version $VERSION -o ./epos-chart 

echo "🔑 Setting up runtime docker-registry secret for EPOS deployments..."
echo "Chart directory: $CHART_DIR"
echo "Pull secret name: $SECRET_NAME"
echo ""

# Function to update imagePullSecrets in deployment templates
update_imagepullsecrets() {
    local file="$1"
    local secret_name="$2"

    if [ -f "$file" ]; then
        echo "Processing $(basename "$(dirname "$file")")/$(basename "$file")..."
        
        # Check if .Values.pullSecrets exists and replace the entire block
        if grep -q "\.Values\.pullSecrets" "$file"; then
            echo "  🔄 Found .Values.pullSecrets reference, replacing entire imagePullSecrets block..."
            
            # Replace the entire imagePullSecrets block
            # This handles the pattern:
            # {{- if .Values.pullSecrets }}
            # imagePullSecrets:
            # {{- .Values.pullSecrets | toYaml | nindent 6 }}
            # {{- end }}
            sed -i '/{{- if \.Values\.pullSecrets }}/,/{{- end }}/{
                /{{- if \.Values\.pullSecrets }}/c\
      {{- if .Values.global.imagePullSecrets.enabled }}
                /imagePullSecrets:/c\
      imagePullSecrets:
                /{{- \.Values\.pullSecrets.*}}/c\
      - name: {{ .Values.global.imagePullSecrets.secretName }}
                /{{- end }}/c\
      {{- end }}
            }' "$file"
            
            echo "  ✅ Replaced imagePullSecrets block with global configuration in $(basename "$file")"
            
        # Check if imagePullSecrets exists but needs to be standardized
        elif grep -q "imagePullSecrets" "$file"; then
            echo "  ℹ️  imagePullSecrets already exists in $(basename "$file"), checking format..."
            
            # Check if it's using the correct global format
            if grep -q "\.Values\.global\.imagePullSecrets\.secretName" "$file"; then
                echo "  ✅ Already using correct .Values.global.imagePullSecrets format"
            else
                echo "  🔄 Updating imagePullSecrets format to use global values..."
                # Replace any remaining .Values.pullSecrets or other formats
                sed -i '/imagePullSecrets:/,/^[[:space:]]*[a-zA-Z]/{
                    /{{- if/c\
      {{- if .Values.global.imagePullSecrets.enabled }}
                    /- name:/c\
      - name: {{ .Values.global.imagePullSecrets.secretName }}
                    /{{- end }}/c\
      {{- end }}
                }' "$file"
                echo "  ✅ Updated imagePullSecrets format"
            fi
        else
            echo "  📝 No imagePullSecrets found, adding new configuration..."
            
            # Add imagePullSecrets after serviceAccountName or before containers
            # Look for the pod template spec section
            sed -i '/template:/,/spec:/{
                /spec:/{
                    # Add imagePullSecrets with proper indentation
                    a\      {{- if .Values.global.imagePullSecrets.enabled }}\
      imagePullSecrets:\
      - name: {{ .Values.global.imagePullSecrets.secretName }}\
      {{- end }}
                }
            }' "$file"
            
            echo "  ✅ Added imagePullSecrets to $(basename "$file")"
        fi
    else
        echo "  ⚠️  File $(basename "$file") not found"
    fi
}

echo "🔍 Processing deployment files..."

if [ ! -d "$CHART_DIR/templates" ]; then
    echo "❌ Templates directory not found. Katenary conversion may have failed."
    exit 1
fi

# Process all deployment files
find "$CHART_DIR/templates" -name "deployment.yaml" | while read -r file; do
    update_imagepullsecrets "$file" "$SECRET_NAME"
done

echo ""
echo "📝 Creating docker-registry secret template..."

# Create the secret template
cat > "$CHART_DIR/templates/docker-registry-secret.yaml" << 'EOF'
{{- if .Values.global.imagePullSecrets.enabled }}
apiVersion: v1
kind: Secret
metadata:
  name: {{ .Values.global.imagePullSecrets.secretName }}
  namespace: {{ .Release.Namespace }}
  labels:
    {{- include "epos-chart.labels" . | nindent 4 }}
type: kubernetes.io/dockerconfigjson
data:
  .dockerconfigjson: {{ printf "{\"auths\":{\"%s\":{\"username\":\"%s\",\"password\":\"%s\",\"email\":\"%s\",\"auth\":\"%s\"}}}" .Values.global.imagePullSecrets.registry.server .Values.global.imagePullSecrets.registry.username .Values.global.imagePullSecrets.registry.password .Values.global.imagePullSecrets.registry.email (printf "%s:%s" .Values.global.imagePullSecrets.registry.username .Values.global.imagePullSecrets.registry.password | b64enc) | b64enc }}
{{- end }}
EOF

echo "✅ Created docker-registry secret template"

echo ""
echo "📝 Updating values.yaml configuration..."

# Update values.yaml with global imagePullSecrets configuration
VALUES_FILE="$CHART_DIR/values.yaml"

if [ -f "$VALUES_FILE" ]; then
    # Remove any existing pullSecrets or imagePullSecrets sections
    if grep -q "^pullSecrets:" "$VALUES_FILE"; then
        echo "  🗑️  Removing old pullSecrets section..."
        sed -i '/^pullSecrets:/,/^[a-zA-Z]/{ /^[a-zA-Z]/!d; /^pullSecrets:/d; }' "$VALUES_FILE"
    fi
    
    # Check if global section already exists
    if ! grep -q "^global:" "$VALUES_FILE"; then
        # Add global section at the beginning
        cat > "${VALUES_FILE}.tmp" << EOF
# Global configuration
global:
  # Docker registry configuration for private images
  imagePullSecrets:
    # Enable/disable docker-registry secret creation
    enabled: true
    
    # Name of the secret to create and reference
    secretName: "$SECRET_NAME"
    
    # Registry credentials (set these via --set during installation)
    registry:
      server: ""     # e.g., "your-registry.example.com" or "ghcr.io"
      username: ""   # Registry username
      password: ""   # Registry password or token
      email: ""      # Registry email

EOF
        cat "$VALUES_FILE" >> "${VALUES_FILE}.tmp"
        mv "${VALUES_FILE}.tmp" "$VALUES_FILE"
        echo "✅ Added global.imagePullSecrets configuration to values.yaml"
    else
        # Check if global.imagePullSecrets already exists
        if ! grep -A 10 "^global:" "$VALUES_FILE" | grep -q "imagePullSecrets:"; then
            echo "  📝 Adding imagePullSecrets to existing global section..."
            # Add imagePullSecrets to existing global section
            sed -i '/^global:/a\
  # Docker registry configuration for private images\
  imagePullSecrets:\
    # Enable/disable docker-registry secret creation\
    enabled: true\
    \
    # Name of the secret to create and reference\
    secretName: "'"$SECRET_NAME"'"\
    \
    # Registry credentials (set these via --set during installation)\
    registry:\
      server: ""     # e.g., "your-registry.example.com" or "ghcr.io"\
      username: ""   # Registry username\
      password: ""   # Registry password or token\
      email: ""      # Registry email\
' "$VALUES_FILE"
            echo "✅ Added imagePullSecrets to existing global section"
        else
            echo "ℹ️  global.imagePullSecrets already exists in values.yaml"
        fi
    fi
else
    echo "⚠️  values.yaml not found"
fi

echo ""
echo "🎉 Docker registry secret configuration complete!"
echo ""
echo "📋 The chart now includes:"
echo "  • Docker-registry secret template that creates the secret at runtime"
echo "  • All deployments configured to use the imagePullSecrets"
echo "  • Global configuration in values.yaml"
echo ""
echo "🚀 Installation examples:"
echo ""
echo "1. Install with Docker Hub (or public registry with auth):"
echo "   helm install epos $CHART_DIR \\"
echo "     --set global.imagePullSecrets.registry.server=\"https://index.docker.io/v1/\" \\"
echo "     --set global.imagePullSecrets.registry.username=\"your-dockerhub-username\" \\"
echo "     --set global.imagePullSecrets.registry.password=\"your-dockerhub-token\" \\"
echo "     --set global.imagePullSecrets.registry.email=\"your-email@example.com\""
echo ""
echo "2. Install with GitHub Container Registry:"
echo "   helm install epos $CHART_DIR \\"
echo "     --set global.imagePullSecrets.registry.server=\"ghcr.io\" \\"
echo "     --set global.imagePullSecrets.registry.username=\"your-github-username\" \\"
echo "     --set global.imagePullSecrets.registry.password=\"your-github-token\" \\"
echo "     --set global.imagePullSecrets.registry.email=\"your-email@example.com\""
echo ""
echo "3. Install with custom private registry:"
echo "   helm install epos $CHART_DIR \\"
echo "     --set global.imagePullSecrets.registry.server=\"your-registry.example.com\" \\"
echo "     --set global.imagePullSecrets.registry.username=\"your-username\" \\"
echo "     --set global.imagePullSecrets.registry.password=\"your-password\" \\"
echo "     --set global.imagePullSecrets.registry.email=\"your-email@example.com\""
echo ""
echo "4. Disable imagePullSecrets (for public images):"
echo "   helm install epos $CHART_DIR \\"
echo "     --set global.imagePullSecrets.enabled=false"
echo ""
echo "💡 Pro tip: You can also create a values-override.yaml file with your registry credentials"
echo "   and use: helm install epos $CHART_DIR -f values-override.yaml"