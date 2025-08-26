#!/bin/bash

K8S_NAMESPACE=epos-release
RELEASE_NAME=release

HELM_CHART_VERSION=0.0.7
COMPONENT_GUI_BACKOFFICE_VERSION=develop
COMPONENT_GUI_VERSION=1-0-44
COMPONENT_SIMPLEGATEWAY_VERSION=2-0-2
COMPONENT_EMAILSENDER_VERSION=1-0-0
ENVIRONMENT_TYPE=development
COMPONENT_BACKOFFICE_VERSION=3-0-1
COMPONENT_RESOURCES_VERSION=2-1-1
COMPONENT_INGESTOR_VERSION=2-0-1
COMPONENT_CONVERTER_VERSION=1-0-2
COMPONENT_CONVERTEROUTINE_VERSION=1-0-1
COMPONENT_MESSAGEBUS_VERSION=3.13.7-management
COMPONENT_EXTERNALACCESS_VERSION=2-0-0
COMPONENT_SHARING_VERSION=0-3-1
COMPONENT_METADATADB_VERSION=3-0-2
CLEANUP_DB=true
COMPONENT_DBCLEANUP_VERSION=3-0-2
INGESTION_PROCESS=true
COMPONENT_METADATACACHE_VERSION=0-44-0
BROKER_PASSWORD=rabbitmq
INGRESS_HOST_PUBLIC=localhost
BASECONTEXT=/release


helm upgrade --create-namespace --namespace ${K8S_NAMESPACE} --install $RELEASE_NAME ./epos-chart -f brgm-values-dev.yml \
      --set backofficeui.repository.tag=$COMPONENT_GUI_BACKOFFICE_VERSION \
      --set dataportal.repository.tag=$COMPONENT_GUI_VERSION \
      --set gateway.repository.tag=$COMPONENT_SIMPLEGATEWAY_VERSION \
      --set emailsenderservice.repository.tag=$COMPONENT_EMAILSENDER_VERSION \
      --set emailsenderservice.environment.ENVIRONMENT_TYPE=$ENVIRONMENT_TYPE \
      --set backofficeservice.repository.tag=$COMPONENT_BACKOFFICE_VERSION \
      --set resourcesservice.repository.tag=$COMPONENT_RESOURCES_VERSION \
      --set ingestorservice.repository.tag=$COMPONENT_INGESTOR_VERSION \
      --set converterservice.repository.tag=$COMPONENT_CONVERTER_VERSION \
      --set converteroutine.repository.tag=$COMPONENT_CONVERTEROUTINE_VERSION \
      --set messagebus.repository.tag=$COMPONENT_MESSAGEBUS_VERSION \
      --set externalaccessservice.repository.tag=$COMPONENT_EXTERNALACCESS_VERSION \
      --set sharing.repository.tag=$COMPONENT_SHARING_VERSION \
      --set metadatadatabase.repository.tag=$COMPONENT_METADATADB_VERSION \
      --set jobs.initDb.enabled=$CLEANUP_DB \
      --set jobs.initDb.tag=$COMPONENT_DBCLEANUP_VERSION \
      --set jobs.metadataPopulator.enabled=$INGESTION_PROCESS \
      --set jobs.metadataPopulator.tag=$COMPONENT_METADATACACHE_VERSION \
      --set jobs.pluginPopulator.enabled=$INGESTION_PROCESS \
      --set global.services.rabbitmq.password=$BROKER_PASSWORD \
      --set global.services.hosts.host=$INGRESS_HOST_PUBLIC \
      --set global.services.hosts.dataportal="$BASECONTEXT/" \
      --set global.services.hosts.backoffice="$BASECONTEXT/backoffice/" \
      --set global.services.hosts.gateway="$BASECONTEXT/api/v1/" \
      --set global.services.hosts.basecontext="$BASECONTEXT" \
      --timeout 20m \
      --wait \
