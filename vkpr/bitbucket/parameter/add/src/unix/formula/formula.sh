#!/bin/bash

runFormula() {
  echoColor blue "Creating new secret ${PARAMETER_NAME}"
  
  ## seting '*' as default value for PARAMETER_SCOPE
  bitbucketCreateOrUpdateRepositoryVariable "$PROJECT_NAME" "$PARAMETER_NAME" "$PARAMETER_VALUE" "$PARAMETER_MASKED" "$BITBUCKET_USERNAME" "$BITBUCKET_TOKEN"
  # echo "TOKEN: $BITBUCKET_TOKEN"

}
