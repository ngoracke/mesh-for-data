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
if [[ ! -z $2 ]]; then
    ssh_key=$2
else
    ssh_key=${HOME}/.ssh/id_rsa
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
oc adm policy add-role-to-group system:image-puller system:serviceaccounts:${unique_prefix} --namespace ${unique_prefix}

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

image_source_repo="wcp-ibm-streams-docker-local.artifactory.swg-devops.com"
image_repo="image-registry.openshift-image-registry.svc:5000"

set +e
oc delete secret -n ${unique_prefix} regcred --wait
oc delete secret -n ${unique_prefix} regcred-test --wait
oc delete secret -n ${unique_prefix} sourceregcred --wait
set -e
set +x
echo "If this step fails:

1. login to one of the openshift clusters here: https://github.ibm.com/IBM-Streams/infra-streams#for-openshift-4x
2. oc get secret -n openshift-config pull-secret -o yaml > /tmp/secret.yaml
3. login to your target cluster again
4. oc create -f /tmp/secret.yaml
5. re-run bootstrap.sh
"
set -x
 
oc get secret -n openshift-config pull-secret -o yaml > ${TMP}/secret.yaml
cp ${TMP}/secret.yaml ${TMP}/secret.yaml.orig
sed -i.bak "s|namespace: openshift-config|namespace: ${unique_prefix}|g" ${TMP}/secret.yaml
sed -i.bak "s|name: pull-secret|name: regcred|g" ${TMP}/secret.yaml
cat ${TMP}/secret.yaml
oc apply -f ${TMP}/secret.yaml

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

set +e
oc delete secret git-ssh-key
set -e
cat ~/.ssh/known_hosts | base64 > ${TMP}/known_hosts
set +x
echo "If this step fails, make the second positional arg the path to an ssh key authenticated with Github Enterprise

ex: bash -x bootstrap.sh m4d-system /path/to/private/ssh/key
"
set -x
oc create secret generic git-ssh-key --from-file=ssh-privatekey=${ssh_key} --type=kubernetes.io/ssh-auth
oc annotate secret git-ssh-key --overwrite 'tekton.dev/git-0'='github.ibm.com'
oc secrets link pipeline git-ssh-key --for=mount

set +x
#echo "install tekton extension is vscode and then run:
# for a dynamically provisioned PVC that will be deleted when the pipelinerun is deleted
#tkn pipeline start build-and-deploy -w name=shared-workspace,volumeClaimTemplateFile=${repo_root}/pipeline/pvc.yaml -p docker-namespace=${unique_prefix} -p git-url=https://github.com/ngoracke/mesh-for-data.git -p git-revision=pipeline -p NAMESPACE=${unique_prefix} ${extra_params}"

echo "
# for a pre-existing PVC that will be deleted when the namespace is deleted
tkn pipeline start build-and-deploy -w name=images-url,emptyDir="" -w name=artifacts,claimName=artifacts-pvc -w name=shared-workspace,claimName=source-pvc -p docker-hostname=image-registry.openshift-image-registry.svc:5000 -p docker-namespace=${unique_prefix} -p git-url=https://github.com/ngoracke/mesh-for-data.git -p git-revision=pipeline -p NAMESPACE=${unique_prefix} ${extra_params}"
