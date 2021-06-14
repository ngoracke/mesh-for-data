#!/bin/bash
set -e
set +e
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
    oc create ns ${1:-m4d-system}
else
    oc project ${1:-m4d-system} 
fi
unique_prefix=$(kubectl config view --minify --output 'jsonpath={..namespace}'; echo)

realpath() {
    [[ $1 = /* ]] && echo "$1" || echo "$PWD/${1#./}"
}

repo_root=$(realpath $(dirname $(realpath $0)))

oc adm policy add-cluster-role-to-user cluster-admin system:serviceaccount:${unique_prefix}:pipeline
oc apply -f pipeline/make.yaml
set +e
oc delete -f pipeline/pipeline.yaml
set -e
oc apply -f pipeline/pipeline.yaml

art="c3RybWR2b3BAdXMuaWJtLmNvbTpBS0NwNWUzb3gxa1Y0ZXJuaVIzTDNma244QlpkWVJEUHlUWTlpZTRjMTVwUTFrZjZzTWc2Vko0RGdYWWJHSFNUVW9Kakh1UFdl"
art_u=$(echo "${art}" | base64 --decode | cut -d: -f 1)
art_p=$(echo "${art}" | base64 --decode | cut -d: -f 2)
stage="aWFtYXBpa2V5OjQ5dDRlQ0F4V1p6SlV4cEs5SktSYjdZNzhVbEpyanZIN2NDLU04OFBJNHpuCg=="
stage_u=$(echo "${stage}" | base64 --decode | cut -d: -f 1)
stage_p=$(echo "${stage}" | base64 --decode | cut -d: -f 2)
icr="aWFtYXBpa2V5Om1jRzF6bjVLeGVSZjRQdWVGU0RETEZuLS01MmV2cGJPcVFBTzJVYkhYU0c5"
icr_u=$(echo "${icr}" | base64 --decode | cut -d: -f 1)
icr_p=$(echo "${icr}" | base64 --decode | cut -d: -f 2)

reg_username=${art_u}
reg_password=${art_p}
auth=${art}

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

curl -kLo ${TMP}/tkn-linux-amd64-0.17.2.tar.gz https://mirror.openshift.com/pub/openshift-v4/clients/pipeline/0.17.2/tkn-linux-amd64-0.17.2.tar.gz
tar -xvf ${TMP}/tkn-linux-amd64-0.17.2.tar.gz -C ${TMP}/
cp ${TMP}/tkn ~/streams.helm-charts/bin/

if [[ "${unique_prefix}" == "m4d-system" ]]; then
    extra_params='-p clusterScoped="true" -p deployVault="true"'
fi
set +e
oc get crd | grep "m4dapplications.app.m4d.ibm.com"
rc=$?
if [[ $rc -ne 0 ]]; then
    extra_params="${extra_params} deployCRD='true'"
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

set +x
echo "install tekton extension is vscode and then run:
tkn pipeline start build-and-deploy -w name=shared-workspace,volumeClaimTemplateFile=${repo_root}/pipeline/pvc.yaml -p deployment-name=m4d -p git-url=https://github.com/ngoracke/mesh-for-data.git -p git-revision=pipeline -p NAMESPACE=${unique_prefix} ${extra_params}"
