#!/bin/bash
show-stack () {
aws cloudformation describe-stacks --output table --stack-name $1
}
INFRA_ID=$(jq -r .infraID metadata.json)
STAGE=$1
NU=1

if [ -z $STAGE  ]
then
    echo "set the stage variable"
    exit
fi

while [ $NU = 1 ];do
    show-stack $INFRA_ID-$STAGE | grep CREATE_IN_PROGRESS && echo in_progress;
        if [ $? != 0  ];then
            show-stack $INFRA_ID-$STAGE && NU=0;
        fi
    done
