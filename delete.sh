#!/bin/bash -xe

delete-stack () {
    aws cloudformation delete-stack --stack-name $1
}
show-stack () {
    aws cloudformation describe-stacks --output table --stack-name $1
}

STAGE=$1
delete () {
    INFRA_ID=$(jq -r .infraID metadata.json)
    NU=1

    if [ -z $STAGE  ]
    then
        echo "set the stage variable"
        exit
    fi

    delete-stack $INFRA_ID-$STAGE

    while [ $NU = 1 ];do
        show-stack $INFRA_ID-$STAGE | grep IN_PROGRESS && echo in_progress|| NU=0;
        done
}

#delete_all () {
#    #for stage in worker control bootstrap sec infra vpc; do
#    for stage in bootstrap sec infra vpc; do
#        #aws cloudformation delete-stack --stack-name $INFRA_ID-$i;show-stack $INFRA_ID-$i| grep DELETE
#        delete $stage
#        return 0
#    done
#}

case $1 in
   # "del_all")
   #     delete_all
   #     ;;
    "worker"|"control"|"boostrap"|"sec"|"infra"|"vpc")
        delete
        ;;
    *)
        echo "../delete.sh {worker|control|sec|infra|vpc} \ne.g.: ../delete.sh vpc"
        ;;
esac
