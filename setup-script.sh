#!/bin/bash

# Set variables
AWS_ACCESS_KEY=
AWS_SECRET_ACCESS_KEY=
BASE_DOMAIN=
REGION="eu-west-2"
IMAGE_SET="img4.16.11-multi-appsub"
SSH_PRIVATE_KEY=
SSH_PUBLIC_KEY=
PULL_SECRET=


printf "\n\n=======================================================\n\n"
printf "\n\n==========================OOO==========================\n\n"
printf "\n\n=======================================================\n\n"

# Label the local cluster
printf "\nEMPIEZA: Añade etiqueta al cluster local\n"
oc label managedcluster/local-cluster rhdp_usage=development
printf "\nFIN: Añade etiqueta al cluster local\n"

printf "\n\n=======================================================\n\n"
printf "\n\n==========================OOO==========================\n\n"
printf "\n\n=======================================================\n\n"

# Create AWS credentials secret
printf "\nEMPIEZA: Crear objeto Credentials para AWS\n"
cat <<EOF | oc apply -f -
kind: Secret
type: Opaque
apiVersion: v1
metadata:
  name: aws
  namespace: open-cluster-management
  labels:
    cluster.open-cluster-management.io/credentials: ''
    cluster.open-cluster-management.io/type: aws
data:
  baseDomain: $(echo -n "$BASE_DOMAIN" | base64)
  aws_access_key_id: $(echo -n "$AWS_ACCESS_KEY" | base64)
  aws_secret_access_key: $(echo -n "$AWS_SECRET_ACCESS_KEY" | base64)
  ssh-privatekey: $(echo -n "$SSH_PRIVATE_KEY" | base64 | tr -d '\n')
  ssh-publickey: $(echo -n "$SSH_PUBLIC_KEY" | base64 | tr -d '\n')
  pullSecret: $(echo -n "$PULL_SECRET" | base64 | tr -d '\n')
EOF
printf "\nFIN: Crear objeto Credentials para AWS\n"

printf "\n\n=======================================================\n\n"
printf "\n\n==========================OOO==========================\n\n"
printf "\n\n=======================================================\n\n"

printf "\n\n EMPIEZA: Crear cluster1\n\n"

# Prepare install-config.yaml template
cat <<EOF > install-config-template.yaml
apiVersion: v1
baseDomain: $BASE_DOMAIN
metadata:
  name: 'cluster1'
platform:
  aws:
    region: $REGION
    credentialsSecretRef:
      name: cluster1-aws-creds
    type: m5.xlarge
controlPlane:
  hyperthreading: Enabled
  name: master
  replicas: 1
  platform:
    aws:
      type: m5.xlarge
      rootVolume:
        size: 100
        type: io1
        iops: 2000
compute:
- name: worker
  replicas: 2
  platform:
    aws:
      type: m5.xlarge
      rootVolume:
        size: 100
        type: io1
        iops: 2000
networking:
  networkType: OVNKubernetes
  clusterNetwork:
  - cidr: 10.128.0.0/14
    hostPrefix: 23
  machineNetwork:
  - cidr: 10.0.0.0/16
  serviceNetwork:
  - 172.30.0.0/16
sshKey: $SSH_PUBLIC_KEY
EOF

# Encode install-config.yaml to base64
INSTALL_CONFIG_BASE64=$(base64 -w 0 install-config-template.yaml)

oc new-project cluster1
printf "\n\n Crear clusterdeployment\n\n"
cat << EOF | oc apply -f -
apiVersion: hive.openshift.io/v1
kind: ClusterDeployment
metadata:
  name: 'cluster1'
  namespace: 'cluster1'
  labels:
    cloud: 'AWS'
    region: $REGION
    vendor: OpenShift
    cluster.open-cluster-management.io/clusterset: 'default'
spec:
  baseDomain: $BASE_DOMAIN
  clusterName: 'cluster1'
  controlPlaneConfig:
    servingCertificates: {}
  installAttemptsLimit: 1
  installed: false
  platform:
    aws:
      credentialsSecretRef:
        name: cluster1-aws-creds
      region: $REGION
  provisioning:
    installConfigSecretRef:
      name: cluster1-install-config
    sshPrivateKeySecretRef:
      name: cluster1-ssh-private-key
    imageSetRef:
      #quay.io/openshift-release-dev/ocp-release:4.16.11-multi
      name: $IMAGE_SET
  pullSecretRef:
    name: cluster1-pull-secret
EOF
printf "\n\n Crear managedcluster\n\n"
cat <<EOF | oc apply -f -
---
apiVersion: cluster.open-cluster-management.io/v1
kind: ManagedCluster
metadata:
  labels:
    cloud: Amazon
    region: '$REGION'
    name: 'cluster1'
    vendor: OpenShift
    cluster.open-cluster-management.io/clusterset: 'default'
    environment: 'prod'
  name: 'cluster1'
spec:
  hubAcceptsClient: true
EOF
printf "\n\n Crear machinepool\n\n"
cat <<EOF | oc apply -f -
---
apiVersion: hive.openshift.io/v1
kind: MachinePool
metadata:
  name: cluster1-worker
  namespace: 'cluster1'
spec:
  clusterDeploymentRef:
    name: 'cluster1'
  name: worker
  platform:
    aws:
      rootVolume:
        iops: 2000
        size: 100
        type: io1
      type: m5.xlarge
  replicas: 2
EOF
printf "\n\n Crear secret pull secret\n\n"
cat <<EOF | oc apply -f -
---
apiVersion: v1
kind: Secret
metadata:
  name: cluster1-pull-secret
  namespace: 'cluster1'
stringData:
  .dockerconfigjson: |-
    $PULL_SECRET
EOF
printf "\n\n Crear secret install-config\n\n"
cat <<EOF | oc apply -f -
---
apiVersion: v1
kind: Secret
metadata:
  name: cluster1-install-config
  namespace: 'cluster1'
type: Opaque
data:
  # Base64 encoding of install-config yaml
  install-config.yaml: $INSTALL_CONFIG_BASE64
EOF
printf "\n\n Crear secret ssh private key\n\n"
cat <<EOF | oc apply -f -
---
apiVersion: v1
kind: Secret
metadata:
  name: cluster1-ssh-private-key
  namespace: 'cluster1'
  ssh-privatekey: |-
$(printf "%s" "$SSH_PRIVATE_KEY" | sed 's/^/    /')
type: Opaque
EOF
printf "\n\n Crear secret aws creds\n\n"
cat <<EOF | oc apply -f -
---
apiVersion: v1
kind: Secret
type: Opaque
metadata:
  name: cluster1-aws-creds
  namespace: 'cluster1'
stringData:
  aws_access_key_id: $AWS_ACCESS_KEY
  aws_secret_access_key: $AWS_SECRET_ACCESS_KEY
EOF

printf "\n\n Eliminar fichero temporal install-config-template.yaml\n\n"
rm install-config-template.yaml

printf "\n\n FIN: Crear cluster1\n\n"

printf "\n\n=======================================================\n\n"
printf "\n\n==========================OOO==========================\n\n"
printf "\n\n=======================================================\n\n"

printf "\n\n EMPIEZA: Crear cluster2\n\n"

# Prepare install-config.yaml template
cat <<EOF > install-config-template.yaml
apiVersion: v1
baseDomain: $BASE_DOMAIN
metadata:
  name: 'cluster2'
platform:
  aws:
    region: eu-west-3
    credentialsSecretRef:
      name: cluster2-aws-creds
    type: m5.xlarge
controlPlane:
  hyperthreading: Enabled
  name: master
  replicas: 1
  platform:
    aws:
      type: m5.xlarge
      rootVolume:
        size: 100
        type: io1
        iops: 2000
compute:
- name: worker
  replicas: 2
  platform:
    aws:
      type: m5.xlarge
      rootVolume:
        size: 100
        type: io1
        iops: 2000
networking:
  networkType: OVNKubernetes
  clusterNetwork:
  - cidr: 10.128.0.0/14
    hostPrefix: 23
  machineNetwork:
  - cidr: 10.0.0.0/16
  serviceNetwork:
  - 172.30.0.0/16
sshKey: $SSH_PUBLIC_KEY
EOF

# Encode install-config.yaml to base64
INSTALL_CONFIG_BASE64=$(base64 -w 0 install-config-template.yaml)

oc new-project cluster2
printf "\n\n Crear clusterdeployment\n\n"
cat << EOF | oc apply -f -
apiVersion: hive.openshift.io/v1
kind: ClusterDeployment
metadata:
  name: 'cluster2'
  namespace: 'cluster2'
  labels:
    cloud: 'AWS'
    region: eu-west-3
    vendor: OpenShift
    cluster.open-cluster-management.io/clusterset: 'default'
spec:
  baseDomain: $BASE_DOMAIN
  clusterName: 'cluster2'
  controlPlaneConfig:
    servingCertificates: {}
  installAttemptsLimit: 1
  installed: false
  platform:
    aws:
      credentialsSecretRef:
        name: cluster2-aws-creds
      region: eu-west-3
  provisioning:
    installConfigSecretRef:
      name: cluster2-install-config
    sshPrivateKeySecretRef:
      name: cluster2-ssh-private-key
    imageSetRef:
      #quay.io/openshift-release-dev/ocp-release:4.16.11-multi
      name: $IMAGE_SET
  pullSecretRef:
    name: cluster2-pull-secret
EOF
printf "\n\n Crear managedcluster\n\n"
cat <<EOF | oc apply -f -
---
apiVersion: cluster.open-cluster-management.io/v1
kind: ManagedCluster
metadata:
  labels:
    cloud: Amazon
    region: 'eu-west-3'
    name: 'cluster2'
    vendor: OpenShift
    cluster.open-cluster-management.io/clusterset: 'default'
    environment: 'no-prod'
  name: 'cluster2'
spec:
  hubAcceptsClient: true
EOF
printf "\n\n Crear machinepool\n\n"
cat <<EOF | oc apply -f -
---
apiVersion: hive.openshift.io/v1
kind: MachinePool
metadata:
  name: cluster2-worker
  namespace: 'cluster2'
spec:
  clusterDeploymentRef:
    name: 'cluster2'
  name: worker
  platform:
    aws:
      rootVolume:
        iops: 2000
        size: 100
        type: io1
      type: m5.xlarge
  replicas: 2
EOF
printf "\n\n Crear secret pull secret\n\n"
cat <<EOF | oc apply -f -
---
apiVersion: v1
kind: Secret
metadata:
  name: cluster2-pull-secret
  namespace: 'cluster2'
stringData:
  .dockerconfigjson: |-
    $PULL_SECRET
EOF
printf "\n\n Crear secret install-config\n\n"
cat <<EOF | oc apply -f -
---
apiVersion: v1
kind: Secret
metadata:
  name: cluster2-install-config
  namespace: 'cluster2'
type: Opaque
data:
  # Base64 encoding of install-config yaml
  install-config.yaml: $INSTALL_CONFIG_BASE64
EOF
printf "\n\n Crear secret ssh private key\n\n"
cat <<EOF | oc apply -f -
---
apiVersion: v1
kind: Secret
metadata:
  name: cluster2-ssh-private-key
  namespace: 'cluster2'
  ssh-privatekey: |-
$(printf "%s" "$SSH_PRIVATE_KEY" | sed 's/^/    /')
type: Opaque
EOF
printf "\n\n Crear secret aws creds\n\n"
cat <<EOF | oc apply -f -
---
apiVersion: v1
kind: Secret
type: Opaque
metadata:
  name: cluster2-aws-creds
  namespace: 'cluster2'
stringData:
  aws_access_key_id: $AWS_ACCESS_KEY
  aws_secret_access_key: $AWS_SECRET_ACCESS_KEY
EOF

printf "\n\n Eliminar fichero temporal install-config-template.yaml\n\n"
rm install-config-template.yaml

printf "\n\n FIN: Crear cluster2\n\n"

printf "\n\n=======================================================\n\n"
printf "\n\n==========================OOO==========================\n\n"
printf "\n\n=======================================================\n\n"

printf "\n\n EMPIEZA: Instalar operadores OpenShift Gitops y AAP\n\n"

cat << EOF | oc apply -f -
---
apiVersion: v1
kind: Namespace
metadata:
  labels:
    openshift.io/cluster-monitoring: "true"
  name: ansible-automation-platform
---
apiVersion: v1
kind: Namespace
metadata:
  labels:
    openshift.io/cluster-monitoring: "true"
  name: openshift-gitops-operator
---
apiVersion: operators.coreos.com/v1
kind: OperatorGroup
metadata:
  name: openshift-gitops-operator
  namespace: openshift-gitops-operator
---
apiVersion: operators.coreos.com/v1alpha1
kind: Subscription
metadata:
  name: openshift-gitops-operator
  namespace: openshift-gitops-operator
spec:
  channel: latest
  installPlanApproval: Automatic
  name: openshift-gitops-operator
  source: redhat-operators
  sourceNamespace: openshift-marketplace
---
apiVersion: operators.coreos.com/v1
kind: OperatorGroup
metadata:
  name: ansible-automation-platform-operator
  namespace: ansible-automation-platform
spec:
  targetNamespaces:
    - ansible-automation-platform
---
apiVersion: operators.coreos.com/v1alpha1
kind: Subscription
metadata:
  name: ansible-automation-platform
  namespace: ansible-automation-platform
spec:
  channel: 'stable-2.4'
  installPlanApproval: Automatic
  name: ansible-automation-platform-operator
  source: redhat-operators
  sourceNamespace: openshift-marketplace
EOF

printf "\n\n FIN: Instalar operadores\n\n"

printf "\n\n=======================================================\n\n"
printf "\n\n==========================OOO==========================\n\n"
printf "\n\n=======================================================\n\n"


printf "\n\n EMPIEZA: Configura el Grafana (creando un bucket S3 en AWS)\n\n"
MY_BUCKET_NAME="grafana-demo-vrsr-${BASE_DOMAIN%%.*}"
aws configure set aws_access_key_id $AWS_ACCESS_KEY
aws configure set aws_secret_access_key $AWS_SECRET_ACCESS_KEY
aws configure set region $REGION
aws s3 mb s3://$MY_BUCKET_NAME
oc create namespace open-cluster-management-observability
oc project open-cluster-management-observability
DOCKER_CONFIG_JSON=`oc extract secret/pull-secret -n openshift-config --to=-`
oc create secret generic multiclusterhub-operator-pull-secret -n open-cluster-management-observability --from-literal=.dockerconfigjson="$DOCKER_CONFIG_JSON" --type=kubernetes.io/dockerconfigjson
cat << EOF | oc apply -f -
apiVersion: v1
kind: Secret
metadata:
  name: thanos-object-storage
  namespace: open-cluster-management-observability
type: Opaque
stringData:
  thanos.yaml: |
    type: s3
    config:
      bucket: $MY_BUCKET_NAME
      endpoint: s3.amazonaws.com
      insecure: false
      access_key: $AWS_ACCESS_KEY
      secret_key: $AWS_SECRET_ACCESS_KEY
EOF
cat << EOF | oc apply -f -
kind: MultiClusterObservability
apiVersion: observability.open-cluster-management.io/v1beta2
metadata:
  name: observability
spec:
  observabilityAddonSpec: {}
  storageConfig:
    metricObjectStorage:
      key: thanos.yaml
      name: thanos-object-storage
EOF
 
printf "\n\n FIN: Configura el Grafana (creando un bucket S3 en AWS)\n\n"

printf "\n\n=======================================================\n\n"
printf "\n\n==========================OOO==========================\n\n"
printf "\n\n=======================================================\n\n"

printf "\n\n Esperamos 5 minutos para que se instalen correctamente los operadores\n\n"
sleep 300
printf "\n\n Fin de la espera \n\n"

printf "\n\n EMPIEZA: Desplegar Ansible Controller\n\n"

cat << EOF | oc apply -f -
apiVersion: automationcontroller.ansible.com/v1beta1
kind: AutomationController
metadata:
  name: my-automation-controller
  namespace: ansible-automation-platform
spec:
  replicas: 1
EOF

printf "\n\n FIN: Desplegar Ansible Controller\n\n"

printf "\n\n=======================================================\n\n"
printf "\n\n==========================OOO==========================\n\n"
printf "\n\n=======================================================\n\n"


printf "\n\n EMPIEZA: Configurar Argo\n\n"

oc new-project openshift-gitops
cat << EOF | oc apply -f -
---
apiVersion: apps.open-cluster-management.io/v1beta1
kind: GitOpsCluster
metadata:
  name: argodemo
  namespace: openshift-gitops
spec:
  argoServer:
    argoNamespace: openshift-gitops
  placementRef:
    name: argodemo-placement
    kind: Placement
    apiVersion: cluster.open-cluster-management.io/v1beta1
---
apiVersion: cluster.open-cluster-management.io/v1beta2
kind: ManagedClusterSetBinding
metadata:
  name: default
  namespace: openshift-gitops
spec:
  clusterSet: default
---
apiVersion: cluster.open-cluster-management.io/v1beta1
kind: Placement
metadata:
  name: argodemo-placement
  namespace: openshift-gitops
spec:
  clusterSets:
    - default
EOF

printf "\n\n FIN: Configurar Argo\n\n"
