#!/bin/bash

runFormula() {
  local PG_USER="postgres"
  local PG_PASSWORD; PG_PASSWORD=$($VKPR_JQ -r '.credential.password' ~/.rit/credentials/default/postgres)
  local PG_DATABASE_NAME="keycloak"
  local VKPR_KEYCLOAK_VALUES; VKPR_KEYCLOAK_VALUES=$(dirname "$0")/utils/keycloak.yaml

  # Global values
  checkGlobalConfig "$DOMAIN" "localhost" "global.domain" "GLOBAL_DOMAIN"
  checkGlobalConfig "$SECURE" "false" "global.secure" "GLOBAL_SECURE"
  checkGlobalConfig "nginx" "nginx" "global.ingressClassName" "GLOBAL_INGRESS"
  checkGlobalConfig "$VKPR_K8S_NAMESPACE" "vkpr" "global.namespace" "GLOBAL_NAMESPACE"
  
  # App values
  checkGlobalConfig "$HA" "false" "keycloak.HA" "HA"
  checkGlobalConfig "$ADMIN_USER" "admin" "keycloak.adminUser" "KEYCLOAK_ADMIN_USER"
  checkGlobalConfig "$ADMIN_PASSWORD" "vkpr123" "keycloak.adminPassword" "KEYCLOAK_ADMIN_PASSWORD"
  checkGlobalConfig "$VKPR_ENV_GLOBAL_INGRESS" "$VKPR_ENV_GLOBAL_INGRESS" "keycloak.ingressClassName" "KEYCLOAK_INGRESS"
  checkGlobalConfig "false" "false" "keycloak.metrics" "METRICS"
  checkGlobalConfig "$VKPR_ENV_GLOBAL_NAMESPACE" "$VKPR_ENV_GLOBAL_NAMESPACE" "keycloak.namespace" "NAMESPACE"

  # External apps values
  checkGlobalConfig "$VKPR_ENV_GLOBAL_NAMESPACE" "$VKPR_ENV_GLOBAL_NAMESPACE" "postgresql.namespace" "POSTGRESQL_NAMESPACE"

  local VKPR_ENV_KEYCLOAK_DOMAIN="keycloak.${VKPR_ENV_GLOBAL_DOMAIN}"

  startInfos
  addRepoKeycloak
  installKeycloak
}

startInfos() {
  echo "=============================="
  echoColor "bold" "$(echoColor "green" "VKPR Keycloak Install Routine")"
  echoColor "bold" "$(echoColor "blue" "Keycloak Domain:") ${VKPR_ENV_KEYCLOAK_DOMAIN}"
  echoColor "bold" "$(echoColor "blue" "Keycloak HTTPS:") ${VKPR_ENV_GLOBAL_SECURE}"
  echoColor "bold" "$(echoColor "blue" "HA:") ${VKPR_ENV_HA}"
  echoColor "bold" "$(echoColor "blue" "Keycloak Admin Username:") ${VKPR_ENV_KEYCLOAK_ADMIN_USER}"
  echoColor "bold" "$(echoColor "blue" "Keycloak Admin Password:") ${VKPR_ENV_KEYCLOAK_ADMIN_PASSWORD}"
  echoColor "bold" "$(echoColor "blue" "Ingress Controller:") ${VKPR_ENV_KEYCLOAK_INGRESS}"
  echo "=============================="
}

addRepoKeycloak(){
  registerHelmRepository bitnami https://charts.bitnami.com/bitnami
}

installKeycloak(){
  local YQ_VALUES=".postgresql.enabled = false"
  [[ $DRY_RUN == false ]] && configureKeycloakDB
  settingKeycloak
  echoColor "bold" "$(echoColor "green" "Installing Keycloak...")"

  if [[ $DRY_RUN == true ]]; then
    echoColor "bold" "---"
    $VKPR_YQ eval "$YQ_VALUES" "$VKPR_KEYCLOAK_VALUES"
  else
    echoColor "bold" "$(echoColor "green" "Installing Keycloak...")"
    $VKPR_YQ eval -i "$YQ_VALUES" "$VKPR_KEYCLOAK_VALUES"
    mergeVkprValuesHelmArgs "keycloak" "$VKPR_KEYCLOAK_VALUES"
    $VKPR_HELM upgrade -i --version "$VKPR_KEYCLOAK_VERSION" \
      --create-namespace -n "$VKPR_ENV_NAMESPACE" \
      --wait --timeout 10m -f "$VKPR_KEYCLOAK_VALUES" keycloak bitnami/keycloak
  fi
}

settingKeycloak(){
  YQ_VALUES="$YQ_VALUES |
    .ingress.hostname = \"$VKPR_ENV_KEYCLOAK_DOMAIN\" |
    .ingress.ingressClassName = \"$VKPR_ENV_KEYCLOAK_INGRESS\" |
    .auth.adminUser = \"$VKPR_ENV_KEYCLOAK_ADMIN_USER\" |
    .auth.adminPassword = \"$VKPR_ENV_KEYCLOAK_ADMIN_PASSWORD\"
  "
  if [[ $VKPR_ENV_GLOBAL_SECURE = true ]]; then
    YQ_VALUES="$YQ_VALUES |
      .ingress.annotations.[\"kubernetes.io/tls-acme\"] = \"true\" |
      .ingress.tls = true
    "
  fi
  if [[ $VKPR_ENV_HA = true ]]; then
    YQ_VALUES="$YQ_VALUES |
      .replicaCount = 3 |
      .serviceDiscovery.enabled = \"true\" |
      .serviceDiscovery.protocol = \"dns.DNS_PING\" |
      .serviceDiscovery.properties[0] = \"dns_query=\"keycloak-headless.$VKPR_ENV_NAMESPACE.svc.cluster.local\"\" |
      .proxyAddressForwarding = true |
      .cache.ownersCount = 3 |
      .cache.authOwnersCount = 3
    "
  fi
  if [[ $VKPR_ENV_METRICS == "true" ]]; then
    YQ_VALUES="$YQ_VALUES |
      .metrics.enabled = true |
      .metrics.serviceMonitor.enabled = true |
      .metrics.serviceMonitor.namespace = \"$VKPR_ENV_NAMESPACE\" |
      .metrics.serviceMonitor.interval = \"30s\" |
      .metrics.serviceMonitor.scrapeTimeout = \"30s\" |
      .metrics.serviceMonitor.additionalLabels.release = \"prometheus-stack\" 
    "
  fi
}

configureKeycloakDB(){
  local PG_HA="false"
  validatePostgresqlPassword "$PASSWORD"
  [[ $VKPR_ENV_HA == true ]] && PG_HA="true"
  if [[ $(checkPodName "$VKPR_ENV_POSTGRESQL_NAMESPACE" "postgres-postgresql") != "true" ]]; then
    echoColor "green" "Initializing postgresql to Keycloak"
    [[ -f $CURRENT_PWD/vkpr.yaml ]] && cp "$CURRENT_PWD"/vkpr.yaml "$(dirname "$0")"
    rit vkpr postgres install --HA="$PG_HA" --default
  fi
  if [[ $(checkExistingDatabase "$PG_USER" "$PG_PASSWORD" "$PG_DATABASE_NAME" "$VKPR_ENV_POSTGRESQL_NAMESPACE") != "keycloak" ]]; then
    echoColor "green" "Creating Database Instance in postgresql..."
    createDatabase "$PG_USER" "$PG_PASSWORD" "$PG_DATABASE_NAME" "$VKPR_ENV_POSTGRESQL_NAMESPACE"
  fi

  local PG_HOST="postgres-postgresql.$VKPR_ENV_POSTGRESQL_NAMESPACE"
  $VKPR_KUBECTL get pod -n "$VKPR_ENV_POSTGRESQL_NAMESPACE" | grep -q pgpool && PG_HOST="postgres-postgresql-pgpool.$VKPR_ENV_POSTGRESQL_NAMESPACE"
  YQ_VALUES="$YQ_VALUES |
    .externalDatabase.host = \"$PG_HOST\" |
    .externalDatabase.port = \"5432\" |
    .externalDatabase.user = \"$PG_USER\" |
    .externalDatabase.password = \"$PG_PASSWORD\" |
    .externalDatabase.database = \"$PG_DATABASE_NAME\"
  "
}