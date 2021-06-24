#!/bin/bash
set -e
set +e

realpath() {
    [[ $1 = /* ]] && echo "$1" || echo "$PWD/${1#./}"
}

repo_root=$(realpath $(dirname $(realpath $0)))/..

. ${repo_root}/pipeline/common_functions.sh

function cleanup {
    if [[ ! -z ${TMP} ]]; then
        rm -rf ${TMP}
#        echo "Deleted temp working directory ${TMP}"
    fi
}

if [[ -z "$TMP" ]]; then
    TMP=$(mktemp -d) || exit 1
    trap cleanup EXIT
fi

rc=1
if [[ ! -z $1 ]]; then
    oc get project $1
    rc=$?
else
    oc get project m4d-system
    rc=$?
fi
set -e
if [[ $rc -ne 0 ]]; then
    oc new-project ${1:-m4d-system}
else
    oc project ${1:-m4d-system} 
fi
unique_prefix=$(kubectl config view --minify --output 'jsonpath={..namespace}'; echo)

set +e
# Be smarter about this - just a quick hack for typical default installs
oc patch storageclass managed-nfs-storage -p '{"metadata": {"annotations": {"storageclass.kubernetes.io/is-default-class": "true"}}}'
set -e

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
oc get -n openshift-operators csv | grep serverless-operator | grep Succeeded
EOH
chmod u+x ${TMP}/streams_csv_check_script.sh
try_command "${TMP}/streams_csv_check_script.sh"  40 true 5

oc adm policy add-cluster-role-to-user cluster-admin system:serviceaccount:${unique_prefix}:pipeline
set +e
#resource_version=$(oc get -f ${repo_root}/pipeline/make.yaml -o jsonpath='{.metadata.resourceVersion}')
set -e
oc apply -f ${repo_root}/pipeline/make.yaml
oc apply -f ${repo_root}/pipeline/git-clone.yaml
oc apply -f ${repo_root}/pipeline/buildah.yaml
oc apply -f ${repo_root}/pipeline/knative-eventing.yaml

oc patch clustertask helm-upgrade-from-repo -p '
[{
  "op": "replace",
  "path": "/spec/steps/0/image",
  "value": "wcp-ibm-streams-docker-local.artifactory.swg-devops.com/pipelines-tutorial/k8s-helm:latest"
}]' --type=json

oc patch clustertask helm-upgrade-from-source -p '
[{
  "op": "replace",
  "path": "/spec/steps/0/image",
  "value": "wcp-ibm-streams-docker-local.artifactory.swg-devops.com/pipelines-tutorial/k8s-helm:latest"
}]' --type=json

set +e
oc delete -f ${repo_root}/pipeline/pipeline.yaml
set -e
oc apply -f ${repo_root}/pipeline/pipeline.yaml

art="c3RybWR2b3BAdXMuaWJtLmNvbTpBS0NwNWUzb3gxa1Y0ZXJuaVIzTDNma244QlpkWVJEUHlUWTlpZTRjMTVwUTFrZjZzTWc2Vko0RGdYWWJHSFNUVW9Kakh1UFdl"
art_u=$(echo "${art}" | base64 --decode | cut -d: -f 1)
art_p=$(echo "${art}" | base64 --decode | cut -d: -f 2)

reg_username=${art_u}
reg_password=${art_p}
auth=${art}

image_repo="wcp-ibm-streams-docker-local.artifactory.swg-devops.com"
cat > ${TMP}/secret.yaml <<EOH
{"auths":{"${image_source_repo:-$image_repo}":{"username":"${reg_username}","password":"${reg_password}","auth":"${auth}"}}}
EOH

set +e
oc delete secret -n ${unique_prefix} regcred --wait
oc delete secret -n ${unique_prefix} regcred-test --wait
oc delete secret -n ${unique_prefix} sourceregcred --wait
set -e
oc create secret generic -n ${unique_prefix} regcred --from-file=.dockerconfigjson=${TMP}/secret.yaml --type=kubernetes.io/dockerconfigjson
oc create secret generic -n ${unique_prefix} regcred-test --from-file=.dockerconfigjson=${TMP}/secret.yaml --type=kubernetes.io/dockerconfigjson
oc create secret generic -n ${unique_prefix} sourceregcred --from-file=.dockerconfigjson=${TMP}/secret.yaml --type=kubernetes.io/dockerconfigjson

oc secrets link pipeline regcred --for=mount
oc secrets link builder regcred --for=mount
oc secrets link pipeline regcred --for=pull

if [[ "${unique_prefix}" == "m4d-system" ]]; then
    extra_params='-p clusterScoped="true" -p deployVault="true"'
fi
set +e
oc get crd | grep "m4dapplications.app.m4d.ibm.com"
rc=$?
if [[ $rc -ne 0 ]]; then
    extra_params="${extra_params} deployCRD='true'"
fi

oc get crd | grep "cert-manager"
if [[ $rc -ne 0 ]]; then
    extra_params="${extra_params} deployCertManager='true'"
fi

set +e
oc get project m4d-system
rc=$?
set -e
if [[ $rc -ne 0 ]]; then
    set +x
    echo "please install into m4d-system first - currently vault can only be installed in one namespace, and needs to go in m4d-system"
    exit 1
fi

oc apply -f ${repo_root}/pipeline/rootsa.yaml
oc apply -f ${repo_root}/pipeline/statefulset.yaml
oc apply -f ${repo_root}/pipeline/pvc.yaml
oc adm policy add-scc-to-user privileged system:serviceaccount:${unique_prefix}:root-sa

oc apply -f ${repo_root}/pipeline/eventlistener/generic-image-pipeline.yaml
oc apply -f ${repo_root}/pipeline/eventlistener/generic-triggerbinding.yaml
oc apply -f ${repo_root}/pipeline/eventlistener/generic-triggertemplate.yaml
oc apply -f ${repo_root}/pipeline/eventlistener/generic-watcher-apiserversource.yaml
oc apply -f ${repo_root}/pipeline/eventlistener/generic-watcher-role.yaml
oc apply -f ${repo_root}/pipeline/eventlistener/generic-watcher-serviceaccount.yaml
oc apply -f ${repo_root}/pipeline/eventlistener/print-generic-task.yaml

pushd ${TMP}
wget https://storage.googleapis.com/tekton-releases/triggers/latest/release.yaml
sed -i.bak 's|namespace: tekton-pipelines|namespace: openshift-pipelines|g' ${TMP}/release.yaml
cat ${TMP}/release.yaml
wget https://storage.googleapis.com/tekton-releases/triggers/latest/interceptors.yaml
sed -i.bak 's|namespace: tekton-pipelines|namespace: openshift-pipelines|g' ${TMP}/interceptors.yaml
cat ${TMP}/interceptors.yaml
popd

oc apply -f ${TMP}/release.yaml
oc apply -f ${TMP}/interceptors.yaml

oc apply -f ${repo_root}/pipeline/eventlistener/generic-eventlistener.yaml
set +e
oc delete rolebinding generic-watcher
set -e
oc create rolebinding generic-watcher --clusterrole=generic-watcher --serviceaccount=${unique_prefix}:generic-watcher

set +x
echo "install tekton extension is vscode and then run:
# for a dynamically provisioned PVC that will be deleted when the pipelinerun is deleted
tkn pipeline start build-and-deploy -w name=shared-workspace,volumeClaimTemplateFile=${repo_root}/pipeline/pvc.yaml -p docker-namespace=${unique_prefix} -p git-url=https://github.com/ngoracke/mesh-for-data.git -p git-revision=pipeline -p NAMESPACE=${unique_prefix} ${extra_params}"

# for a pre-existing PVC that will be deleted when the namespace is deleted
echo "tkn pipeline start build-and-deploy -w name=shared-workspace,claimName=source-pvc -p docker-namespace=${unique_prefix} -p git-url=https://github.com/ngoracke/mesh-for-data.git -p git-revision=pipeline -p NAMESPACE=${unique_prefix} ${extra_params}"
