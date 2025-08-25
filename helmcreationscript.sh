#!/bin/bash
# add-imagepullsecrets-and-jobs.sh
# Script to add runtime docker-registry secret, imagePullSecrets, and initialization Jobs to Katenary-generated deployments
# Uses external YAML file for global configuration and job configuration

CHART_DIR="./epos-chart"
SECRET_NAME="${1:-epos-registry-secret}"
VERSION=${CHART_VERSION:-0.0.1}
GLOBAL_CONFIG_FILE="${2:-global-template.yaml}"
JOBS_CONFIG_FILE="${3:-jobs-template.yaml}"

echo "🚀 Converting docker-compose to Helm chart..."
katenary convert -c docker-compose.yml --app-version $VERSION --chart-version $VERSION -o ./epos-chart

echo "🔑 Setting up runtime docker-registry secret and initialization jobs for EPOS deployments..."
echo "Chart directory: $CHART_DIR"
echo "Pull secret name: $SECRET_NAME"
echo "Global config template: $GLOBAL_CONFIG_FILE"
echo "Jobs config template: $JOBS_CONFIG_FILE"
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
fi

# Check if jobs config file exists
if [ ! -f "$JOBS_CONFIG_FILE" ]; then
    echo "⚠️  Jobs configuration file '$JOBS_CONFIG_FILE' not found!"
    echo "📝 Creating default jobs configuration template..."
    
    # Create default jobs config template
    cat > "$JOBS_CONFIG_FILE" << EOF
# Jobs configuration template for EPOS initialization
jobs:
  # Enable/disable job creation
  enabled: true
  
  # Job 1: Database Initialization (post-install hook)
  initDb:
    enabled: true
    image: "your-pgha-job-image"
    tag: "latest"
    connectionString: "postgresql://{{ tpl .Values.global.services.database.host . }}:{{ .Values.global.services.database.port }}/{{ .Values.global.services.database.dbname }}?user={{ .Values.global.services.database.username }}&password={{ .Values.global.services.database.password }}"
    pgConnectionString: "postgresql://{{ tpl .Values.global.services.database.host . }}:{{ .Values.global.services.database.port }}/{{ .Values.global.services.database.dbname }}?user={{ .Values.global.services.database.username }}&password={{ .Values.global.services.database.password }}"
    hookWeight: "1"
    backoffLimit: 3
    activeDeadlineSeconds: 1800
    waitForServices:
      - "gateway:5000"
    resources:
      requests:
        cpu: 100m
        memory: 256Mi
      limits:
        cpu: 500m
        memory: 512Mi

  # Job 2: Plugin Populator (post-install hook, weight 2)
  pluginPopulator:
    enabled: true
    image: "epos-ci.brgm.fr:5005/epos/converter-plugins/populate-environment-script"
    tag: "docker"
    hookWeight: "2"
    backoffLimit: 3
    activeDeadlineSeconds: 3600
    waitForServices:
      - "gateway:5000"
    resources:
      requests:
        cpu: 10m
        memory: 100Mi
      limits:
        cpu: 200m
        memory: 256Mi

  # Job 3: Metadata Populator (post-install hook, weight 3)
  metadataPopulator:
    enabled: true
    image: "your-metadatapopulator-image"
    tag: "latest"
    hookWeight: "3"
    backoffLimit: 3
    activeDeadlineSeconds: 3600
    securityCode: "your-security-code"
    maxParallel: 10
    waitForServices:
      - "gateway:5000"
    resources:
      requests:
        cpu: 100m
        memory: 256Mi
      limits:
        cpu: 1000m
        memory: 1Gi
EOF
    echo "✅ Created default jobs configuration template: $JOBS_CONFIG_FILE"
    echo "📝 Please edit these files with your desired configurations before running the script again."
    echo ""
fi

# Function to extract sections from YAML file
extract_yaml_section() {
    local config_file="$1"
    local section_name="$2"
    
    if [ -f "$config_file" ]; then
        # Use yq if available, otherwise use awk
        if command -v yq >/dev/null 2>&1; then
            # Check if section exists
            if yq eval "has(\"$section_name\")" "$config_file" 2>/dev/null | grep -q "true"; then
                yq eval ". | {\"$section_name\": .$section_name}" "$config_file" 2>/dev/null
            else
                echo "❌ No '$section_name:' section found in $config_file"
                return 1
            fi
        else
            # Extract section using awk
            local section_content=$(awk -v section="$section_name" '
            $0 ~ "^" section ":" { in_section=1; print; next }
            in_section && /^[a-zA-Z]/ && !/^[[:space:]]/ { in_section=0 }
            in_section { print }
            ' "$config_file")
            
            if [ -n "$section_content" ]; then
                echo "$section_content"
            else
                echo "❌ No '$section_name:' section found in $config_file"
                return 1
            fi
        fi
    else
        echo "❌ Configuration file not found: $config_file"
        return 1
    fi
}

# Function to create initialization jobs
create_initialization_jobs() {
    local templates_dir="$1"
    
    echo "🏗️  Creating initialization jobs..."
    
    # Job 1: init-db.yaml (pre-install hook)
    cat > "$templates_dir/init-db-job.yaml" << 'EOF'
{{- if and .Values.jobs.enabled .Values.jobs.initDb.enabled }}
apiVersion: batch/v1
kind: Job
metadata:
  name: '{{ include "epos-chart.fullname" . }}-init-db'
  labels:
    {{- include "epos-chart.labels" . | nindent 4 }}
    katenary.v3/component: init-db
  annotations:
    "helm.sh/hook": post-install,post-upgrade
    "helm.sh/hook-weight": "{{ .Values.jobs.initDb.hookWeight }}"
    "helm.sh/hook-delete-policy": before-hook-creation,hook-succeeded
spec:
  completions: 1
  parallelism: 1
  backoffLimit: {{ .Values.jobs.initDb.backoffLimit }}
  activeDeadlineSeconds: {{ .Values.jobs.initDb.activeDeadlineSeconds }}
  template:
    metadata:
      labels:
        {{- include "epos-chart.selectorLabels" . | nindent 8 }}
        katenary.v3/component: init-db
    spec:
      restartPolicy: OnFailure
      {{- if .Values.global.imagePullSecrets.enabled }}
      imagePullSecrets:
      - name: {{ .Values.global.imagePullSecrets.secretName }}
      {{- end }}
      
      initContainers:
      # Wait for required services
      {{- range .Values.jobs.initDb.waitForServices }}
      {{- $service := splitList ":" . }}
      - name: wait-for-{{ index $service 0 | replace "-" "" }}
        image: busybox:latest
        command: ["/bin/sh", "-c"]
        args:
        - |
          echo "Waiting for {{ index $service 0 }}:{{ index $service 1 }}..."
          until nc -z {{ include "epos-chart.fullname" $ }}-{{ index $service 0 }} {{ index $service 1 }}; do
            sleep 2
          done
          echo "✓ {{ index $service 0 }} is ready"
      {{- end }}
      
      containers:
      - name: init-db
        image: '{{ .Values.jobs.initDb.image }}:{{ .Values.jobs.initDb.tag }}'
        imagePullPolicy: Always
        command: [ "/bin/sh", "-c" ]
        args:
        - |
          set -e
          echo "[$(date '+%Y-%m-%d %H:%M:%S')] [init-db] Starting database initialization..."
          /init-db/init-db.sh
          echo "[$(date '+%Y-%m-%d %H:%M:%S')] [init-db] Database initialization completed successfully"
        env:
        - name: POSTGRESQL_JOB_CONNECTION_STRING
          value: '{{ tpl .Values.jobs.initDb.connectionString . }}'
        - name: POSTGRESQL_JOB_CONNECTION_STRING_PG
          value: '{{ tpl .Values.jobs.initDb.pgConnectionString . }}'
        - name: ALLOW_EMPTY_PASSWORD
          value: "yes"
        {{- if .Values.jobs.initDb.resources }}
        resources:
          {{ .Values.jobs.initDb.resources | toYaml | nindent 10 }}
        {{- end }}
{{- end }}
EOF
    
    # Job 2: pluginpopulator.yaml (post-install hook, weight 1)
    cat > "$templates_dir/pluginpopulator-job.yaml" << 'EOF'
apiVersion: v1
kind: ConfigMap
metadata:
  name: populate
data:
  # file-like keys
  populate.json: |
    [
      {
        "version": "main",
        "name": "ah-episodes-elements-plugin",
        "description": "plugin description",
        "version_type": "branch",
        "repository": "https://gitlab.com/epos-eric/epos/converter-plugins/ah-episodes-elements-plugin.git",
        "runtime": "java",
        "executable": "target/WP14_Episode_elements-main-jar-with-dependencies.jar",
        "arguments": "org.epos.ahepisodes.core.AHEpisodesInvoker",
        "enabled": true,
        "inputFormat": "application/json",
        "outputFormat": "application/epos.geo+json",
        "relations": [
          {
            "relationId": "anthropogenic_hazards/webservice/is-epos_platform/episode-elements/CZORSZTYN"
          },
          {
            "relationId": "anthropogenic_hazards/webservice/is-epos_platform/episode-elements/GS"
          },
          {
            "relationId": "anthropogenic_hazards/webservice/is-epos_platform/episode-elements/LGCD"
          },
          {
            "relationId": "anthropogenic_hazards/webservice/is-epos_platform/episode-elements/SONG_TRANH"
          },
          {
            "relationId": "anthropogenic_hazards/webservice/is-epos_platform/episode-elements/USCB"
          },
          {
            "relationId": "anthropogenic_hazards/webservice/is-epos_platform/episode-elements/BOBREK"
          },
          {
            "relationId": "anthropogenic_hazards/webservice/is-epos_platform/episode-elements/PYHASALMI_MINE"
          },
          {
            "relationId": "anthropogenic_hazards/webservice/is-epos_platform/episode-elements/LGF"
          },
          {
            "relationId": "anthropogenic_hazards/webservice/is-epos_platform/episode-elements/MONTEYNARD"
          },
          {
            "relationId": "anthropogenic_hazards/webservice/is-epos_platform/episode-elements/SSFS1993"
          },
          {
            "relationId": "anthropogenic_hazards/webservice/is-epos_platform/episode-elements/SSFS2000"
          },
          {
            "relationId": "anthropogenic_hazards/webservice/is-epos_platform/episode-elements/SSFS2003"
          },
          {
            "relationId": "anthropogenic_hazards/webservice/is-epos_platform/episode-elements/SSFS2004"
          },
          {
            "relationId": "anthropogenic_hazards/webservice/is-epos_platform/episode-elements/SSFS2005"
          },
          {
            "relationId": "anthropogenic_hazards/webservice/is-epos_platform/episode-elements/GISOS-CERVILLE"
          },
          {
            "relationId": "anthropogenic_hazards/webservice/is-epos_platform/episode-elements/STARFISH"
          },
          {
            "relationId": "anthropogenic_hazards/webservice/is-epos_platform/episode-elements/THE_GEYSERS_Prati_9_and_Prati_29_cluster"
          },
          {
            "relationId": "anthropogenic_hazards/webservice/is-epos_platform/episode-elements/THE_GEYSERS"
          },
          {
            "relationId": "anthropogenic_hazards/webservice/is-epos_platform/episode-elements/VDF"
          },
          {
            "relationId": "anthropogenic_hazards/webservice/is-epos_platform/episode-elements/VD"
          },
          {
            "relationId": "anthropogenic_hazards/webservice/is-epos_platform/episode-elements/PREESE_HALL"
          },
          {
            "relationId": "anthropogenic_hazards/webservice/is-epos_platform/episode-elements/THORESBY_COLLIERY"
          },
          {
            "relationId": "anthropogenic_hazards/webservice/is-epos_platform/episode-elements/ASFORDBY"
          },
          {
            "relationId": "anthropogenic_hazards/webservice/is-epos_platform/episode-elements/NORTHWICH"
          },
          {
            "relationId": "anthropogenic_hazards/webservice/is-epos_platform/episode-elements/OK"
          },
          {
            "relationId": "anthropogenic_hazards/webservice/is-epos_platform/episode-elements/PREESALL_MINE"
          },
          {
            "relationId": "anthropogenic_hazards/webservice/is-epos_platform/episode-elements/GRONINGEN_FIELD"
          },
          {
            "relationId": "anthropogenic_hazards/webservice/is-epos_platform/episode-elements/LUBOCINO"
          },
          {
            "relationId": "anthropogenic_hazards/webservice/is-epos_platform/episode-elements/WYSIN"
          },
          {
            "relationId": "anthropogenic_hazards/webservice/is-epos_platform/episode-elements/SG"
          },
          {
            "relationId": "anthropogenic_hazards/webservice/is-epos_platform/episode-elements/VOUGLANS"
          },
          {
            "relationId": "anthropogenic_hazards/webservice/is-epos_platform/episode-elements/GAZLI"
          },
          {
            "relationId": "anthropogenic_hazards/webservice/is-epos_platform/episode-elements/COTTON_VALLEY"
          },
          {
            "relationId": "anthropogenic_hazards/webservice/is-epos_platform/episode-elements/COOPER_BASIN"
          },
          {
            "relationId": "anthropogenic_hazards/webservice/is-epos_platform/episode-elements/BOGDANKA"
          },
          {
            "relationId": "anthropogenic_hazards/webservice/is-epos_platform/episode-elements/LAI_CHAU"
          },
          {
            "relationId": "anthropogenic_hazards/webservice/is-epos_platform/episode-elements/EMILIA_ROMAGNA"
          },
          {
            "relationId": "anthropogenic_hazards/webservice/is-epos_platform/episode-elements/KWK_Piast_Ziemowit"
          },
          {
            "relationId": "anthropogenic_hazards/webservice/is-epos_platform/episode-elements/KWK_Ruda_Bielszowice"
          },
          {
            "relationId": "anthropogenic_hazards/webservice/is-epos_platform/episode-elements/MUSE1_Regional_Polygon"
          },
          {
            "relationId": "anthropogenic_hazards/webservice/is-epos_platform/episode-elements/KWK_ROW_Rydultowy"
          },
          {
            "relationId": "anthropogenic_hazards/webservice/is-epos_platform/episode-elements/ASPO"
          },
          {
            "relationId": "anthropogenic_hazards/webservice/is-epos_platform/episode-elements/JAGUARS"
          },
          {
            "relationId": "anthropogenic_hazards/webservice/is-epos_platform/episode-elements/AE_LAB-EXPERIMENT"
          },
          {
            "relationId": "anthropogenic_hazards/webservice/is-epos_platform/episode-elements/STIMTEC"
          }
        ]
      },
      {
        "version": "main",
        "name": "nfo-vpvs-covjson-go",
        "description": "plugin description",
        "version_type": "branch",
        "repository": "https://gitlab.com/epos-eric/epos/converter-plugins/nfo-vpvs-covjson-go.git",
        "runtime": "binary",
        "executable": "binary",
        "arguments": "",
        "enabled": true,
        "inputFormat": "application/json",
        "outputFormat": "application/epos.covjson",
        "relations": [
          {
            "relationId": "https://www.epos-eu.org/epos-dcat-ap/NearFaultObservatory/TABOO/VPVS/WebService/001/Operation/001"
          },
          {
            "relationId": "https://www.epos-eu.org/epos-dcat-ap/NearFaultObservatory/KOERI/VPVS/WebService/001/Operation/001"
          },
          {
            "relationId": "https://www.epos-eu.org/epos-dcat-ap/NearFaultObservatory/irpinia/vpvs/Operation/001"
          },
          {
            "relationId": "https://www.epos-eu.org/epos-dcat-ap/NearFaultObservatory/NIEP/VPVS/WebService/001/Operation/001"
          },
          {
            "relationId": "https://www.epos-eu.org/epos-dcat-ap/NearFaultObservatory/CRL/VPVS/WebService/001/Operation/001"
          }
        ]
      },
      {
        "version": "main",
        "name": "satd-linked-plugin",
        "description": "plugin description",
        "version_type": "branch",
        "repository": "https://gitlab.com/epos-eric/epos/converter-plugins/satd-linked-plugin.git",
        "runtime": "binary",
        "executable": "binary",
        "arguments": "",
        "enabled": true,
        "inputFormat": "application/json",
        "outputFormat": "application/epos.geo+json",
        "relations": [
          {
            "relationId": "https://catalog.terradue.com/gep-epos/SatelliteObservations/WebService/WRAPPED_INTERFEROGRAM/Operation/Search"
          },
          {
            "relationId": "https://catalog.terradue.com/gep-epos/SatelliteObservations/WebService/UNWRAPPED_INTERFEROGRAM/Operation/Search"
          },
          {
            "relationId": "https://catalog.terradue.com/gep-epos/SatelliteObservations/WebService/SPATIAL_COHERENCE/Operation/Search"
          }
        ]
      },
      {
        "version": "main",
        "name": "satd-plugin",
        "description": "plugin description",
        "version_type": "branch",
        "repository": "https://gitlab.com/epos-eric/epos/converter-plugins/satd-plugin.git",
        "runtime": "java",
        "executable": "target/SATDPlugin-main-jar-with-dependencies.jar",
        "arguments": "org.epos.satellite.core.SATDInvoker",
        "enabled": true,
        "inputFormat": "application/json",
        "outputFormat": "application/epos.geo+json",
        "relations": [
          {
            "relationId": "https://catalog.terradue.com/gep-epos/SatelliteObservations/WebService/LOS_DISPLACEMENT_TIMESERIES/Operation/Search"
          },
          {
            "relationId": "https://catalog.terradue.com/gep-epos/SatelliteObservations/WebService/MAP_OF_LOS_VECTOR/Operation/Search"
          },
          {
            "relationId": "https://catalog.terradue.com/gep-epos/SatelliteObservations/WebService/INTERFEROGRAM_APS_GLOBAL_MODEL/Operation/Search"
          },
          {
            "relationId": "https://catalog.terradue.com/gep-epos/SatelliteObservations/WebService/DEM_RADAR_GEOMETRY/Operation/Search"
          },
          {
            "relationId": "https://catalog.terradue.com/gep-epos/SatelliteObservations/WebService/LOOKUP_TABLE_RADAR2GROUND_COORDINATES/Operation/Search"
          }
        ]
      },
      {
        "version": "main",
        "name": "nfo-co2-covjson",
        "description": "plugin description",
        "version_type": "branch",
        "repository": "https://gitlab.com/epos-eric/epos/converter-plugins/nfo-co2-covjson.git",
        "runtime": "java",
        "executable": "target/covjson-co2-main-jar-with-dependencies.jar",
        "arguments": "org.epos.nfo.co2.NFOCO2Invoker",
        "enabled": true,
        "inputFormat": "application/json",
        "outputFormat": "application/epos.covjson",
        "relations": [
          {
            "relationId": "https://www.epos-eu.org/epos-dcat-ap/NearFaultObservatory/TABOO/METEO/WebService/001/Operation/001"
          },
          {
            "relationId": "https://www.epos-eu.org/epos-dcat-ap/NearFaultObservatory/TABOO/CO2/WebService/001/Operation/001"
          }
        ]
      },
      {
        "version": "main",
        "name": "nfo-co2-plugin",
        "description": "plugin description",
        "version_type": "branch",
        "repository": "https://gitlab.com/epos-eric/epos/converter-plugins/nfo-co2-plugin.git",
        "runtime": "java",
        "executable": "target/WP09_NFOCO2Plugin-main-jar-with-dependencies.jar",
        "arguments": "org.epos.nfo.core.NFOInvoker",
        "enabled": true,
        "inputFormat": "application/json",
        "outputFormat": "application/epos.geo+json",
        "relations": [
          {
            "relationId": "https://www.epos-eu.org/epos-dcat-ap/NearFaultObservatory/TABOO/CO2_STATIONS/WebService/001/Operation/001"
          }
        ]
      },
      {
        "version": "main",
        "name": "nfo-radon-covjson-go",
        "description": "plugin description",
        "version_type": "branch",
        "repository": "https://gitlab.com/epos-eric/epos/converter-plugins/nfo-radon-covjson-go.git",
        "runtime": "binary",
        "executable": "binary",
        "arguments": "",
        "enabled": true,
        "inputFormat": "application/json",
        "outputFormat": "application/epos.covjson",
        "relations": [
          {
            "relationId": "https://www.epos-eu.org/epos-dcat-ap/NearFaultObservatory/TABOO/RADON/WebService/001/Operation/001"
          },
          {
            "relationId": "https://radon.infp.ro/epos-dcat-ap/NearFaultObjservatory/NIEP/RADON/Webservice/001/Operation/001"
          },
          {
            "relationId": "https://www.epos-eu.org/epos-dcat-ap/NearFaultObservatory/KOERI/RADON/WebService/001/Operation/001"
          }
        ]
      },
      {
        "version": "main",
        "name": "quakeml-plugin",
        "description": "plugin description",
        "version_type": "branch",
        "repository": "https://gitlab.com/epos-eric/epos/converter-plugins/quakeml-plugin.git",
        "runtime": "java",
        "executable": "target/QuakeML-main-jar-with-dependencies.jar",
        "arguments": "org.epos.quakeml.core.QuakeMLInvoker",
        "enabled": true,
        "inputFormat": "application/xml",
        "outputFormat": "application/epos.geo+json",
        "relations": [
          {
            "relationId": "https://www.epos-eu.org/epos-dcat-ap/Seismology/WebService/AHEAD/restful/macroseismic/Operation"
          },
          {
            "relationId": "https://www.epos-eu.org/epos-dcat-ap/Seismology/Dataset/001/EMSC/operation"
          },
          {
            "relationId": "https://www.epos-eu.org/epos-dcat-ap/NearFaultObservatory/CRL/event/Webservice/001/Operation/001"
          },
          {
            "relationId": "https://www.epos-eu.org/epos-dcat-ap/NearFaultObservatory/irpinia/HistEQ/WebService/001/Operation/001"
          },
          {
            "relationId": "https://www.epos-eu.org/epos-dcat-ap/NearFaultObservatory/KOERI/HistEQ/WebService/001/Operation/001"
          },
          {
            "relationId": "https://www.epos-eu.org/epos-dcat-ap/NearFaultObservatory/TABOO/HistEQ/WebService/001/Operation/001"
          },
          {
            "relationId": "https://www.epos-eu.org/epos-dcat-ap/NearFaultObservatory/SED/HistEQ/WebService/001/Operation/001"
          },
          {
            "relationId": "https://www.epos-eu.org/epos-dcat-ap/NearFaultObservatory/NIEP/HistEQ/WebService/001/Operation/001"
          },
          {
            "relationId": "https://www.epos-eu.org/epos-dcat-ap/NearFaultObservatory/irpinia/event/Operation/001"
          },
          {
            "relationId": "https://www.epos-eu.org/epos-dcat-ap/NearFaultObservatory/TABOO/Event/WebService/001/Operation/001"
          },
          {
            "relationId": "https://www.epos-eu.org/epos-dcat-ap/NearFaultObservatory/NIEP/Event/WebService/001/Operation/001"
          },
          {
            "relationId": "https://www.epos-eu.org/epos-dcat-ap/NearFaultObservatory/KOERI/Event/WebService/001/Operation/001"
          },
          {
            "relationId": "https://www.epos-eu.org/epos-dcat-ap/volcano-observations/WebService/DDSS0027/Operation/IPGP"
          },
          {
            "relationId": "https://www.epos-eu.org/epos-dcat-ap/Seismology/WebService/AHEAD/restful/fdsnws-event/Operation"
          },
          {
            "relationId": "https://www.epos-eu.org/epos-dcat-ap/NearFaultObservatory/CRL/HistEQ/WebService/001/Operation/001"
          }
        ]
      },
      {
        "version": "main",
        "name": "nfo-radon-plugin",
        "description": "plugin description",
        "version_type": "branch",
        "repository": "https://gitlab.com/epos-eric/epos/converter-plugins/nfo-radon-plugin.git",
        "runtime": "java",
        "executable": "target/WP09-NFORadon-main-jar-with-dependencies.jar",
        "arguments": "org.epos.nfo.core.NFOInvoker",
        "enabled": true,
        "inputFormat": "application/json",
        "outputFormat": "application/epos.geo+json",
        "relations": [
          {
            "relationId": "https://www.epos-eu.org/epos-dcat-ap/NearFaultObservatory/TABOO/RADON_STATIONS/WebService/001/Operation/001"
          },
          {
            "relationId": "https://radon.infp.ro/epos-dcat-ap/NearFaultObjservatory/NIEP/RADON_STATIONS/Webservice/001/Operation/001"
          },
          {
            "relationId": "https://www.epos-eu.org/epos-dcat-ap/NearFaultObservatory/KOERI/RADON_STATIONS/WebService/001/Operation/001"
          }
        ]
      },
      {
        "version": "main",
        "name": "bibliography-no-conversion",
        "description": "plugin description",
        "version_type": "branch",
        "repository": "https://gitlab.com/epos-eric/epos/converter-plugins/bibliography-no-conversion.git",
        "runtime": "java",
        "executable": "target/WP08_BibliographyPlugin-main-jar-with-dependencies.jar",
        "arguments": "org.epos.bibliography.core.BibliographyInvoker",
        "enabled": true,
        "inputFormat": "application/json",
        "outputFormat": "application/epos.table.geo+json",
        "relations": [
          {
            "relationId": "https://www.epos-eu.org/epos-dcat-ap/Seismology/WebService/AHEAD/restful/bibliography/Operation"
          }
        ]
      },
      {
        "version": "main",
        "name": "msl-plugin",
        "description": "plugin description",
        "version_type": "branch",
        "repository": "https://gitlab.com/epos-eric/epos/converter-plugins/msl-plugin.git",
        "runtime": "java",
        "executable": "target/WP16_MSLPlugin-main-jar-with-dependencies.jar",
        "arguments": "org.epos.msl.core.MSLInvoker",
        "enabled": true,
        "inputFormat": "application/json",
        "outputFormat": "application/epos.table.geo+json",
        "relations": [
          {
            "relationId": "https://www.epos-eu.org/multi-scale-laboratories/WebService/001/Operation/001"
          },
          {
            "relationId": "https://www.epos-eu.org/multi-scale-laboratories/WebService/002/Operation/002"
          },
          {
            "relationId": "https://www.epos-eu.org/multi-scale-laboratories/WebService/003/Operation/003"
          },
          {
            "relationId": "https://www.epos-eu.org/multi-scale-laboratories/WebService/006/Operation/006"
          },
          {
            "relationId": "https://www.epos-eu.org/multi-scale-laboratories/WebService/011/Operation/011"
          },
          {
            "relationId": "https://www.epos-eu.org/multi-scale-laboratories/WebService/013/Operation/013"
          },
          {
            "relationId": "https://www.epos-eu.org/multi-scale-laboratories/WebService/012/Operation/012"
          }
        ]
      },
      {
        "version": "main",
        "name": "satd-plugin-models",
        "description": "plugin description",
        "version_type": "branch",
        "repository": "https://gitlab.com/epos-eric/epos/converter-plugins/satd-plugin-models.git",
        "runtime": "java",
        "executable": "target/SATDPluginModels-main-jar-with-dependencies.jar",
        "arguments": "org.epos.satellite.core.SATDInvoker",
        "enabled": true,
        "inputFormat": "application/json",
        "outputFormat": "application/epos.geo+json",
        "relations": [
          {
            "relationId": "https://catalog.terradue.com/gep-epos/SatelliteObservations/WebService/MODEL/Operation/Search"
          }
        ]
      },
      {
        "version": "main",
        "name": "ah-list-of-applications-plugin",
        "description": "plugin description",
        "version_type": "branch",
        "repository": "https://gitlab.com/epos-eric/epos/converter-plugins/ah-list-of-applications-plugin.git",
        "runtime": "java",
        "executable": "target/WP14_List_of_applications-main-jar-with-dependencies.jar",
        "arguments": "org.epos.ahapplications.core.AHApplicationsInvoker",
        "enabled": true,
        "inputFormat": "application/json",
        "outputFormat": "application/epos.table.geo+json",
        "relations": [
          {
            "relationId": "anthropogenic_hazards/webservice/is-epos_platform/apps/sspe"
          },
          {
            "relationId": "anthropogenic_hazards/webservice/is-epos_platform/apps/sfm"
          },
          {
            "relationId": "anthropogenic_hazards/webservice/is-epos_platform/apps/esa"
          },
          {
            "relationId": "anthropogenic_hazards/webservice/is-epos_platform/apps/hra"
          },
          {
            "relationId": "anthropogenic_hazards/webservice/is-epos_platform/apps/dt"
          },
          {
            "relationId": "anthropogenic_hazards/webservice/is-epos_platform/apps/conv"
          },
          {
            "relationId": "anthropogenic_hazards/webservice/is-epos_platform/apps/rt"
          },
          {
            "relationId": "anthropogenic_hazards/webservice/is-epos_platform/apps/vis"
          }
        ]
      },
      {
        "version": "main",
        "name": "ah-episodes-plugin",
        "description": "plugin description",
        "version_type": "branch",
        "repository": "https://gitlab.com/epos-eric/epos/converter-plugins/ah-episodes-plugin.git",
        "runtime": "java",
        "executable": "target/WP14_Episodes-main-jar-with-dependencies.jar",
        "arguments": "org.epos.ahepisodes.core.AHEpisodesInvoker",
        "enabled": true,
        "inputFormat": "application/json",
        "outputFormat": "application/epos.geo+json",
        "relations": [
          {
            "relationId": "anthropogenic_hazards/webservice/is-epos_platform/episodes"
          }
        ]
      },
      {
        "version": "main",
        "name": "satd-wms",
        "description": "plugin description",
        "version_type": "branch",
        "repository": "https://gitlab.com/epos-eric/epos/converter-plugins/satd-wms.git",
        "runtime": "java",
        "executable": "target/SATDWMSPlugin-main-jar-with-dependencies.jar",
        "arguments": "org.epos.satellite.core.SATDWMSInvoker",
        "enabled": true,
        "inputFormat": "application/json",
        "outputFormat": "application/epos.geo+json",
        "relations": []
      },
      {
        "version": "main",
        "name": "seismo-beachballs",
        "description": "plugin description",
        "version_type": "branch",
        "repository": "https://gitlab.com/epos-eric/epos/converter-plugins/seismo-beachballs.git",
        "runtime": "binary",
        "executable": "seismo-beachballs",
        "arguments": "",
        "enabled": true,
        "inputFormat": "application/json",
        "outputFormat": "application/epos.geo+json",
        "relations": [
          {
            "relationId": "https://www.epos-eu.org/epos-dcat-ap/Seismology/Dataset/003/EMSC/operation"
          }
        ]
      },
      {
        "version": "main",
        "name": "seismo-fdsnevent",
        "description": "plugin description",
        "version_type": "branch",
        "repository": "https://gitlab.com/epos-eric/epos/converter-plugins/seismo-fdsnevent.git",
        "runtime": "binary",
        "executable": "seismo-fdsnevent",
        "arguments": "",
        "enabled": true,
        "inputFormat": "application/xml",
        "outputFormat": "application/epos.covjson",
        "relations": [
          {
            "relationId": "https://www.epos-eu.org/epos-dcat-ap/Seismology/Dataset/001/EMSC/operation"
          },
          {
            "relationId": "https://www.epos-eu.org/epos-dcat-ap/Seismology/WebService/AHEAD/restful/fdsnws-event/Operation"
          },
          {
            "relationId": "https://www.epos-eu.org/epos-dcat-ap/NearFaultObservatory/CRL/event/Webservice/001/Operation/001"
          },
          {
            "relationId": "https://www.epos-eu.org/epos-dcat-ap/NearFaultObservatory/irpinia/event/Operation/001"
          },
          {
            "relationId": "https://www.epos-eu.org/epos-dcat-ap/NearFaultObservatory/KOERI/Event/WebService/001/Operation/001"
          },
          {
            "relationId": "https://www.epos-eu.org/epos-dcat-ap/NearFaultObservatory/TABOO/Event/WebService/001/Operation/001"
          },
          {
            "relationId": "https://www.epos-eu.org/epos-dcat-ap/NearFaultObservatory/NIEP/Event/WebService/001/Operation/001"
          },
          {
            "relationId": "https://www.epos-eu.org/epos-dcat-ap/NearFaultObservatory/CRL/HistEQ/WebService/001/Operation/001"
          },
          {
            "relationId": "https://www.epos-eu.org/epos-dcat-ap/NearFaultObservatory/irpinia/HistEQ/WebService/001/Operation/001"
          },
          {
            "relationId": "https://www.epos-eu.org/epos-dcat-ap/NearFaultObservatory/KOERI/HistEQ/WebService/001/Operation/001"
          },
          {
            "relationId": "https://www.epos-eu.org/epos-dcat-ap/NearFaultObservatory/TABOO/HistEQ/WebService/001/Operation/001"
          },
          {
            "relationId": "https://www.epos-eu.org/epos-dcat-ap/NearFaultObservatory/SED/HistEQ/WebService/001/Operation/001"
          },
          {
            "relationId": "https://www.epos-eu.org/epos-dcat-ap/NearFaultObservatory/NIEP/HistEQ/WebService/001/Operation/001"
          },
          {
            "relationId": "https://www.epos-eu.org/epos-dcat-ap/volcano-observations/WebService/DDSS0027/Operation/IPGP"
          }
        ]
      },
      {
        "version": "main",
        "name": "seismo-wfcatalog",
        "description": "plugin description",
        "version_type": "branch",
        "repository": "https://gitlab.com/epos-eric/epos/converter-plugins/seismo-wfcatalog.git",
        "runtime": "binary",
        "executable": "seismo-wfcatalog",
        "arguments": "",
        "enabled": true,
        "inputFormat": "application/xml",
        "outputFormat": "application/epos.graph.covjson",
        "relations": [
          {
            "relationId": "https://www.epos-eu.org/epos-dcat-ap/Seismology/WebService/003/Operation/001/RESIF"
          },
          {
            "relationId": "https://www.epos-eu.org/epos-dcat-ap/Seismology/WebService/003/Operation/003/BGR"
          },
          {
            "relationId": "https://www.epos-eu.org/epos-dcat-ap/Seismology/WebService/003/Operation/003/GFZ"
          },
          {
            "relationId": "https://www.epos-eu.org/epos-dcat-ap/Seismology/WebService/003/Operation/003/ICGC"
          },
          {
            "relationId": "https://www.epos-eu.org/epos-dcat-ap/Seismology/WebService/003/Operation/003/INGV"
          },
          {
            "relationId": "https://www.epos-eu.org/epos-dcat-ap/Seismology/WebService/003/Operation/003/KOERI"
          },
          {
            "relationId": "https://www.epos-eu.org/epos-dcat-ap/Seismology/WebService/003/Operation/003/LMU"
          },
          {
            "relationId": "https://www.epos-eu.org/epos-dcat-ap/Seismology/WebService/003/Operation/003/NIEP"
          },
          {
            "relationId": "https://www.epos-eu.org/epos-dcat-ap/Seismology/WebService/003/Operation/003/NOA"
          },
          {
            "relationId": "https://www.epos-eu.org/epos-dcat-ap/Seismology/WebService/003/Operation/003/ODC"
          },
          {
            "relationId": "https://www.epos-eu.org/epos-dcat-ap/Seismology/WebService/003/Operation/003/SED"
          },
          {
            "relationId": "https://www.epos-eu.org/epos-dcat-ap/Seismology/WebService/003/Operation/003/UIB"
          },
          {
            "relationId": "https://www.epos-eu.org/epos-dcat-ap/Seismology/WebService/004/Operation/004/FEDERATOR"
          },
          {
            "relationId": "https://www.epos-eu.org/epos-dcat-ap/Seismology/WebService/003/Operation/003/BGS"
          }
        ]
      },
      {
        "version": "main",
        "name": "stationxml-plugin",
        "description": "plugin description",
        "version_type": "branch",
        "repository": "https://gitlab.com/epos-eric/epos/converter-plugins/stationxml-plugin.git",
        "runtime": "java",
        "executable": "target/StationXML-main-jar-with-dependencies.jar",
        "arguments": "org.epos.stationxml.core.StationXMLInvoker",
        "enabled": true,
        "inputFormat": "application/xml",
        "outputFormat": "application/epos.geo+json",
        "relations": [
          {
            "relationId": "https://www.epos-eu.org/epos-dcat-ap/NearFaultObservatory/TABOO/geophysics/WebService/002/Operation/002"
          },
          {
            "relationId": "https://www.epos-eu.org/epos-dcat-ap/NearFaultObservatory/KARST/SEISMIC_STATION/WebService/001/Operation/001"
          },
          {
            "relationId": "https://www.epos-eu.org/epos-dcat-ap/Seismology/WebService/002/Operation/002/KOERI"
          },
          {
            "relationId": "https://www.epos-eu.org/epos-dcat-ap/Seismology/WebService/002/Operation/002/BGR"
          },
          {
            "relationId": "https://www.epos-eu.org/epos-dcat-ap/Seismology/WebService/008/Operation/008/FEDERATOR"
          },
          {
            "relationId": "https://www.epos-eu.org/epos-dcat-ap/Seismology/WebService/002/Operation/002/GFZ"
          },
          {
            "relationId": "https://www.epos-eu.org/epos-dcat-ap/Seismology/WebService/002/Operation/002/ICGC"
          },
          {
            "relationId": "https://www.epos-eu.org/epos-dcat-ap/Seismology/WebService/002/Operation/002/INGV"
          },
          {
            "relationId": "https://www.epos-eu.org/epos-dcat-ap/Seismology/WebService/002/Operation/002/LMU"
          },
          {
            "relationId": "https://www.epos-eu.org/epos-dcat-ap/Seismology/WebService/002/Operation/002/NIEP"
          },
          {
            "relationId": "https://www.epos-eu.org/epos-dcat-ap/Seismology/WebService/002/Operation/002/NOA"
          },
          {
            "relationId": "https://www.epos-eu.org/epos-dcat-ap/Seismology/WebService/002/Operation/002/SED"
          },
          {
            "relationId": "https://www.epos-eu.org/epos-dcat-ap/Seismology/WebService/002/Operation/002/UIB"
          },
          {
            "relationId": "https://www.epos-eu.org/epos-dcat-ap/Seismology/WebService/002/Operation/002/ODC"
          },
          {
            "relationId": "https://www.epos-eu.org/epos-dcat-ap/Seismology/WebService/002/Operation/001/RESIF"
          },
          {
            "relationId": "https://www.epos-eu.org/epos-dcat-ap/Seismology/WebService/002/Operation/002/BGS"
          },
          {
            "relationId": "https://www.epos-eu.org/epos-dcat-ap/NearFaultObservatory/NIEP/INFRASOUND_STATION/WebService/001/Operation/001"
          },
          {
            "relationId": "https://radon.infp.ro/epos-dcat-ap/NearFaultObjservatory/NIEP/RADON_STATIONS/Webservice/001/Operation/001"
          },
          {
            "relationId": "https://www.epos-eu.org/epos-dcat-ap/NearFaultObservatory/NIEP/SEISMIC_STATION/WebService/001/Operation/001"
          },
          {
            "relationId": "https://www.epos-eu.org/epos-dcat-ap/NearFaultObservatory/CRL/WebService/002/Operation/002/NOA"
          },
          {
            "relationId": "https://www.epos-eu.org/epos-dcat-ap/NearFaultObservatory/CRL/WebService/002/Operation/002/RESIF"
          },
          {
            "relationId": "https://www.epos-eu.org/epos-dcat-ap/NearFaultObservatory/CRL/geophysics/WebService/002/Operation/002/RESIF"
          },
          {
            "relationId": "https://www.epos-eu.org/epos-dcat-ap/NearFaultObservatory/irpinia/station/Operation/001"
          },
          {
            "relationId": "https://www.epos-eu.org/epos-dcat-ap/NearFaultObservatory/KOERI/SEISMIC_STATION/WebService/001/Operation/001"
          },
          {
            "relationId": "https://www.epos-eu.org/epos-dcat-ap/NearFaultObservatory/TABOO/SEISMIC_STATION/WebService/001/Operation/001"
          },
          {
            "relationId": "https://www.epos-eu.org/epos-dcat-ap/volcano-observations/WebService/DDSS001-2/Operation/station/RESIF"
          },
          {
            "relationId": "https://www.epos-eu.org/epos-dcat-ap/volcano-observations/WebService/DDSS005/Operation/station/IPGP"
          },
          {
            "relationId": "https://www.epos-eu.org/epos-dcat-ap/volcano-observations/WebService/DDSS006/Operation/station/IPGP"
          }
        ]
      },
      {
        "version": "main",
        "name": "tsu-hazard-model",
        "description": "plugin description",
        "version_type": "branch",
        "repository": "https://gitlab.com/epos-eric/epos/converter-plugins/tsu-hazard-model.git",
        "runtime": "java",
        "executable": "target/TSU-Hazard-Model-main-jar-with-dependencies.jar",
        "arguments": "org.epos.tsu.core.TSUInvoker",
        "enabled": true,
        "inputFormat": "application/json",
        "outputFormat": "application/epos.geo+json",
        "relations": [
          {
            "relationId": "Tsunami/NEAMTHM18/Operation/NEAMTHM18_Full_Dataset"
          }
        ]
      },
      {
        "version": "main",
        "name": "vol-bulkrocketna",
        "description": "plugin description",
        "version_type": "branch",
        "repository": "https://gitlab.com/epos-eric/epos/converter-plugins/vol-bulkrocketna.git",
        "runtime": "java",
        "executable": "target/VOLBulkRockEtna-main-jar-with-dependencies.jar",
        "arguments": "org.epos.vol.core.VOLInvoker",
        "enabled": true,
        "inputFormat": "application/json",
        "outputFormat": "application/epos.geo+json",
        "relations": [
          {
            "relationId": "rest/bulk-rock/operation"
          }
        ]
      },
      {
        "version": "main",
        "name": "vol-generic-plugin",
        "description": "plugin description",
        "version_type": "branch",
        "repository": "https://gitlab.com/epos-eric/epos/converter-plugins/vol-generic-plugin.git",
        "runtime": "java",
        "executable": "target/VOLGeneric-main-jar-with-dependencies.jar",
        "arguments": "org.epos.vol.core.VOLInvoker",
        "enabled": true,
        "inputFormat": "application/json",
        "outputFormat": "application/epos.geo+json",
        "relations": [
          {
            "relationId": "https://www.epos-eu.org/epos-dcat-ap/volcano-observations/WebService/DDSS0032/Operation/report/IPGP"
          },
          {
            "relationId": "EarthquakeParameters/INGV/DDSS-027/operation"
          },
          {
            "relationId": "MultiParameterStationsListItaly/INGV/DDSS-067/operation"
          }
        ]
      },
      {
        "version": "main",
        "name": "vol-generic-table-plugin",
        "description": "plugin description",
        "version_type": "branch",
        "repository": "https://gitlab.com/epos-eric/epos/converter-plugins/vol-generic-table-plugin.git",
        "runtime": "java",
        "executable": "target/VOLGenericTable-main-jar-with-dependencies.jar",
        "arguments": "org.epos.vol.core.VOLInvoker",
        "enabled": true,
        "inputFormat": "application/json",
        "outputFormat": "application/epos.table.geo+json",
        "relations": []
      },
      {
        "version": "main",
        "name": "vol-interferograms-plugin",
        "description": "plugin description",
        "version_type": "branch",
        "repository": "https://gitlab.com/epos-eric/epos/converter-plugins/vol-interferograms-plugin.git",
        "runtime": "java",
        "executable": "target/VOLInterferogram-main-jar-with-dependencies.jar",
        "arguments": "org.epos.volinterferogram.core.VOLInterferogramInvoker",
        "enabled": true,
        "inputFormat": "application/json",
        "outputFormat": "application/epos.geo+json",
        "relations": [
          {
            "relationId": "INTERFEROGRAMS/INGV/DDSS-050/operation"
          }
        ]
      },
      {
        "version": "main",
        "name": "vol-lava-flow-invasion",
        "description": "plugin description",
        "version_type": "branch",
        "repository": "https://gitlab.com/epos-eric/epos/converter-plugins/vol-lava-flow-invasion.git",
        "runtime": "binary",
        "executable": "vol-lava-flow-invasion",
        "arguments": "",
        "enabled": true,
        "inputFormat": "application/json",
        "outputFormat": "application/epos.geo+json",
        "relations": [
          {
            "relationId": "HazardMap/Lavaflow/operation"
          },
          {
            "relationId": "SusceptibilityMap/operation"
          },
          {
            "relationId": "HazardMap/PDCs/operation"
          },
          {
            "relationId": "HazardMap/Probabilistic/operation"
          }
        ]
      },
      {
        "version": "main",
        "name": "vol-projects-plugin",
        "description": "plugin description",
        "version_type": "branch",
        "repository": "https://gitlab.com/epos-eric/epos/converter-plugins/vol-projects-plugin.git",
        "runtime": "java",
        "executable": "target/VOLProjects-main-jar-with-dependencies.jar",
        "arguments": "org.epos.volprojects.core.VOLProjectsInvoker",
        "enabled": true,
        "inputFormat": "application/json",
        "outputFormat": "application/epos.table.geo+json",
        "relations": [
          {
            "relationId": "Software/operation"
          }
        ]
      },
      {
        "version": "main",
        "name": "vol-weekly-reports-plugin",
        "description": "plugin description",
        "version_type": "branch",
        "repository": "https://gitlab.com/epos-eric/epos/converter-plugins/vol-weekly-reports-plugin.git",
        "runtime": "java",
        "executable": "target/VOLReports-main-jar-with-dependencies.jar",
        "arguments": "org.epos.volreports.core.VOLReportsInvoker",
        "enabled": true,
        "inputFormat": "application/json",
        "outputFormat": "application/epos.geo+json",
        "relations": [
          {
            "relationId": "REPORTS/INGV/DDSS-031/operation"
          },
          {
            "relationId": "VONA/INGV/DDSS-032/operation"
          }
        ]
      }
    ]
---
{{- if and .Values.jobs.enabled .Values.jobs.pluginPopulator.enabled }}
apiVersion: batch/v1
kind: Job
metadata:
  name: '{{ include "epos-chart.fullname" . }}-pluginpopulator'
  labels:
    {{- include "epos-chart.labels" . | nindent 4 }}
    katenary.v3/component: pluginpopulator
  annotations:
    "helm.sh/hook": post-install,post-upgrade
    "helm.sh/hook-weight": "{{ .Values.jobs.pluginPopulator.hookWeight }}"
    "helm.sh/hook-delete-policy": before-hook-creation,hook-succeeded,hook-failed
    "helm.sh/hook-failure-policy": ignore
spec:
  completions: 1
  parallelism: 1
  backoffLimit: {{ .Values.jobs.pluginPopulator.backoffLimit }}
  activeDeadlineSeconds: {{ .Values.jobs.pluginPopulator.activeDeadlineSeconds }}
  template:
    metadata:
      labels:
        {{- include "epos-chart.selectorLabels" . | nindent 8 }}
        katenary.v3/component: pluginpopulator
    spec:
      restartPolicy: Never
      {{- if .Values.global.imagePullSecrets.enabled }}
      imagePullSecrets:
      - name: {{ .Values.global.imagePullSecrets.secretName }}
      {{- end }}
      
      initContainers:
      # Wait for required services
      {{- range .Values.jobs.pluginPopulator.waitForServices }}
      {{- $service := splitList ":" . }}
      - name: wait-for-{{ index $service 0 | replace "-" "" }}
        image: busybox:latest
        command: ["/bin/sh", "-c"]
        args:
        - |
          echo "Waiting for {{ index $service 0 }}:{{ index $service 1 }}..."
          until nc -z {{ include "epos-chart.fullname" $ }}-{{ index $service 0 }} {{ index $service 1 }}; do
            sleep 2
          done
          echo "✓ {{ index $service 0 }} is ready"
      {{- end }}
      
      containers:
      - name: pluginpopulator-container
        image: '{{ .Values.jobs.pluginPopulator.image }}:{{ .Values.jobs.pluginPopulator.tag }}'
        imagePullPolicy: Always
        env:
        - name: CONVERTER_ENDPOINT
          value: "http://{{ include "epos-chart.fullname" . }}-converterservice:8080/api/converter-service/v1"
        - name: RESOURCES_ENDPOINT
          value: "http://{{ include "epos-chart.fullname" . }}-resourcesservice:8080/api/resources-service/v1"
        {{- if .Values.jobs.pluginPopulator.resources }}
        resources:
          {{ .Values.jobs.pluginPopulator.resources | toYaml | nindent 10 }}
        {{- end }}
        volumeMounts:
        - name: populate
          mountPath: "/populate"
          readOnly: true
      volumes:
      - name: populate
        configMap:
          name: populate
          items:
          - key: "populate.json"
            path: "populate.json"

{{- end }}
EOF
    
    # Job 3: metadatapopulator.yaml (post-install hook, weight 2)
    cat > "$templates_dir/metadatapopulator-job.yaml" << 'EOF'
{{- if and .Values.jobs.enabled .Values.jobs.metadataPopulator.enabled }}
apiVersion: v1
kind: Service
metadata:
  name: '{{ include "epos-chart.fullname" . }}-metadatapopulator'
  labels:
    {{- include "epos-chart.labels" . | nindent 4 }}
    katenary.v3/component: metadatapopulator
  annotations:
    "helm.sh/hook": post-install,post-upgrade
    "helm.sh/hook-weight": "{{ .Values.jobs.metadataPopulator.hookWeight }}"
    "helm.sh/hook-delete-policy": before-hook-creation
spec:
  type: ClusterIP
  ports:
  - port: 80
    targetPort: 80
    protocol: TCP
    name: http
  selector:
    katenary.v3/component: metadatapopulator
---
{{- end }}

{{- if and .Values.jobs.enabled .Values.jobs.metadataPopulator.enabled }}
apiVersion: batch/v1
kind: Job
metadata:
  name: '{{ include "epos-chart.fullname" . }}-metadatapopulator'
  labels:
    {{- include "epos-chart.labels" . | nindent 4 }}
    katenary.v3/component: metadatapopulator
  annotations:
    "helm.sh/hook": post-install,post-upgrade
    "helm.sh/hook-weight": "{{ .Values.jobs.metadataPopulator.hookWeight }}"
    "helm.sh/hook-delete-policy": before-hook-creation
spec:
  completions: 1
  parallelism: 1
  backoffLimit: {{ .Values.jobs.metadataPopulator.backoffLimit }}
  activeDeadlineSeconds: {{ .Values.jobs.metadataPopulator.activeDeadlineSeconds }}
  template:
    metadata:
      labels:
        {{- include "epos-chart.selectorLabels" . | nindent 8 }}
        katenary.v3/component: metadatapopulator
    spec:
      restartPolicy: Never
      {{- if .Values.global.imagePullSecrets.enabled }}
      imagePullSecrets:
      - name: {{ .Values.global.imagePullSecrets.secretName }}
      {{- end }}
      
      initContainers:
      # Wait for required services
      {{- range .Values.jobs.metadataPopulator.waitForServices }}
      {{- $service := splitList ":" . }}
      - name: wait-for-{{ index $service 0 | replace "-" "" }}
        image: busybox:latest
        command: ["/bin/sh", "-c"]
        args:
        - |
          echo "Waiting for {{ index $service 0 }}:{{ index $service 1 }}..."
          until nc -z {{ include "epos-chart.fullname" $ }}-{{ index $service 0 }} {{ index $service 1 }}; do
            sleep 2
          done
          echo "✓ {{ index $service 0 }} is ready"
      {{- end }}
      
      containers:
      - name: metadatapopulator
        image: '{{ .Values.jobs.metadataPopulator.image }}:{{ .Values.jobs.metadataPopulator.tag }}'
        imagePullPolicy: Always
        command: ["/bin/sh", "-c"]
        args:
        - |
          set -eu
          
          log() {
            echo "[$(date '+%Y-%m-%d %H:%M:%S')] [metadatapopulator] $1"
          }
          
          log "Starting metadata population..."

          # Start nginx
          nginx
          log "✓ Nginx started"

          log "Waiting for ingestor-service health check..."
          until curl -fsS "http://{{ include "epos-chart.fullname" . }}-ingestorservice:8080/api/ingestor-service/v1/actuator/health" >/dev/null 2>&1; do
            sleep 2
          done

          log "Registering ontologies..."
          curl -fsS -X POST --header "accept: */*" \
            'http://{{ include "epos-chart.fullname" . }}-ingestorservice:8080/api/ingestor-service/v1/ontology?path=https://raw.githubusercontent.com/epos-eu/EPOS-DCAT-AP/EPOS-DCAT-AP-shapes/epos-dcat-ap_shapes.ttl&securityCode={{ .Values.jobs.metadataPopulator.securityCode }}&name=EPOS-DCAT-AP-V1&type=BASE'

          curl -fsS -X POST --header "accept: */*" \
            'http://{{ include "epos-chart.fullname" . }}-ingestorservice:8080/api/ingestor-service/v1/ontology?path=https://raw.githubusercontent.com/epos-eu/EPOS-DCAT-AP/EPOS-DCAT-AP-v3.0/docs/epos-dcat-ap_v3.0.0_shacl.ttl&securityCode={{ .Values.jobs.metadataPopulator.securityCode }}&name=EPOS-DCAT-AP-V3&type=BASE'

          curl -fsS -X POST --header "accept: */*" \
            'http://{{ include "epos-chart.fullname" . }}-ingestorservice:8080/api/ingestor-service/v1/ontology?path=https://raw.githubusercontent.com/epos-eu/EPOS_Data_Model_Mapping/main/edm-schema-shapes.ttl&securityCode={{ .Values.jobs.metadataPopulator.securityCode }}&name=EDM-TO-DCAT-AP&type=MAPPING'

          log "✓ Ontologies registered"

          sleep 10
          SECONDS=0

          log "Downloading metadata index..."
          files="$(curl -fsS 'http://{{ include "epos-chart.fullname" . }}-metadatapopulator/index.txt' | tr -d '\r' | sed '/^[[:space:]]*$/d')"

          get_group_name() {
            case "$1" in
              *tcs-geomag*) echo 'Geomagnetic%20Observations' ;;
              *tcs-gnss*)   echo 'GNSS%20Data%20and%20Products' ;;
              *tcs-vo*)     echo 'Volcano%20Observations' ;;
              *tcs-gim*)    echo 'Geological%20Information%20and%20Modeling' ;;
              *tcs-seismo*) echo 'Seismology' ;;
              *tcs-msl*)    echo 'Multi-scale%20Laboratories' ;;
              *tcs-tsu*)    echo 'Tsunami' ;;
              *tcs-satd*)   echo 'Satellite%20Data' ;;
              *tcs-nfo*)    echo 'Near%20Fault%20Observatories' ;;
              *tcs-ah*)     echo 'Anthropogenic%20Hazards' ;;
              *)            echo 'ALL' >&2; echo 'ALL' ;;
            esac
          }

          max="{{ .Values.jobs.metadataPopulator.maxParallel }}"
          count=0
          log "Starting parallel metadata ingestion (MAX_PARALLEL=$max)"

          for i in ${files}; do
            filename="${i##*/}"
            groupname="$(get_group_name "$i")"
            log "Processing $i (group=$groupname)"
            (
              curl -fsS -X POST --header "accept: */*" \
                "http://{{ include "epos-chart.fullname" . }}-ingestorservice:8080/api/ingestor-service/v1/populate?path=http://{{ include "epos-chart.fullname" . }}-metadatapopulator/$filename&securityCode={{ .Values.jobs.metadataPopulator.securityCode }}&model=EPOS-DCAT-AP-V1&mapping=EDM-TO-DCAT-AP&type=single&metadataGroup=$groupname"
              log "✓ Completed $i"
            ) &
            count=$((count + 1))
            if [ $((count % max)) -eq 0 ]; then
              wait
            fi
          done

          wait
          duration=$SECONDS
          log "✓ Total ingestion time: $((duration/60))m $((duration%60))s"

          curl -fsS -X POST --header "accept: application/json" "http://{{ include "epos-chart.fullname" . }}-resourcesservice:8080/api/resources-service/v1/invalidate"

          log "Metadata population completed successfully!"
          
        ports:
        - containerPort: 80
          name: http

        {{- if .Values.jobs.metadataPopulator.resources }}
        resources:
          {{ .Values.jobs.metadataPopulator.resources | toYaml | nindent 10 }}
        {{- end }}
{{- end }}
EOF

    echo "✅ Created initialization job templates:"
    echo "  • init-db-job.yaml (pre-install hook)"
    echo "  • pluginpopulator-job.yaml (post-install hook, weight 1)"
    echo "  • metadatapopulator-job.yaml (post-install hook, weight 2)"
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
echo "🏗️  Creating initialization jobs..."
create_initialization_jobs "$CHART_DIR/templates"

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
echo "📝 Updating chart values.yaml with global and jobs configuration..."

VALUES_FILE="$CHART_DIR/values.yaml"

if [ -f "$VALUES_FILE" ]; then
    # Create backup
    cp "$VALUES_FILE" "${VALUES_FILE}.backup"
    echo "  💾 Created backup: ${VALUES_FILE}.backup"
    
    # Remove any existing global and jobs sections
    if grep -q "^global:" "$VALUES_FILE"; then
        echo "  🗑️  Removing existing global section..."
        sed -i '/^global:/,/^[a-zA-Z]/{/^[a-zA-Z]/!d; /^global:/d;}' "$VALUES_FILE"
    fi
    
    if grep -q "^jobs:" "$VALUES_FILE"; then
        echo "  🗑️  Removing existing jobs section..."
        sed -i '/^jobs:/,/^[a-zA-Z]/{/^[a-zA-Z]/!d; /^jobs:/d;}' "$VALUES_FILE"
    fi
    
    # Extract configurations from external config files
    echo "  📥 Extracting global configuration from $GLOBAL_CONFIG_FILE..."
    GLOBAL_CONTENT=$(extract_yaml_section "$GLOBAL_CONFIG_FILE" "global")
    
    echo "  📥 Extracting jobs configuration from $JOBS_CONFIG_FILE..."
    JOBS_CONTENT=$(extract_yaml_section "$JOBS_CONFIG_FILE" "jobs")
    
    if [ -n "$GLOBAL_CONTENT" ] && [ -n "$JOBS_CONTENT" ]; then
        echo "  ✅ Both configurations extracted successfully"
        
        # Create new values.yaml with configurations at the top
        {
            echo "# Global configuration (imported from $GLOBAL_CONFIG_FILE)"
            echo "$GLOBAL_CONTENT"
            echo ""
            echo "# Jobs configuration (imported from $JOBS_CONFIG_FILE)" 
            echo "$JOBS_CONTENT"
            echo ""
            echo "# Chart-specific configuration"
            cat "$VALUES_FILE"
        } > "${VALUES_FILE}.tmp"
        
        mv "${VALUES_FILE}.tmp" "$VALUES_FILE"
        echo "  ✅ Added global and jobs configuration to values.yaml"
    else
        echo "  ⚠️  Could not extract configurations from template files"
        echo "  💡 Make sure the files contain 'global:' and 'jobs:' sections"
        mv "${VALUES_FILE}.backup" "$VALUES_FILE"
        exit 1
    fi
    
    # Update the secret name in the imported global config if it differs
    if [ -n "$SECRET_NAME" ] && [ "$SECRET_NAME" != "epos-registry-secret" ]; then
        echo "  🔧 Updating secret name to: $SECRET_NAME"
        sed -i "s/secretName: .*/secretName: \"$SECRET_NAME\"/" "$VALUES_FILE"
    fi
    
    echo "  ✅ Successfully updated values.yaml with global and jobs configuration"
    
else
    echo "  ❌ values.yaml not found in $CHART_DIR"
    exit 1
fi

# Verify the result
echo ""
echo "🔍 Verifying configuration in values.yaml..."
if grep -A 5 "^global:" "$VALUES_FILE" >/dev/null && grep -A 5 "^jobs:" "$VALUES_FILE" >/dev/null; then
    echo "✅ Global and jobs sections successfully added to values.yaml"
    echo ""
    echo "📋 Configuration preview:"
    echo "Global configuration:"
    echo "$(grep -A 10 "^global:" "$VALUES_FILE" | head -15)"
    echo "..."
    echo ""
    echo "Jobs configuration:"
    echo "$(grep -A 15 "^jobs:" "$VALUES_FILE" | head -20)"
    echo "..."
else
    echo "❌ Failed to add global and/or jobs sections to values.yaml"
    exit 1
fi

echo ""
echo "🎉 Docker registry secret and initialization jobs configuration complete!"
echo ""
echo "📋 Configuration summary:"
echo "  • Global config template: $GLOBAL_CONFIG_FILE"
echo "  • Jobs config template: $JOBS_CONFIG_FILE"
echo "  • Chart values updated: $VALUES_FILE"
echo "  • Secret template created: $CHART_DIR/templates/docker-registry-secret.yaml"
echo "  • All deployments configured with imagePullSecrets"
echo "  • Created 3 initialization job templates with Helm hooks (correct execution order)"
echo ""
echo "🔧 Job execution order:"
echo "  1. init-db (pre-install hook, weight 1)"
echo "  2. pluginpopulator (post-install hook, weight 1)" 
echo "  3. metadatapopulator (post-install hook, weight 2)"
echo ""
echo "🔧 To modify configurations:"
echo "  1. Edit $GLOBAL_CONFIG_FILE for global settings"
echo "  2. Edit $JOBS_CONFIG_FILE for job settings"
echo "  3. Re-run this script to update the chart"
echo ""
echo "🚀 Installation examples:"
echo ""
echo "1. Install with current configuration:"
echo "   helm install epos $CHART_DIR"
echo ""
echo "2. Install without jobs (services only):"
echo "   helm install epos $CHART_DIR --set jobs.enabled=false"
echo ""
echo "3. Override specific job settings:"
echo "   helm install epos $CHART_DIR \\"
echo "     --set jobs.initDb.connectionString=\"your-db-connection\" \\"
echo "     --set jobs.metadataPopulator.securityCode=\"your-security-code\""
echo ""
echo "4. Override registry settings:"
echo "   helm install epos $CHART_DIR \\"
echo "     --set global.imagePullSecrets.registry.server=\"ghcr.io\" \\"
echo "     --set global.imagePullSecrets.registry.username=\"your-username\" \\"
echo "     --set global.imagePullSecrets.registry.password=\"your-token\""
echo ""
echo "5. Test configuration:"
echo "   helm template epos $CHART_DIR --debug"
echo ""
echo "🔍 Monitoring jobs:"
echo "   kubectl get jobs -l katenary.v3/component"
echo "   kubectl logs -l katenary.v3/component=init-db"
echo "   kubectl describe job \$RELEASE_NAME-init-db"
echo ""
echo "💡 Pro tips:"
echo "  • Jobs will run automatically during helm install/upgrade"
echo "  • Use 'kubectl get jobs' to monitor job status"
echo "  • Jobs are cleaned up automatically after success (configurable)"
echo "  • Edit template files for custom job configurations"
echo "  • Test with 'helm template' before deploying"