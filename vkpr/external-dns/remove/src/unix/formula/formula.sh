#!/bin/bash

runFormula() {
  echoColor "bold" "$(echoColor "green" "Removing External-DNS...")"

  EXTERNAL_DNS_NAMESPACE=$($VKPR_KUBECTL get po -A -l app.kubernetes.io/instance=external-dns,vkpr=true -o=yaml |\
                           $VKPR_YQ e ".items[].metadata.namespace" - |\
                           head -n1)

  $VKPR_HELM uninstall external-dns -n "$EXTERNAL_DNS_NAMESPACE" 2> /dev/null || echoColor "red" "VKPR external-dns not found"
}
