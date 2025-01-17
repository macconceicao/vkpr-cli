#!/bin/bash


runFormula() {
  # Global values
  checkGlobalConfig "$VKPR_K8S_NAMESPACE" "vkpr" "global.namespace" "GLOBAL_NAMESPACE"
  
  # App values
  checkGlobalConfig "$LB_TYPE" "Classic" "ingress.loadBalancerType" "INGRESS_LB_TYPE"
  checkGlobalConfig "false" "false" "ingress.metrics" "INGRESS_METRICS"
  checkGlobalConfig "$VKPR_ENV_GLOBAL_NAMESPACE" "$VKPR_ENV_GLOBAL_NAMESPACE" "ingress.namespace" "INGRESS_NAMESPACE"

  local VKPR_INGRESS_VALUES; VKPR_INGRESS_VALUES="$(dirname "$0")"/utils/ingress.yaml
  
  startInfos
  configureRepository
  installIngress
}

startInfos() {
  echo "=============================="
  info "VKPR Ingress Install Routine"
  echo "=============================="
}

configureRepository() {
  registerHelmRepository ingress-nginx https://kubernetes.github.io/ingress-nginx
}

installIngress() {
  local YQ_VALUES=".rbac.create = true"
  settingIngress

  if [[ $DRY_RUN == true ]]; then
    echoColor "bold" "---"
    $VKPR_YQ eval "$YQ_VALUES" "$VKPR_INGRESS_VALUES"
  else
    info "Installing ngnix ingress..."
    $VKPR_YQ eval -i "$YQ_VALUES" "$VKPR_INGRESS_VALUES"
    mergeVkprValuesHelmArgs "ingress" "$VKPR_INGRESS_VALUES"
    $VKPR_HELM upgrade -i --version "$VKPR_INGRESS_NGINX_VERSION" \
      --namespace "$VKPR_ENV_INGRESS_NAMESPACE" --create-namespace \
      --wait -f "$VKPR_INGRESS_VALUES" ingress-nginx ingress-nginx/ingress-nginx
  fi
}

settingIngress() {
  if [[ "$VKPR_ENV_INGRESS_LB_TYPE" == "NLB" ]]; then
    YQ_VALUES="
      .controller.service.annotations.[\"service.beta.kubernetes.io/aws-load-balancer-backend-protocol\"] = \"tcp\" |
      .controller.service.annotations.[\"service.beta.kubernetes.io/aws-load-balancer-cross-zone-load-balancing-enabled\"] = \"true\" |
      .controller.service.annotations.[\"service.beta.kubernetes.io/aws-load-balancer-type\"] = \"nlb\"
    "
  fi

  if [[ "$VKPR_ENV_INGRESS_METRICS" == "true" ]]; then
    YQ_VALUES="$YQ_VALUES |
      .controller.metrics.enabled = true |
      .controller.metrics.service.annotations.[\"prometheus.io/scrape\"] = \"true\" |
      .controller.metrics.service.annotations.[\"prometheus.io/port\"] = \"10254\" |
      .controller.metrics.serviceMonitor.enabled = true |
      .controller.metrics.serviceMonitor.namespace = \"$VKPR_ENV_INGRESS_NAMESPACE\" |
      .controller.metrics.serviceMonitor.additionalLabels.release = \"prometheus-stack\"
     "
  fi
}