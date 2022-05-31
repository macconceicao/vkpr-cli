#!/bin/bash

runFormula() {
  info "Removing jaeger..."

  WHOAMI_NAMESPACE=$($VKPR_KUBECTL get po -A -l app.kubernetes.io/instance=jaeger,vkpr=true -o=yaml |\
                     $VKPR_YQ e ".items[].metadata.namespace" - |\
                     head -n1)

  $VKPR_HELM uninstall jaeger -n "$WHOAMI_NAMESPACE" 2> /dev/null || error "VKPR jaeger not found"
}