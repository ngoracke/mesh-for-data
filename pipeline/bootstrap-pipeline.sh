#!/bin/bash
set -ex
set +e

run_tkn=${run_tkn:-0}
skip_tests=${skip_tests:-false}
GH_TOKEN=${GH_TOKEN}
ARTIFACTORY_APIKEY=${ARTIFACTORY_APIKEY}
git_user=${git_user}
github=${github:-github.ibm.com}
image_source_repo_username=${image_source_repo_username}
image_repo="${image_repo:-image-registry.openshift-image-registry.svc:5000}"
dockerhub_hostname="${dockerhub_hostname:-wcp-ibm-streams-docker-local.artifactory.swg-devops.com/pipelines-tutorial}"
helper_text=""
realpath() {
    [[ $1 = /* ]] && echo "$1" || echo "$PWD/${1#./}"
}

repo_root=$(realpath $(dirname $(realpath $0)))/..

. ${repo_root}/pipeline/common_functions.sh

function cleanup {
    if [[ ! -z ${TMP} ]]; then
        rm -rf ${TMP}
        echo ${helper_text}
#        echo "Deleted temp working directory ${TMP}"
    fi
}

if [[ -z "$TMP" ]]; then
    TMP=$(mktemp -d) || exit 1
    trap cleanup EXIT
fi

extra_params=''
is_external="false"
is_internal="false"
helm_image=
build_image=
if [[ "${github}" == "github.com" ]]; then
    is_external="true"
    build_image="docker.io/yakinikku/suede_compile"
    helm_image="docker.io/lachlanevenson/k8s-helm:latest"
    extra_params="-p build_image ${build_image} -p helm_image ${helm_image}"
    cp ${repo_root}/pipeline/statefulset.yaml ${TMP}/
    sed -i.bak "s|wcp-ibm-streams-docker-local.artifactory.swg-devops.com/elvis_build/suede:latest|docker.io/yakinikku/suede|g" ${TMP}/statefulset.yaml
else
    is_internal="true"
    build_image="wcp-ibm-streams-docker-local.artifactory.swg-devops.com/elvis_build/suede_compile:latest"
    helm_image="wcp-ibm-streams-docker-local.artifactory.swg-devops.com/pipelines-tutorial/k8s-helm"
    extra_params="-p build_image ${build_image} -p helm_image ${helm_image}"
    cp ${repo_root}/pipeline/statefulset.yaml ${TMP}/
fi
is_openshift="false"
is_kubernetes="false"
client=kubectl
pipeline_sa=pipeline
set +e
kubectl get ns | grep openshift-apiserver
rc=$?
if [[ $rc -eq 0 ]]; then
    is_openshift=true
    client=oc
    pipeline_sa=pipeline
else
    is_kubernetes=true
    client=kubectl
    pipeline_sa=default
fi
if [[ ${is_kubernetes} == "true" ]]; then
    set -e
    kubectl apply -f ${repo_root}/pipeline/nfs.yaml
    helm repo add stable https://charts.helm.sh/stable
    ip=$(kubectl get svc -n default nfs-service -o jsonpath='{.spec.clusterIP}')
    helm upgrade --install nfs-provisioner stable/nfs-client-provisioner --values ${repo_root}/pipeline/nfs-values.yaml --set nfs.server=${ip} --namespace nfs-provisioner --create-namespace
fi
set +e
rc=1
if [[ ! -z $1 ]]; then
    if [[ ${is_openshift} == "true" ]]; then
        oc get project $1
        rc=$?
    else
        kubectl get ns $1
        rc=$?
    fi
else
    if [[ ${is_openshift} == "true" ]]; then
        oc get project m4d-system
        rc=$?
    else
        kubectl get ns m4d-system
        rc=$?
    fi
fi
if [[ ! -z $2 ]]; then
    ssh_key=$2
else
    ssh_key=${HOME}/.ssh/id_rsa
fi
set -e
if [[ $rc -ne 0 ]]; then
    if [[ ${is_openshift} == "true" ]]; then
        oc new-project ${1:-m4d-system}
    else
        kubectl create ns ${1:-m4d-system}
        kubectl config set-context --current --namespace=${1:-m4d-system}
    fi
else
    if [[ ${is_openshift} == "true" ]]; then
        oc project ${1:-m4d-system}
    else
        kubectl config set-context --current --namespace=${1:-m4d-system}
    fi
fi
unique_prefix=$(kubectl config view --minify --output 'jsonpath={..namespace}'; echo)

set +e
# Be smarter about this - just a quick hack for typical default installs
oc patch storageclass managed-nfs-storage -p '{"metadata": {"annotations": {"storageclass.kubernetes.io/is-default-class": "true"}}}'
oc patch storageclass standard -p '{"metadata": {"annotations": {"storageclass.kubernetes.io/is-default-class": "false"}}}'
set -e

if [[ ${is_openshift} == "true" ]]; then
    oc apply -f ${repo_root}/pipeline/subscription.yaml
    oc apply -f ${repo_root}/pipeline/serverless-subscription.yaml

    cat > ${TMP}/streams_csv_check_script.sh <<EOH
#!/bin/bash
set -x
oc get -n openshift-pipelines csv | grep redhat-openshift-pipelines-operator 
oc get -n openshift-pipelines csv | grep redhat-openshift-pipelines-operator | grep Succeeded
EOH
chmod u+x ${TMP}/streams_csv_check_script.sh
    try_command "${TMP}/streams_csv_check_script.sh"  40 true 5

    cat > ${TMP}/streams_csv_check_script.sh <<EOH
#!/bin/bash
set -x
oc get -n openshift-operators csv | grep serverless-operator
oc get -n openshift-operators csv | grep serverless-operator | grep -e Succeeded -e Replacing
EOH
chmod u+x ${TMP}/streams_csv_check_script.sh
    try_command "${TMP}/streams_csv_check_script.sh"  40 false 5
    oc apply -f ${repo_root}/pipeline/knative-eventing.yaml
else
    kubectl apply --filename https://storage.googleapis.com/tekton-releases/pipeline/latest/release.yaml
    kubectl apply -f https://github.com/knative/operator/releases/download/v0.15.4/operator.yaml
    kubectl apply -f https://github.com/knative/eventing/releases/download/v0.21.0/eventing-crds.yaml
    kubectl apply -f https://github.com/knative/eventing/releases/download/v0.21.0/eventing-core.yaml
    kubectl wait pod -n tekton-pipelines --all --for=condition=Ready --timeout=3m
    set +e
    kubectl create ns knative-eventing
    set -e
    cat > ${TMP}/knative-eventing.yaml <<EOH
apiVersion: operator.knative.dev/v1alpha1
kind: KnativeEventing
metadata:
  name: knative-eventing
  namespace: knative-eventing
EOH
    ls -alrt ${TMP}/
    kubectl apply -f ${TMP}/knative-eventing.yaml
fi

if [[ ${is_openshift} == "true" ]]; then
    oc adm policy add-cluster-role-to-user cluster-admin system:serviceaccount:${unique_prefix}:pipeline
    oc adm policy add-cluster-role-to-user cluster-admin system:serviceaccount:${unique_prefix}:root-sa
    oc adm policy add-role-to-group system:image-puller system:serviceaccounts:${unique_prefix} --namespace ${unique_prefix}
    oc adm policy add-role-to-group system:image-puller system:serviceaccounts:m4d-blueprints --namespace ${unique_prefix}
    oc adm policy add-role-to-user system:image-puller system:serviceaccount:${unique_prefix}:wkc-connector --namespace ${unique_prefix}
    # Temporary hack pending a better solution
    oc adm policy add-scc-to-user anyuid system:serviceaccount:${unique_prefix}:opa-connector
    oc adm policy add-scc-to-user anyuid system:serviceaccount:${unique_prefix}:manager
else
    set +e
    kubectl create clusterrolebinding ${unique_prefix}-default-cluster-admin --clusterrole=cluster-admin --serviceaccount=${unique_prefix}:default
    set -e
    #exit 1
fi

set +e
#resource_version=$(oc get -f ${repo_root}/pipeline/make.yaml -o jsonpath='{.metadata.resourceVersion}')
set -e
set +x
helper_text="If this step fails, tekton related pods may be restarting or initializing:

1. Please rerun in a minute or so
"
set -x
oc apply -f ${repo_root}/pipeline/make.yaml
oc apply -f ${repo_root}/pipeline/git-clone.yaml
oc apply -f ${repo_root}/pipeline/buildah.yaml
oc apply -f ${repo_root}/pipeline/skopeo-copy.yaml
oc apply -f ${repo_root}/pipeline/openshift-client.yaml
oc apply -f ${repo_root}/pipeline/helm-upgrade-from-source.yaml 
oc apply -f ${repo_root}/pipeline/helm-upgrade-from-repo.yaml 
helper_text=""

#oc patch clustertask helm-upgrade-from-repo -p '
#[{
#  "op": "replace",
#  "path": "/spec/steps/0/image",
#  "value": "wcp-ibm-streams-docker-local.artifactory.swg-devops.com/pipelines-tutorial/k8s-helm:latest"
#}]' --type=json
#
#oc patch clustertask helm-upgrade-from-source -p '
#[{
#  "op": "replace",
#  "path": "/spec/steps/0/image",
#  "value": "wcp-ibm-streams-docker-local.artifactory.swg-devops.com/pipelines-tutorial/k8s-helm:latest"
#}]' --type=json

set +e
oc delete -f ${repo_root}/pipeline/pipeline.yaml
set -e
oc apply -f ${repo_root}/pipeline/pipeline.yaml

image_source_repo="wcp-ibm-streams-docker-local.artifactory.swg-devops.com"

set +e
oc delete secret -n ${unique_prefix} regcred --wait
oc delete secret -n ${unique_prefix} regcred-test --wait
oc delete secret -n ${unique_prefix} sourceregcred --wait
set -e
set +x
helper_text="If this step fails:

1. login to one of the openshift clusters here: https://github.ibm.com/IBM-Streams/infra-streams#for-openshift-4x
2. oc get secret -n openshift-config pull-secret -o yaml > /tmp/secret.yaml
3. login to your target cluster again
4. oc create -f /tmp/secret.yaml
5. re-run bootstrap.sh
"
set -x

set +e 
oc get secret -n openshift-config pull-secret -o yaml > ${TMP}/secret.yaml
rc=$?
if [[ ${rc} -eq 0 ]]; then
    helper_text=""
    oc get secret -n openshift-config pull-secret -o=go-template='{{index .data ".dockerconfigjson"}}' | base64 --decode | grep wcp-ibm-streams-docker-local
    rc=$?
    if [[ ${rc} -eq 0 ]]; then
        set -e
        cp ${TMP}/secret.yaml ${TMP}/secret.yaml.orig
        sed -i.bak "s|namespace: openshift-config|namespace: ${unique_prefix}|g" ${TMP}/secret.yaml
        sed -i.bak "s|name: pull-secret|name: regcred|g" ${TMP}/secret.yaml
        cat ${TMP}/secret.yaml
        oc apply -f ${TMP}/secret.yaml
    else
        if [[ ! -z ${ARTIFACTORY_APIKEY} ]]; then
            set -e
            auth=$(echo -n "${image_source_repo_username:-$git_username}:${ARTIFACTORY_APIKEY}" | base64 -w 0)
            cat > ${TMP}/secret.yaml <<EOH
{"auths":{"${image_source_repo}":{"username":"${image_source_repo_username:-$git_username}","password":"${ARTIFACTORY_APIKEY}","auth":"${auth}"}}}
EOH
            kubectl create secret -n ${unique_prefix} generic regcred --from-file=.dockerconfigjson=${TMP}/secret.yaml --type=kubernetes.io/dockerconfigjson
        else
            helper_text="Run the following commands to set up credentials for artifactory:

            export ARTIFACTORY_APIKEY=xxx
            export image_source_repo_username=user@email.com
            "
            exit 1
        fi
    fi
else
    helper_text=""
    if [[ ! -z ${ARTIFACTORY_APIKEY} ]]; then
        set -e
        auth=$(echo -n "${image_source_repo_username:-$git_username}:${ARTIFACTORY_APIKEY}" | base64 -w 0)
        cat > ${TMP}/secret.yaml <<EOH
{"auths":{"${image_source_repo}":{"username":"${image_source_repo_username:-$git_username}","password":"${ARTIFACTORY_APIKEY}","auth":"${auth}"}}}
EOH
        kubectl create secret -n ${unique_prefix} generic regcred --from-file=.dockerconfigjson=${TMP}/secret.yaml --type=kubernetes.io/dockerconfigjson
    else
        helper_text="Run the following commands to set up credentials for artifactory:
    
        export ARTIFACTORY_APIKEY=xxx
        export image_source_repo_username=user@email.com
        "
        exit 1
    fi
fi

if [[ ${is_openshift} == "true" ]]; then
    oc secrets link pipeline regcred --for=mount
    oc secrets link builder regcred --for=mount
    oc secrets link pipeline regcred --for=pull
else
    kubectl patch serviceaccount default -p '{"imagePullSecrets": [{"name": "regcred"}]}'
    kubectl patch serviceaccount default -p '{"secrets": [{"name": "regcred"}]}'
fi

cluster_scoped="false"
deploy_vault="false"
if [[ "${unique_prefix}" == "m4d-system" ]]; then
    extra_params='-p clusterScoped="true" -p deployVault="true"'
    cluster_scoped="true"
    deploy_vault="true"
fi
set +e
oc get crd | grep "m4dapplications.app.m4d.ibm.com"
rc=$?
deploy_crd="false"
if [[ $rc -ne 0 ]]; then
    extra_params="${extra_params} -p deployCRD='true'"
    deploy_crd="true"
fi

oc get crd | grep "certmanager"
rc=$?
deploy_cert_manager="false"
if [[ $rc -ne 0 ]]; then
    extra_params="${extra_params} -p deployCertManager='true'"
    deploy_cert_manager="true"
fi

set +e
oc get ns m4d-system
rc=$?
set -e
if [[ $rc -ne 0 ]]; then
    set +x
    helper_text="please install into m4d-system first - currently vault can only be installed in one namespace, and needs to go in m4d-system"
    exit 1
fi

oc apply -f ${repo_root}/pipeline/rootsa.yaml
oc apply -f ${TMP}/statefulset.yaml
oc apply -f ${repo_root}/pipeline/pvc.yaml
if [[ ${is_openshift} == "true" ]]; then
    oc adm policy add-scc-to-user privileged system:serviceaccount:${unique_prefix}:root-sa
fi

pushd ${TMP}
wget https://storage.googleapis.com/tekton-releases/triggers/latest/release.yaml
if [[ ${is_openshift} == "true" ]]; then
    sed -i.bak 's|namespace: tekton-pipelines|namespace: openshift-pipelines|g' ${TMP}/release.yaml
fi
cat ${TMP}/release.yaml
wget https://storage.googleapis.com/tekton-releases/triggers/latest/interceptors.yaml
if [[ ${is_openshift} == "true" ]]; then
    sed -i.bak 's|namespace: tekton-pipelines|namespace: openshift-pipelines|g' ${TMP}/interceptors.yaml
fi
cat ${TMP}/interceptors.yaml
popd

oc apply -f ${TMP}/release.yaml
oc apply -f ${TMP}/interceptors.yaml

oc apply -f ${repo_root}/pipeline/eventlistener/generic-image-pipeline.yaml
oc apply -f ${repo_root}/pipeline/eventlistener/generic-triggerbinding.yaml
oc apply -f ${repo_root}/pipeline/eventlistener/generic-triggertemplate.yaml
oc apply -f ${repo_root}/pipeline/eventlistener/generic-watcher-apiserversource.yaml
oc apply -f ${repo_root}/pipeline/eventlistener/generic-watcher-role.yaml
oc apply -f ${repo_root}/pipeline/eventlistener/generic-watcher-serviceaccount.yaml
oc apply -f ${repo_root}/pipeline/eventlistener/print-generic-task.yaml

set +x
helper_text="If this step fails, run again - knative related pods may be restarting and unable to process the webhook
"
set -x
oc apply -f ${repo_root}/pipeline/eventlistener/generic-eventlistener.yaml
helper_text=""
set +e
oc delete rolebinding generic-watcher
set -e
oc create rolebinding generic-watcher --role=generic-watcher --serviceaccount=${unique_prefix}:generic-watcher

set +e
oc delete secret git-ssh-key
oc delete secret git-token
set -e

if [[ -z ${GH_TOKEN} ]]; then
    cat ~/.ssh/known_hosts | base64 -w 0 > ${TMP}/known_hosts
    set +x
    helper_text="If this step fails, make the second positional arg the path to an ssh key authenticated with Github Enterprise
    
    ex: bash -x bootstrap.sh m4d-system /path/to/private/ssh/key
    "
    set -x
    oc create secret generic git-ssh-key --from-file=ssh-privatekey=${ssh_key} --type=kubernetes.io/ssh-auth
    helper_text=""
    oc annotate secret git-ssh-key --overwrite 'tekton.dev/git-0'="${github}"
    if [[ ${is_openshift} == "true" ]]; then
        oc secrets link pipeline git-ssh-key --for=mount
        set +e
        oc secrets unlink pipeline git-token
    else
        kubectl patch serviceaccount default -p '{"secrets": [{"name": "git-ssh-key"}]}'
        set +e
#        kubectl patch serviceaccount default --type=json -p='[{"op": "remove", "path": "/data/mykey"}]'
#        kubectl patch deploy/some-deployment --type=json -p='[{"op": "remove", "path": "/spec/template/spec/containers/0/ports/0"},{"op": "remove", "path": "/spec/template/spec/containers/0/ports/2"}]
#        oc get sa default -o yaml | grep -A3 "secrets:" | awk '/git-token/ { print NR }' 
    fi
    set -e
    extra_params="${extra_params} -p git-url=git@${github}:IBM-Data-Fabric/mesh-for-data.git -p wkc-connector-git-url=git@${github}:ngoracke/WKC-connector.git -p vault-plugin-secrets-wkc-reader-url=git@${github}:data-mesh-research/vault-plugin-secrets-wkc-reader.git"
else
    cat > ${TMP}/git-token.yaml <<EOH
apiVersion: v1
kind: Secret
metadata:
  name: git-token
  annotations:
    tekton.dev/git-0: https://${github} # Described below
type: kubernetes.io/basic-auth
stringData:
  username: ${git_user}
  password: ${GH_TOKEN}
EOH
    oc apply -f ${TMP}/git-token.yaml
    if [[ ${is_openshift} == "true" ]]; then
        oc secrets link pipeline git-token --for=mount
        set +e
        oc secrets unlink pipeline git-ssh-key
    else
        kubectl patch serviceaccount default -p '{"secrets": [{"name": "git-token"}]}'
        set +e
    fi
    set -e
    extra_params="${extra_params} -p git-url=https://${github}/IBM-Data-Fabric/mesh-for-data.git -p wkc-connector-git-url=https://${github}/ngoracke/WKC-connector.git -p vault-plugin-secrets-wkc-reader-url=https://${github}/data-mesh-research/vault-plugin-secrets-wkc-reader.git"
fi
cat > ${TMP}/wkc-credentials.yaml <<EOH
apiVersion: v1
kind: Secret
metadata:
  name: wkc-credentials
  namespace: ${unique_prefix} 
type: kubernetes.io/Opaque
stringData:
  CP4D_USERNAME: admin 
  CP4D_PASSWORD: password
  CP4D_SERVER_URL: https://cpd-tooling-2q21-cpd.apps.cpstreamsx3.cp.fyre.ibm.com
EOH
cat ${TMP}/wkc-credentials.yaml
oc apply -f ${TMP}/wkc-credentials.yaml

extra_params="${extra_params} -p wkcConnectorServerUrl=https://cpd-tooling-2q21-cpd.apps.cpstreamsx3.cp.fyre.ibm.com"
#set +e
#oc -n ${unique_prefix} delete configmap sample-policy
#set -e
#oc -n ${unique_prefix} create configmap sample-policy --from-file=sample-policy.rego
#oc -n ${unique_prefix} label configmap sample-policy openpolicyagent.org/policy=rego

#if [[ ${unique_prefix} != "m4d-system" ]]; then
#    set +e
#    oc delete secrets vault-credentials -n ${unique_prefix}
#    set -e
#    oc get secrets vault-credentials -n m4d-system -o jsonpath={.data.VAULT_TOKEN} | base64 --decode > ${TMP}/token.txt
#    oc create secret generic vault-credentials --from-file=VAULT_TOKEN=${TMP}/token.txt -n ${unique_prefix}
#fi

set +e
oc get secret us-south-creds
rc=$?
transfer_images_to_icr=false
if [[ $rc -eq 0 ]]; then
    transfer_images_to_icr=true
fi

set -e
set +x
#echo "install tekton extension is vscode and then run:
# for a dynamically provisioned PVC that will be deleted when the pipelinerun is deleted
#tkn pipeline start build-and-deploy -w name=shared-workspace,volumeClaimTemplateFile=${repo_root}/pipeline/pvc.yaml -p docker-namespace=${unique_prefix} -p git-revision=pipeline -p NAMESPACE=${unique_prefix} ${extra_params}"

echo "
# for a pre-existing PVC that will be deleted when the namespace is deleted
tkn pipeline start build-and-deploy -w name=images-url,emptyDir="" -w name=artifacts,claimName=artifacts-pvc -w name=shared-workspace,claimName=source-pvc -p docker-hostname=${image_repo} -p dockerhub-hostname=${dockerhub_hostname} -p docker-namespace=${unique_prefix} -p NAMESPACE=${unique_prefix} -p skipTests=${skip_tests} -p transfer-images-to-icr=${transfer_images_to_icr} ${extra_params} -p git-revision=pipeline"

if [[ ${run_tkn} -eq 1 ]]; then
    set -x
    #tkn pipeline start build-and-deploy -w name=images-url,emptyDir="" -w name=artifacts,claimName=artifacts-pvc -w name=shared-workspace,claimName=source-pvc -p docker-hostname=image-registry.openshift-image-registry.svc:5000 -p docker-namespace=${unique_prefix} -p git-url=git@${github}:IBM-Data-Fabric/mesh-for-data.git -p git-revision=pipeline -p NAMESPACE=${unique_prefix} ${extra_params} --dry-run > ${TMP}/pipelinerun.yaml

    cat > ${TMP}/pipelinerun.yaml <<EOH
apiVersion: tekton.dev/v1beta1
kind: PipelineRun
metadata:
  labels:
    tekton.dev/pipeline: build-and-deploy
  name: build-and-deploy-run
  namespace: ${unique_prefix} 
spec:
  params:
  - name: NAMESPACE
    value: ${unique_prefix} 
  - name: docker-hostname
    value: ${image_repo}
  - name: dockerhub-hostname
    value: ${dockerhub_hostname}
  - name: docker-namespace
    value: ${unique_prefix} 
  - name: git-revision
    value: pipeline
  - name: wkcConnectorServerUrl
    value: https://cpd-tooling-2q21-cpd.apps.cpstreamsx3.cp.fyre.ibm.com
  - name: git-url
    value: https://${github}/IBM-Data-Fabric/mesh-for-data.git
  - name: wkc-connector-git-url
    value: https://${github}/ngoracke/WKC-connector.git
  - name: vault-plugin-secrets-wkc-reader-url 
    value: https://${github}/data-mesh-research/vault-plugin-secrets-wkc-reader.git
  - name: skipTests
    value: "${skip_tests}"
  - name: transfer-images-to-icr
    value: "${transfer_images_to_icr}"
  - name: clusterScoped
    value: "${cluster_scoped}"
  - name: deployVault
    value: "${deploy_vault}"
  - name: deployCRD
    value: "${deploy_crd}"
  - name: build_image
    value: "${build_image}"
  - name: helm_image
    value: "${helm_image}"
  - name: deployCertManager
    value: "${deploy_cert_manager}"
  pipelineRef:
    name: build-and-deploy
  serviceAccountName: ${pipeline_sa}
  timeout: 1h0m0s
  workspaces:
  - emptyDir: {}
    name: images-url
  - name: artifacts
    persistentVolumeClaim:
      claimName: artifacts-pvc
  - name: shared-workspace
    persistentVolumeClaim:
      claimName: source-pvc
EOH
    cat ${TMP}/pipelinerun.yaml
    oc apply -f ${TMP}/pipelinerun.yaml
 
    cat > ${TMP}/streams_csv_check_script.sh <<EOH
#!/bin/bash
set -x
oc get taskrun,pvc,po
for i in $(oc get taskrun --no-headers | grep "False" | cut -d' ' -f1); do oc logs -l tekton.dev/taskRun=$i --all-containers; done
oc get pipelinerun --no-headers
oc get pipelinerun --no-headers | grep -e "Failed" -e "Succeeded"
EOH
    chmod u+x ${TMP}/streams_csv_check_script.sh
    try_command "${TMP}/streams_csv_check_script.sh"  40 false 30 
fi
