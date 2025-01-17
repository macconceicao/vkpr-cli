#!/bin/bash

runFormula() {
  local PROJECT_ID BRANCH_NAME PIPELINE_ID DEPLOY_COMPLETE;

  validateGitlabUsername "$GITLAB_USERNAME"
  validateGitlabToken "$GITLAB_TOKEN"
  
  PROJECT_ID=$(curl -s https://gitlab.com/api/v4/users/"$GITLAB_USERNAME"/projects |\
    $VKPR_JQ '.[] | select(.name == "k8s-digitalocean").id'
  )
  PIPELINE_ID=$(curl -s https://gitlab.com/api/v4/projects/"$PROJECT_ID"/pipelines \
    -H "PRIVATE-TOKEN: $GITLAB_TOKEN" |\
    $VKPR_JQ '.[0].id'
  )
  BRANCH_NAME=$(curl -s https://gitlab.com/api/v4/projects/"$PROJECT_ID"/pipelines \
    -H "PRIVATE-TOKEN: $GITLAB_TOKEN" |\
    $VKPR_JQ -r '.[0].ref'
  )
  DEPLOY_COMPLETE=$(curl -s https://gitlab.com/api/v4/projects/"$PROJECT_ID"/pipelines/"$PIPELINE_ID"/jobs \
    -H "PRIVATE-TOKEN: $GITLAB_TOKEN" |\
    $VKPR_JQ -r '.[1].status'
  )

  waitJobComplete "$PROJECT_ID" "$PIPELINE_ID" "$DEPLOY_COMPLETE" "$GITLAB_TOKEN" "1"
  downloadKubeconfig "$PROJECT_ID" "$PIPELINE_ID" "$DEPLOY_COMPLETE" "$GITLAB_TOKEN" "digitalocean"

  echoColor "green" "Kubeconfig downloaded succefully, to use the Kubeconfig run the following command: "
  echoColor "bold" "export KUBECONFIG=\$HOME/.vkpr/kubeconfig/digitalocean/kubeconfig_${BRANCH_NAME}"
}