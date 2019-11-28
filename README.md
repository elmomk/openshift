# Install: User Provided Infrastructure (UPI)
source: https://github.com/openshift/installer


The steps for performing a UPI-based install are outlined here. Several [CloudFormation][cloudformation] templates are
provided to assist in completing these steps or to help model your own.  You are also free to create the required
resources through other methods; the CloudFormation templates are just an example.

## Create Configuration

```
ssh-keygen -t rsa -b 4096 -N '' -f <path>/<file_name>
eval $(ssh-agent -s)
ssh-add ~/Documents/gluo/openshift4.2_try_out/openshift.pem
cp ~/Documents/gluo/openshift4.2_try_out/openshift.pem.pub ~/.ssh
ssh-add -L
cd ~/Documents/gluo/openshift4.2_try_out/aws
```

Create an install configuration as for [the usual approach](install.md#create-configuration):

```console
$ git clone https://github.com/openshift/installer.git install_templates
$ mkdir install-config
$ cd !$
$ openshift-install create install-config
? SSH Public Key /home/user_id/.ssh/id_rsa.pub
? Platform aws
? Region us-east-2
? Base Domain example.com
? Cluster Name openshift
? Pull Secret [? for help]
$ cd -
$ ./create.sh setup
```

The ./create.sh setup basically just copies the install-config to another folder called install_$(date %Y%m%d%H%M%N), like this you have a backup in case you would want to reuse it. This config file will get consumed later on in the process.

Remember to change the basedomain in the `./json_parameters_aws` files. I didn't write this in the script yet because I had no direct use case for it.

### Empty Compute Pools

This can be done through using.

```sh
../create.sh ignition
```
It will set the `replicas` to 0 for the `compute` pool (as directed below) and will create the `manifests`, delete `openshift/99_openshift-cluster-api_master-machines-*.yaml` and `openshift/99_openshift-cluster-api_worker-machineset-*.yaml`, after this it will create the `ignition-configs`

Skip this part:
```
We'll be providing the control-plane and compute machines ourselves, so edit the resulting `install-config.yaml` to set `replicas` to 0 for the `compute` pool:

python -c '
import yaml;
path = "install-config.yaml";
data = yaml.load(open(path));
data["compute"][0]["replicas"] = 0;
open(path, "w").write(yaml.dump(data, default_flow_style=False))'
```

## Edit Manifests

Already done if you used ./create.sh ignition

Skip this part:
```
Use [a staged install](../overview.md#multiple-invocations) to make some adjustments which are not exposed via the install configuration.


$ openshift-install create manifests
INFO Consuming "Install Config" from target directory


### Remove Machines and MachineSets

Remove the control-plane Machines and compute MachineSets, because we'll be providing those ourselves and don't want to involve [the machine-API operator][machine-api-operator]:


$ rm -f openshift/99_openshift-cluster-api_master-machines-*.yaml openshift/99_openshift-cluster-api_worker-machineset-*.yaml
```

You are free to leave the compute MachineSets in if you want to create compute machines via the machine API, but if you do you may need to update the various references (`subnet`, etc.) to match your environment.


### Make control-plane nodes unschedulable

In the redhat partner course the `masterSchedulable` is kept on `True`

Skip this part:
```
Currently [emptying the compute pools](#empty-compute-pools) makes control-plane nodes schedulable.
But due to a [Kubernetes limitation][kubernetes-service-load-balancers-exclude-masters], router pods running on control-plane nodes will not be reachable by the ingress load balancer.
Update the scheduler configuration to keep router pods and other workloads off the control-plane nodes:


python -c '
import yaml;
path = "manifests/cluster-scheduler-02-config.yml"
data = yaml.load(open(path));
data["spec"]["mastersSchedulable"] = False;
open(path, "w").write(yaml.dump(data, default_flow_style=False))'
```

### Adjust DNS Zones

In our case we are going to choose for operator-managed DNS, so you can skip to point `Extract Infrastructure Name from Ignition Metadata`.

[The ingress operator][ingress-operator] is able to manage DNS records on your behalf.
Depending on whether you want operator-managed DNS or user-managed DNS, you can choose to [identify the internal DNS zone](#identify-the-internal-dns-zone) or [remove DNS zones](#remove-dns-zones) from the DNS configuration.

#### Identify the internal DNS zone

If you want [the ingress operator][ingress-operator] to manage DNS records on your behalf, adjust the `privateZone` section in the DNS configuration to identify the zone it should use.
By default it will use a `kubernetes.io/cluster/{infrastructureName}: owned` tag, but that tag is only appropriate if `openshift-install destroy cluster` should remove the zone.
For user-provided zones, you can remove `tags` completely and use the zone ID instead:

```sh
python -c '
import yaml;
path = "manifests/cluster-dns-02-config.yml";
data = yaml.load(open(path));
del data["spec"]["privateZone"]["tags"];
data["spec"]["privateZone"]["id"] = "Z21IZ5YJJMZ2A4";
open(path, "w").write(yaml.dump(data, default_flow_style=False))'
```

#### Remove DNS zones

If you don't want [the ingress operator][ingress-operator] to manage DNS records on your behalf, remove the `privateZone` and `publicZone` sections from the DNS configuration:

```sh
python -c '
import yaml;
path = "manifests/cluster-dns-02-config.yml";
data = yaml.load(open(path));
del data["spec"]["publicZone"];
del data["spec"]["privateZone"];
open(path, "w").write(yaml.dump(data, default_flow_style=False))'
```

If you do so, you'll need to [add ingress DNS records manually](#add-the-ingress-dns-records) later on.

## Create Ignition Configs

Already done if you used ./create.sh ignition

Skip this part:
```

Now we can create the bootstrap Ignition configs:


$ openshift-install create ignition-configs


After running the command, several files will be available in the directory.


$ tree
.
├── auth
│   └── kubeconfig
├── bootstrap.ign
├── master.ign
├── metadata.json
└── worker.ign
```

### Extract Infrastructure Name from Ignition Metadata

```
$ ../create.sh name
# sanity check
$ egrep {your clustername} ../json_parameters_aws/*
$ jq -r .clusterName metadata.json
$ jq -r '(.[] | select(.ParameterKey == "ClusterName") | .ParameterValue)' ../json_parameters_aws/*
$ jq -r .infraID metadata.json
$ jq -r '(.[] | select(.ParameterKey == "InfrastructureName") | .ParameterValue)' ../json_parameters_aws/*
```
To rename all the json parameters files in ```../json_parameters_aws``` with the correct `infraID` and `clustername`

Many of the operators and functions within OpenShift rely on tagging AWS resources. By default, Ignition
generates a unique cluster identifier comprised of the cluster name specified during the invocation of the installer
and a short string known internally as the infrastructure name. These values are seeded in the initial manifests within
the Ignition configuration. To use the output of the default, generated
`ignition-configs` extracting the internal infrastructure name is necessary.

An example of a way to get this is below:

```
$ jq -r .infraID metadata.json
openshift-vw9j6
```

## Create/Identify the VPC to be Used
Change `../json_parameters_aws/vpc.json` in case you want to change `VpcCidr`, `AvailabilityZoneCount` or `SubnetBits`.
```
$ ../create.sh vpc
$ alias show-stack='aws cloudformation describe-stacks --output table --stack-name'
$ INFRA_ID=$(jq -r .infraID metadata.json)
$ show-stack $INFRA_ID-vpc
```
This script will also rename the output variables for `vpc` and start to build a vpc through cloudformation, so double check the `vpc stack` on aws CloudFormation to make sure eveything went as planned.


You may create a VPC with various desirable characteristics for your situation (VPN, route tables, etc.). The
VPC configuration and a CloudFormation template is provided [here](../../../upi/aws/cloudformation/01_vpc.yaml).

A created VPC via the template or manually should approximate a setup similar to this:

<div style="text-align:center">
  <img src="images/install_upi_vpc.svg" width="100%" />
</div>

## Create DNS entries and Load Balancers for Control Plane Components

The DNS and load balancer configuration within a CloudFormation template is provided
[here](../../../upi/aws/cloudformation/02_cluster_infra.yaml). It uses a public hosted zone and creates a private hosted
zone similar to the IPI installation method.
It also creates load balancers, listeners, as well as hosted zone and subnet tags the same way as the IPI
installation method.
This template can be run multiple times within a single VPC and in combination with the VPC
template provided above.

### Optional: Manually Create Load Balancer Configuration

It is needed to create a TCP load balancer for ports 6443 (the Kubernetes API and its extensions) and 22623 (Ignition
configurations for new machines).  The targets will be the master nodes.  Port 6443 must be accessible to both clients
external to the cluster and nodes within the cluster. Port 22623 must be accessible to nodes within the cluster.

### Optional: Manually Create Route53 Hosted Zones & Records

For the cluster name identified earlier in [Create Ignition Configs](#create-ignition-configs), you must create a DNS entry which resolves to your created load balancer.
The entry `api.$clustername.$domain` should point to the external load balancer and `api-int.$clustername.$domain` should point to the internal load balancer.

## Create Security Groups and IAM Roles


```
$ ../create.sh infra_sec
## if for some reason the simple sed script failed for rename_vpc,Then
$ rm -rf ../json_parameters_aws
$ cp -r ../json_parameters_aws_base !$
$ ../create.sh rename_vpc
$ ../create.sh infra_sec
```

The security group and IAM configuration within a CloudFormation template is provided
[here](../../../upi/aws/cloudformation/03_cluster_security.yaml). Run this template to get the minimal and permanent
set of security groups and IAM roles needed for an operational cluster. It can also be inspected for the current
set of required rules to facilitate manual creation.

## Launch Temporary Bootstrap Resource
Change the parameters in `create.sh` for `s3_setup`. I mainly used this to replace bootstrap.ign on the s3 bucket it was on.
```
$ ../create.sh s3
```
The bootstrap launch and other necessary, temporary security group plus IAM configuration and a CloudFormation
template is provided [here](../../../upi/aws/cloudformation/04_cluster_bootstrap.yaml). Upload your generated `bootstrap.ign`
file to an S3 bucket in your account and run this template to get a bootstrap node along with a predictable clean up of
the resources when complete. It can also be inspected for the set of required attributes via manual creation.

```
$ ../create.sh bootstrap
```
Troubleshooting:
```
$ ssh core@bootstrap_ip
$ journalctl -b -f -u bootkube.service
```


## Launch Permanent Master Nodes

The master launch and other necessary DNS entries for etcd are provided within a CloudFormation
template [here](../../../upi/aws/cloudformation/05_cluster_master_nodes.yaml). Run this template to get three master
nodes. It can also be inspected for the set of required attributes needed for manual creation of the nodes, DNS entries
and load balancer configuration.

```
$ ../create.sh control
```
Troubleshooting (work in process):
First check the ec2 logs ons aws:
```
38.253852] ignition[661]: GET error: Get https://api-int.openshift.gluo.cloud:22623/config/master: x509: certificate signed by unknown authority (possibly because of "crypto/rsa: verification error" while trying to verify candidate authority certificate "root-ca")
```
```
$ cat /etc/pki/ca-trust/source/anchors/ca.crt # on boostrap instance
```
This ca.crt is empty when there is an x509 error.
https://developers.redhat.com/blog/2017/01/24/end-to-end-encryption-with-openshift-part-1-two-way-ssl/
```
$ ssh -A core@bootstrap_ip
$ ssh master_ip ###
```


## Monitor for `bootstrap-complete` and Initialization

Skip this part `$ ../create.sh control` does this for you:
```
$ bin/openshift-install wait-for bootstrap-complete
INFO Waiting up to 30m0s for the Kubernetes API at https://api.test.example.com:6443...
INFO API v1.12.4+c53f462 up
INFO Waiting up to 30m0s for the bootstrap-complete event...
```

## Destroy Bootstrap Resources

At this point, you should delete the bootstrap resources. If using the CloudFormation template, you would [delete the
stack][delete-stack] created for the bootstrap to clean up all the temporary resources.
```
$ ../delete bootstrap s
```

## Launch Additional Compute Nodes

You may create compute nodes by launching individual EC2 instances discretely or by automated processes outside the cluster (e.g. Auto Scaling Groups).
You can also take advantage of the built in cluster scaling mechanisms and the machine API in OpenShift, as mentioned [above](#create-ignition-configs).
In this example, we'll manually launch instances via the CloudFormatio template [here](../../../upi/aws/cloudformation/06_cluster_worker_node.yaml).
You can launch a CloudFormation stack to manage each individual compute node (you should launch at least two for a high-availability ingress router).
A similar launch configuration could be used by outside automation or AWS auto scaling groups.
```
$ ../create worker
```

#### Approving the CSR requests for nodes

The CSR requests for client and server certificates for nodes joining the cluster will need to be approved by the administrator.
You can view them with:

```console
$ oc get csr
NAME        AGE     REQUESTOR                                                                   CONDITION
csr-8b2br   15m     system:serviceaccount:openshift-machine-config-operator:node-bootstrapper   Approved,Issued
csr-8vnps   15m     system:serviceaccount:openshift-machine-config-operator:node-bootstrapper   Approved,Issued
csr-b96j4   25s     system:node:ip-10-0-52-215.us-east-2.compute.internal                       Approved,Issued
csr-bfd72   5m26s   system:node:ip-10-0-50-126.us-east-2.compute.internal                       Pending
csr-c57lv   5m26s   system:node:ip-10-0-95-157.us-east-2.compute.internal                       Pending
...
```

Administrators should carefully examine each CSR request and approve only the ones that belong to the nodes created by them.
CSRs can be approved by name, for example:

```sh
oc adm certificate approve csr-bfd72
oc get clusteroperators
oc get no
```
Troubleshooting:
It is possible that openshift will get stuck creating the authentication clusteroperator. (work in process)
https://docs.openshift.com/container-platform/4.1/authentication/understanding-authentication.html

## Add the Ingress DNS Records

If you removed the DNS Zone configuration [earlier](#remove-dns-zones), you'll need to manually create some DNS records pointing at the ingress load balancer.
You can create either a wildcard `*.apps.{baseDomain}.` or specific records (more on the specific records below).
You can use A, CNAME, [alias][route53-alias], etc. records, as you see fit.
For example, you can create wildcard alias records by retrieving the ingress load balancer status:

```console
$ oc -n openshift-ingress get service router-default
NAME             TYPE           CLUSTER-IP      EXTERNAL-IP                                                              PORT(S)                      AGE
router-default   LoadBalancer   172.30.62.215   ab37f072ec51d11e98a7a02ae97362dd-240922428.us-east-2.elb.amazonaws.com   80:31499/TCP,443:30693/TCP   5m
```

Then find the hosted zone ID for the load balancer (or use [this table][route53-zones-for-load-balancers]):

```console
$ aws elb describe-load-balancers | jq -r '.LoadBalancerDescriptions[] | select(.DNSName == "ab37f072ec51d11e98a7a02ae97362dd-240922428.us-east-2.elb.amazonaws.com").CanonicalHostedZoneNameID'
Z3AADJGX6KTTL2
```

And finally, add the alias records to your private and public zones:

```console
$ aws route53 change-resource-record-sets --hosted-zone-id "${YOUR_PRIVATE_ZONE}" --change-batch '{
>   "Changes": [
>     {
>       "Action": "CREATE",
>       "ResourceRecordSet": {
>         "Name": "\\052.apps.your.cluster.domain.example.com",
>         "Type": "A",
>         "AliasTarget":{
>           "HostedZoneId": "Z3AADJGX6KTTL2",
>           "DNSName": "ab37f072ec51d11e98a7a02ae97362dd-240922428.us-east-2.elb.amazonaws.com.",
>           "EvaluateTargetHealth": false
>         }
>       }
>     }
>   ]
> }'
$ aws route53 change-resource-record-sets --hosted-zone-id "${YOUR_PUBLIC_ZONE}" --change-batch '{
>   "Changes": [
>     {
>       "Action": "CREATE",
>       "ResourceRecordSet": {
>         "Name": "\\052.apps.your.cluster.domain.example.com",
>         "Type": "A",
>         "AliasTarget":{
>           "HostedZoneId": "Z3AADJGX6KTTL2",
>           "DNSName": "ab37f072ec51d11e98a7a02ae97362dd-240922428.us-east-2.elb.amazonaws.com.",
>           "EvaluateTargetHealth": false
>         }
>       }
>     }
>   ]
> }'
```

If you prefer to add explicit domains instead of using a wildcard, you can create entries for each of the cluster's current routes:

```console
$ oc get --all-namespaces -o jsonpath='{range .items[*]}{range .status.ingress[*]}{.host}{"\n"}{end}{end}' routes
oauth-openshift.apps.your.cluster.domain.example.com
console-openshift-console.apps.your.cluster.domain.example.com
downloads-openshift-console.apps.your.cluster.domain.example.com
alertmanager-main-openshift-monitoring.apps.your.cluster.domain.example.com
grafana-openshift-monitoring.apps.your.cluster.domain.example.com
prometheus-k8s-openshift-monitoring.apps.your.cluster.domain.example.com
```

## Monitor for Cluster Completion

```console
$ bin/openshift-install wait-for install-complete
INFO Waiting up to 30m0s for the cluster to initialize...
```

Also, you can observe the running state of your cluster pods:

```console
$ oc get pods --all-namespaces
NAMESPACE                                               NAME                                                                READY     STATUS      RESTARTS   AGE
kube-system                                             etcd-member-ip-10-0-3-111.us-east-2.compute.internal                1/1       Running     0          35m
kube-system                                             etcd-member-ip-10-0-3-239.us-east-2.compute.internal                1/1       Running     0          37m
kube-system                                             etcd-member-ip-10-0-3-24.us-east-2.compute.internal                 1/1       Running     0          35m
openshift-apiserver-operator                            openshift-apiserver-operator-6d6674f4f4-h7t2t                       1/1       Running     1          37m
openshift-apiserver                                     apiserver-fm48r                                                     1/1       Running     0          30m
openshift-apiserver                                     apiserver-fxkvv                                                     1/1       Running     0          29m
openshift-apiserver                                     apiserver-q85nm                                                     1/1       Running     0          29m
...
openshift-service-ca-operator                           openshift-service-ca-operator-66ff6dc6cd-9r257                      1/1       Running     0          37m
openshift-service-ca                                    apiservice-cabundle-injector-695b6bcbc-cl5hm                        1/1       Running     0          35m
openshift-service-ca                                    configmap-cabundle-injector-8498544d7-25qn6                         1/1       Running     0          35m
openshift-service-ca                                    service-serving-cert-signer-6445fc9c6-wqdqn                         1/1       Running     0          35m
openshift-service-catalog-apiserver-operator            openshift-service-catalog-apiserver-operator-549f44668b-b5q2w       1/1       Running     0          32m
openshift-service-catalog-controller-manager-operator   openshift-service-catalog-controller-manager-operator-b78cr2lnm     1/1       Running     0          31m
```

[cloudformation]: https://docs.aws.amazon.com/AWSCloudFormation/latest/UserGuide/Welcome.html
[delete-stack]: https://docs.aws.amazon.com/AWSCloudFormation/latest/UserGuide/cfn-console-delete-stack.html
[ingress-operator]: https://github.com/openshift/cluster-ingress-operator
[kubernetes-service-load-balancers-exclude-masters]: https://github.com/kubernetes/kubernetes/issues/65618
[machine-api-operator]: https://github.com/openshift/machine-api-operator
[route53-alias]: https://docs.aws.amazon.com/Route53/latest/DeveloperGuide/resource-record-sets-choosing-alias-non-alias.html
[route53-zones-for-load-balancers]: https://docs.aws.amazon.com/general/latest/gr/rande.html#elb_region
