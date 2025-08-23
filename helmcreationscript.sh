#!/bin/bash
# add-imagepullsecrets.sh
# Script to add runtime docker-registry secret and imagePullSecrets to Katenary-generated deployments
# Uses external YAML file for global configuration

CHART_DIR="./epos-chart"
SECRET_NAME="${1:-epos-registry-secret}"
VERSION=${CHART_VERSION:-0.0.1}
GLOBAL_CONFIG_FILE="${2:-global-template.yaml}"

echo "🚀 Converting docker-compose to Helm chart..."
katenary convert -c docker-compose.yml --app-version $VERSION --chart-version $VERSION -o ./epos-chart

echo "🔑 Setting up runtime docker-registry secret for EPOS deployments..."
echo "Chart directory: $CHART_DIR"
echo "Pull secret name: $SECRET_NAME"
echo "Global config template: $GLOBAL_CONFIG_FILE"
echo ""

# Check if global config file exists
if [ ! -f "$GLOBAL_CONFIG_FILE" ]; then
    echo "⚠️  Global configuration file '$GLOBAL_CONFIG_FILE' not found!"
    echo "📝 Creating default global configuration template..."
    
    # Create default global config template
    cat > "$GLOBAL_CONFIG_FILE" << EOF
# Global configuration template for EPOS Helm Chart
global:
  # Docker registry configuration for private images
  imagePullSecrets:
    enabled: true
    secretName: "$SECRET_NAME"
    registry:
      server: ""
      username: ""
      password: ""
      email: ""

  # Additional global configurations
  nodeSelector: {}
  tolerations: []
  affinity: {}
  securityContext: {}
  resources: {}
EOF
    echo "✅ Created default global configuration template: $GLOBAL_CONFIG_FILE"
    echo "📝 Please edit this file with your desired global configurations before running the script again."
    echo ""
fi

# Function to extract global section from YAML file
extract_global_section() {
    local config_file="$1"
    
    if [ -f "$config_file" ]; then
        # Use yq if available, otherwise use awk
        if command -v yq >/dev/null 2>&1; then
            #echo "🔍 Using yq to extract global configuration..."
            # Check if global section exists
            if yq eval 'has("global")' "$config_file" 2>/dev/null | grep -q "true"; then
                # Method 1: Try to extract the entire global section including the key
                # This preserves the original formatting better
                yq eval '. | {"global": .global}' "$config_file" 2>/dev/null
            else
                echo "❌ No 'global:' section found in $config_file"
                return 1
            fi
        else
            #echo "🔍 Using awk to extract global configuration..."
            # Extract global section using awk (includes the global: key)
            local global_content=$(awk '
            /^global:/ { in_global=1; print; next }
            in_global && /^[a-zA-Z]/ && !/^[[:space:]]/ { in_global=0 }
            in_global { print }
            ' "$config_file")
            
            if [ -n "$global_content" ]; then
                echo "$global_content"
            else
                echo "❌ No 'global:' section found in $config_file"
                return 1
            fi
        fi
    else
        echo "❌ Configuration file not found: $config_file"
        return 1
    fi
}

# Function to update imagePullSecrets in deployment templates
update_imagepullsecrets() {
    local file="$1"

    if [ -f "$file" ]; then
        echo "Processing $(basename "$(dirname "$file")")/$(basename "$file")..."
        
        # Check if .Values.pullSecrets exists and replace the entire block
        if grep -q "\.Values\.pullSecrets" "$file"; then
            echo "  🔄 Found .Values.pullSecrets reference, replacing entire imagePullSecrets block..."
            
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
            
        elif grep -q "imagePullSecrets" "$file"; then
            echo "  ℹ️  imagePullSecrets already exists in $(basename "$file"), checking format..."
            
            if grep -q "\.Values\.global\.imagePullSecrets\.secretName" "$file"; then
                echo "  ✅ Already using correct .Values.global.imagePullSecrets format"
            else
                echo "  🔄 Updating imagePullSecrets format to use global values..."
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
            
            sed -i '/template:/,/spec:/{
                /spec:/{
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
    update_imagepullsecrets "$file"
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
echo "📝 Updating chart values.yaml with global configuration from $GLOBAL_CONFIG_FILE..."

VALUES_FILE="$CHART_DIR/values.yaml"

if [ -f "$VALUES_FILE" ]; then
    # Create backup
    cp "$VALUES_FILE" "${VALUES_FILE}.backup"
    echo "  💾 Created backup: ${VALUES_FILE}.backup"
    
    # Remove any existing global section
    if grep -q "^global:" "$VALUES_FILE"; then
        echo "  🗑️  Removing existing global section..."
        # Remove existing global section (everything from "global:" until next top-level key or EOF)
        sed -i '/^global:/,/^[a-zA-Z]/{/^[a-zA-Z]/!d; /^global:/d;}' "$VALUES_FILE"
    fi
    
    # Extract global section from external config file
    echo "  📥 Extracting global configuration from $GLOBAL_CONFIG_FILE..."
    
    # Extract global content directly
    GLOBAL_CONTENT=$(extract_global_section "$GLOBAL_CONFIG_FILE")
    
    if [ -n "$GLOBAL_CONTENT" ]; then
        echo "  ✅ Global configuration extracted"
        
        # Create new values.yaml with global section at the top
        {
            echo "# Global configuration (imported from $GLOBAL_CONFIG_FILE)"
            echo "$GLOBAL_CONTENT"
            echo ""
            echo "# Chart-specific configuration"
            cat "$VALUES_FILE"
        } > "${VALUES_FILE}.tmp"
        
        mv "${VALUES_FILE}.tmp" "$VALUES_FILE"
        echo "  ✅ Added global configuration to values.yaml"
    else
        echo "  ⚠️  Could not extract global section from $GLOBAL_CONFIG_FILE"
        echo "  💡 Make sure the file contains a 'global:' section"
        mv "${VALUES_FILE}.backup" "$VALUES_FILE"
        exit 1
    fi
    
    # Update the secret name in the imported global config if it differs
    if [ -n "$SECRET_NAME" ] && [ "$SECRET_NAME" != "epos-registry-secret" ]; then
        echo "  🔧 Updating secret name to: $SECRET_NAME"
        sed -i "s/secretName: .*/secretName: \"$SECRET_NAME\"/" "$VALUES_FILE"
    fi
    
    echo "  ✅ Successfully updated values.yaml with global configuration"
    
else
    echo "  ❌ values.yaml not found in $CHART_DIR"
    exit 1
fi

# Verify the result
echo ""
echo "🔍 Verifying global configuration in values.yaml..."
if grep -A 5 "^global:" "$VALUES_FILE" >/dev/null; then
    echo "✅ Global section successfully added to values.yaml"
    echo ""
    echo "📋 Global configuration preview:"
    echo "$(grep -A 10 "^global:" "$VALUES_FILE" | head -15)"
    echo "..."
else
    echo "❌ Failed to add global section to values.yaml"
    exit 1
fi

echo ""
echo "🎉 Docker registry secret configuration complete!"
echo ""
echo "📋 Configuration summary:"
echo "  • Global config template: $GLOBAL_CONFIG_FILE"
echo "  • Chart values updated: $VALUES_FILE"
echo "  • Secret template created: $CHART_DIR/templates/docker-registry-secret.yaml"
echo "  • All deployments configured with imagePullSecrets"
echo ""
echo "🔧 To modify global settings:"
echo "  1. Edit $GLOBAL_CONFIG_FILE with your desired configuration"
echo "  2. Re-run this script to update the chart"
echo ""
echo "🚀 Installation examples:"
echo ""
echo "1. Install with current configuration:"
echo "   helm install epos $CHART_DIR"
echo ""
echo "2. Override specific values:"
echo "   helm install epos $CHART_DIR \\"
echo "     --set global.imagePullSecrets.registry.server=\"ghcr.io\" \\"
echo "     --set global.imagePullSecrets.registry.username=\"your-username\" \\"
echo "     --set global.imagePullSecrets.registry.password=\"your-token\""
echo ""
echo "3. Test configuration:"
echo "   helm template epos $CHART_DIR --debug"
echo ""
echo "💡 Pro tips:"
echo "  • Keep $GLOBAL_CONFIG_FILE in version control for team consistency"
echo "  • Use environment-specific global config files for different deployments"
echo "  • Test changes with 'helm template' before deploying"