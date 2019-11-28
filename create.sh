#!/bin/bash -xe
VAR_CASE=$1
if [ "$VAR_CASE" != "setup" ];then
    if [ "$VAR_CASE" != "ignition" ];then
        INFRA_ID=$(jq -r .infraID metadata.json)
    fi
elif [ "$VAR_CASE" != "ignition" ];then
    if [ "$VAR_CASE" != "setup" ];then
        INFRA_ID=$(jq -r .infraID metadata.json)
    fi
fi

setup_start () {
    DATE=$(date +%Y%m%d%H%M%N)
    #cd ~/Documents/gluo/openshift4.2_try_out/aws
    mkdir install_$DATE
    cp install-conf/install-config.yaml install_$DATE
    git clone https://github.com/openshift/installer.git install_templates
    #cat << EOF > install_$DATE/auto.sh
    ##!/bin/bash
    #for i in ignition s3 name vpc infra_sec bootstrap control
    #do
    #    ../create.sh $i
    #done
#EOF
    #chmod +x install_$DATE/auto.sh

}

create_vpc () {
    aws cloudformation create-stack --stack-name $INFRA_ID-vpc --template-body file://../install_templates/upi/aws/cloudformation/01_vpc.yaml --parameters file://../json_parameters_aws/vpc.json
}

create_infra () {
aws cloudformation create-stack --stack-name $INFRA_ID-infra --template-body file://../install_templates/upi/aws/cloudformation/02_cluster_infra.yaml --parameters file://../json_parameters_aws/infra.json --capabilities CAPABILITY_NAMED_IAM
}

create_sec () {
aws cloudformation create-stack --stack-name $INFRA_ID-sec --template-body file://../install_templates/upi/aws/cloudformation/03_cluster_security.yaml --parameters file://../json_parameters_aws/sec.json --capabilities CAPABILITY_NAMED_IAM
}

create_bootstrap () {
aws cloudformation create-stack --stack-name $INFRA_ID-bootstrap --template-body file://../install_templates/upi/aws/cloudformation/04_cluster_bootstrap.yaml --parameters file://../json_parameters_aws/bootstrap.json --capabilities CAPABILITY_NAMED_IAM
}


create_control () {
aws cloudformation create-stack --stack-name $INFRA_ID-control --template-body file://../install_templates/upi/aws/cloudformation/05_cluster_master_nodes.yaml --parameters file://../json_parameters_aws/control_plane.json --capabilities CAPABILITY_NAMED_IAM
}


create_worker () {
aws cloudformation create-stack --stack-name $INFRA_ID-worker --template-body file://../install_templates/upi/aws/cloudformation/06_cluster_worker_node.yaml --parameters file://../json_parameters_aws/worker.json --capabilities CAPABILITY_NAMED_IAM
}

#oc get nodes
#oc get csr
#oc adm certificate approve <csr-name>
#oc get no
#oc get clusteroperators
#
#oc patch configs.imageregistry.operator.openshift.io cluster --type merge --patch '{"spec":{"storage":{"emptyDir":{}}}}'
#
#openshift-install wait-for install-complete
#
#
## for i in worker control bootstrap sec infra vpc; do aws cloudformation delete-stack --stack-name $INFRA_ID-$i;show-stack $INFRA_ID-$i| grep DELETE; done
#vpc_json_var () {
#    for KEY in PublicSubnets PrivateSubnets VpcId; do
#        cat ../json_parameters_aws/infra.json| jq '(.[] | select(.ParameterKey == "PublicSubnets") | .ParameterValue)'
#    done
#}
rename_cluster_name () {
    ../rename.sh $(jq -r '(.[] | select(.ParameterKey == "InfrastructureName") | .ParameterValue)' ../json_parameters_aws/infra.json) $(jq -r .infraID metadata.json)
    ../rename.sh $(jq -r '(.[] | select(.ParameterKey == "ClusterName") | .ParameterValue)' ../json_parameters_aws/infra.json) $(jq -r .clusterName metadata.json)
}

rename_vpc_var () {
        ../rename.sh $(jq -r '(.[] | select(.ParameterKey == "PublicSubnets") | .ParameterValue)' ../json_parameters_aws/infra.json) $(../show.sh vpc | awk '/PublicSubnetIds/ {print $(NF-1)}')
        ../rename.sh $(jq -r '(.[] | select(.ParameterKey == "PrivateSubnets") | .ParameterValue)' ../json_parameters_aws/infra.json) $(../show.sh vpc | awk '/PrivateSubnetIds/ {print $(NF-1)}')
        ../rename.sh $(jq -r '(.[] | select(.ParameterKey == "VpcId") | .ParameterValue)' ../json_parameters_aws/infra.json) $(../show.sh vpc | awk '/VpcId/ {print $(NF-1)}')
}

rename_prepare_bootstrap_var () {
    ../rename.sh $(jq -r '(.[] | select(.ParameterKey == "PublicSubnet") | .ParameterValue)' ../json_parameters_aws/bootstrap.json) $(../show.sh vpc | awk '/PublicSubnetIds/ {print $(NF-1)}' | awk -F , '{print $(1)}')
    ../rename.sh $(jq -r '(.[] | select(.ParameterKey == "MasterSecurityGroupId") | .ParameterValue)' ../json_parameters_aws/bootstrap.json) $(../show.sh sec | awk '/MasterSecurityGroupId/ {print $(NF-1)}')
    ../rename.sh $(jq -r '(.[] | select(.ParameterKey == "RegisterNlbIpTargetsLambdaArn") | .ParameterValue)' ../json_parameters_aws/bootstrap.json | awk -F - '{print $(NF)}') $(../show.sh infra | awk '/RegisterNlbIpTargetsLambda/ {print $(NF-1)}' | awk -F - '{print $(NF)}')
    ############################################## ExternalApiTargetGroupArn ####################################
    ../rename.sh $(jq -r '(.[] | select(.ParameterKey == "ExternalApiTargetGroupArn") | .ParameterValue)' ../json_parameters_aws/bootstrap.json | awk -F - '{print $(NF)}' | awk -F '/' '{print $(1)}') $(../show.sh infra | awk '/ExternalApiTargetGroupArn/ {print $(NF-1) }' | awk -F - '{print $(NF)}' | awk -F '/' '{print $(1)}')
    ../rename.sh $(jq -r '(.[] | select(.ParameterKey == "ExternalApiTargetGroupArn") | .ParameterValue)' ../json_parameters_aws/bootstrap.json | awk -F - '{print $(NF)}' | awk -F '/' '{print $(2)}') $(../show.sh infra | awk '/ExternalApiTargetGroupArn/ {print $(NF-1) }' | awk -F - '{print $(NF)}' | awk -F '/' '{print $(2)}')
    ############################################## InternalApiTargetGroupArn ####################################
    ../rename.sh $(jq -r '(.[] | select(.ParameterKey == "InternalApiTargetGroupArn") | .ParameterValue)' ../json_parameters_aws/bootstrap.json | awk -F - '{print $(NF)}' | awk -F '/' '{print $(1)}') $(../show.sh infra | awk '/InternalApiTargetGroupArn/ {print $(NF-1) }' | awk -F - '{print $(NF)}' | awk -F '/' '{print $(1)}')
    ../rename.sh $(jq -r '(.[] | select(.ParameterKey == "InternalApiTargetGroupArn") | .ParameterValue)' ../json_parameters_aws/bootstrap.json | awk -F - '{print $(NF)}' | awk -F '/' '{print $(2)}') $(../show.sh infra | awk '/InternalApiTargetGroupArn/ {print $(NF-1) }' | awk -F - '{print $(NF)}' | awk -F '/' '{print $(2)}')
    ############################################## InternalServiceTargetGroupArn ####################################
    ../rename.sh $(jq -r '(.[] | select(.ParameterKey == "InternalServiceTargetGroupArn") | .ParameterValue)' ../json_parameters_aws/bootstrap.json | awk -F - '{print $(NF)}' | awk -F '/' '{print $(1)}') $(../show.sh infra | awk '/InternalServiceTargetGroupArn/ {print $(NF-1) }' | awk -F - '{print $(NF)}' | awk -F '/' '{print $(1)}')
    ../rename.sh $(jq -r '(.[] | select(.ParameterKey == "InternalServiceTargetGroupArn") | .ParameterValue)' ../json_parameters_aws/bootstrap.json | awk -F - '{print $(NF)}' | awk -F '/' '{print $(2)}') $(../show.sh infra | awk '/InternalServiceTargetGroupArn/ {print $(NF-1) }' | awk -F - '{print $(NF)}' | awk -F '/' '{print $(2)}')
}

rename_prepare_control_var () {
    ############################################## PrivateHostedZoneId ####################################
    ../rename.sh $(jq -r '(.[] | select(.ParameterKey == "PrivateHostedZoneId") | .ParameterValue)' ../json_parameters_aws/control_plane.json) $(../show.sh infra | awk '/PrivateHostedZoneId/ {print $(NF-1)}')
    ############################################## Master0Subnet ####################################
    for m in {0..2}; do
        ../rename.sh $(jq -r '(.[] | select(.ParameterKey == "Master'$m'Subnet") | .ParameterValue)' ../json_parameters_aws/control_plane.json) $(../show.sh vpc | awk '/PrivateSubnetIds/ {print $(NF-1)}' | awk -F , '{print $('$m'+1)}')
    done
    #############################################CertificateAuthorities Master #################################
    ../rename.sh \"$(jq -r '(.[] | select(.ParameterKey == "CertificateAuthorities") | .ParameterValue)' ../json_parameters_aws/control_plane.json | awk -F , '{print $(NF)}')\" \"$(jq -r .ignition.security.tls.certificateAuthorities master.ign | awk -F : '/source/ {print $(NF)}' | awk -F , '{print $(NF-1)}')
    ############################################# MasterInstanceProfileName #################################
    ../rename.sh $(jq -r '(.[] | select(.ParameterKey == "MasterInstanceProfileName") | .ParameterValue)' ../json_parameters_aws/control_plane.json) $(../show.sh sec | awk '/MasterInstanceProfile/ {print $(NF-1)}')
}
rename_prepare_worker_var () {
    ############################################## Subnet ####################################
        ../rename.sh $(jq -r '(.[] | select(.ParameterKey == "Subnet") | .ParameterValue)' ../json_parameters_aws/worker.json) $(../show.sh vpc | awk '/PrivateSubnetIds/ {print $(NF-1)}' | awk -F , '{print $(1)}')
    #############################################CertificateAuthorities Master #################################
    ../rename.sh \"$(jq -r '(.[] | select(.ParameterKey == "CertificateAuthorities") | .ParameterValue)' ../json_parameters_aws/worker.json | awk -F , '{print $(NF)}')\" \"$(jq -r .ignition.security.tls.certificateAuthorities worker.ign | awk -F : '/source/ {print $(NF)}' | awk -F , '{print $(NF-1)}')
    ############################################# sec #################################
    ../rename.sh $(jq -r '(.[] | select(.ParameterKey == "WorkerInstanceProfileName") | .ParameterValue)' ../json_parameters_aws/worker.json) $(../show.sh sec | awk '/WorkerInstanceProfile/ {print $(NF-1)}')
    ../rename.sh $(jq -r '(.[] | select(.ParameterKey == "WorkerSecurityGroupId") | .ParameterValue)' ../json_parameters_aws/worker.json) $(../show.sh sec | awk '/WorkerSecurityGroupId/ {print $(NF-1)}')
}

create_ignition () {
    pwd
    ls -halt
    sleep 3
    sed -e '/name: worker/!b;n;n;c\ \ replicas: 0'  install-config.yaml
    sed -i '/name: worker/!b;n;n;c\ \ replicas: 0'  install-config.yaml
    openshift-install create manifests
    tree
    sleep 3
    rm -f openshift/99_openshift-cluster-api_master-machines-*.yaml
    rm -f openshift/99_openshift-cluster-api_worker-machineset-*.yaml
    openshift-install create ignition-configs
    tree
}

s3_setup () {
    aws s3 ls
    aws s3 ls s3://openshift-upi-infra
    aws s3 rm s3://openshift-upi-infra/bootstrap.ign
    aws s3 cp bootstrap.ign s3://openshift-upi-infra
    aws s3 ls s3://openshift-upi-infra
}


case $VAR_CASE in
    "s3")
        s3_setup
        ;;
    "ignition")
        create_ignition
        ;;
    "setup")
        setup_start
        ;;
    "name")
        rename_cluster_name
        ;;
    "vpc")
        create_vpc
        ../wait.sh $1 && sleep 3
        rename_vpc_var
        ;;
    "vpc")
        rename_vpc_var
        ;;
    "infra_sec")
        create_infra
        ../wait.sh infra
        create_sec && sleep 3
        ../wait.sh sec
        ;;
    "infra")
        create_infra
        ../wait.sh $1
        ;;
    "sec")
        create_sec
        ../wait.sh $1
        ;;
    "bootstrap")
        rename_prepare_bootstrap_var
        create_bootstrap
        ../wait.sh $1
        ;;
    "control")
        rename_prepare_control_var
        create_control
        ../wait.sh $1
        sleep 30
        openshift-install wait-for bootstrap-complete
        ;;
    "worker")
        rename_prepare_worker_var
        create_worker
        ;;
    *|"-h"|"--help")
        echo "what do you want to create?\n./create.sh {s3|ignition|name|vpc|infra|sec|bootstrap|control|worker"}
        ;;
esac
