#!/bin/bash
# add-imagepullsecrets.sh
# Script to add imagePullSecrets to all Katenary-generated deployments

CHART_DIR="./epos-chart"
SECRET_NAME="${1:-epos-registry-secret}"

katenary convert -c docker-compose.yml --chart-name ${{ env.HELM_CHART_NAME }} --chart-version ${{ env.CHART_VERSION }} --app-version ${{ env.CHART_VERSION }} -o ./epos-chart 

echo "🔑 Adding imagePullSecrets to EPOS deployments..."
echo "Chart directory: $CHART_DIR"
echo "Pull secret name: $SECRET_NAME"
echo ""

# Function to add imagePullSecrets to a deployment template
add_imagepullsecrets() {
    local file="$1"
    local secret_name="$2"

    echo $file
    
    if [ -f "$file" ]; then
        echo "Processing $(basename "$file")..."
        
        # Check if imagePullSecrets already exists
        if grep -q "imagePullSecrets" "$file"; then
            echo "  ⚠ imagePullSecrets already exists in $(basename "$file")"
            return
        fi
        
        # Add imagePullSecrets after serviceAccountName or before containers
        # Look for the pod template spec section
        sed -i '/template:/,/spec:/{
            /spec:/{
                # Add imagePullSecrets with proper indentation
                a\      imagePullSecrets:\
      - name: {{ .Values.imagePullSecrets.name | default "'"$secret_name"'" }}
            }
        }' "$file"
        
        echo "  ✅ Added imagePullSecrets to $(basename "$file")"
    else
        echo "  ⚠ File $(basename "$file") not found"
    fi
}

# Add imagePullSecrets to all deployment files
echo "🔍 Searching for deployment files in $CHART_DIR/templates/..."

ls

if [ ! -d "$CHART_DIR/templates" ]; then
    echo "❌ Templates directory not found. Run katenary convert first."
    exit 1
fi

# Process all deployment files
for manifest_folder in "$CHART_DIR/templates/*" ; do
    add_imagepullsecrets "$manifest_folder/deployment.yaml" "$SECRET_NAME"
done

echo ""
echo "📝 Adding imagePullSecrets configuration to values.yaml..."

# Add imagePullSecrets section to values.yaml if it doesn't exist
VALUES_FILE="$CHART_DIR/values.yaml"

if [ -f "$VALUES_FILE" ]; then
    # Check if imagePullSecrets section already exists
    if ! grep -q "imagePullSecrets:" "$VALUES_FILE"; then
        cat >> "$VALUES_FILE" << EOF

# Image Pull Secrets Configuration
imagePullSecrets:
  # Name of the secret containing registry credentials
  name: "$SECRET_NAME"
  
  # Global registry configuration
  registry:
    server: "your-registry.example.com"
    username: ""  # Set via --set or separate secret
    password: ""  # Set via --set or separate secret
    email: ""

# Global image settings
global:
  imageRegistry: "your-registry.example.com"
  imagePullSecrets:
    - name: "$SECRET_NAME"
EOF
        echo "✅ Added imagePullSecrets configuration to values.yaml"
    else
        echo "⚠ imagePullSecrets configuration already exists in values.yaml"
    fi
else
    echo "⚠ values.yaml not found"
fi

echo ""
echo "🎉 imagePullSecrets configuration complete!"
echo ""
echo "📋 Next steps:"
echo "1. Create the registry secret:"
echo "   kubectl create secret docker-registry $SECRET_NAME \\"
echo "     --docker-server=your-registry.example.com \\"
echo "     --docker-username=your-username \\"
echo "     --docker-password=your-password \\"
echo "     --docker-email=your-email@example.com"
echo ""
echo "2. Or use Helm to create the secret during deployment:"
echo "   helm install epos $CHART_DIR \\"
echo "     --set imagePullSecrets.registry.server=your-registry.example.com \\"
echo "     --set imagePullSecrets.registry.username=your-username \\"
echo "     --set imagePullSecrets.registry.password=your-password \\"
echo "     --set imagePullSecrets.registry.email=your-email@example.com"
echo ""
echo "3. Deploy the chart:"
echo "   helm install epos $CHART_DIR"