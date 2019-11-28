#!/bin/bash -xe
show-stack () {
aws cloudformation describe-stacks --output table --stack-name $1
}

INFRA_ID=`jq -r .infraID metadata.json`
STAGE=$1

show-stack $INFRA_ID-$STAGE
