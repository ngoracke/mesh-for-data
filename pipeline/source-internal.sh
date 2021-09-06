#!/bin/bash
export git_user=${git_user}
export GH_TOKEN=${GH_TOKEN}
export github_workspace=${github_workspace}
export image_source_repo_username=${image_source_repo_username}
export image_source_repo_password=${ARTIFACTORY_APIKEY}
export run_tkn=${run_tkn:-0}
export skip_tests=${skip_tests:-false}
export cluster_scoped=${cluster_scoped:-false}
export github=${github:-github.ibm.com}
export image_repo="${image_repo:-image-registry.openshift-image-registry.svc:5000}"
export image_source_repo="${image_source_repo:-cp.stg.icr.io/cp/cpd}"
export dockerhub_hostname="${dockerhub_hostname:-cp.stg.icr.io/cp/cpd/pipelines-tutorial}"
export cpd_url=https://cpd-cpd4.apps.cpstreamsx4.cp.fyre.ibm.com
export git_url=git@${github}:IBM-Data-Fabric/mesh-for-data.git
export wkc_connector_git_url=git@${github}:IBM-Data-Fabric/WKC-connector.git
export cpd_password=password
export cpd_username=admin
export vault_plugin_secrets_wkc_reader_url=git@${github}:data-mesh-research/vault-plugin-secrets-wkc-reader.git
export git_url="git@${github}:IBM-Data-Fabric/mesh-for-data.git"
export wkc_connector_git_url="git@${github}:IBM-Data-Fabric/WKC-connector.git"
export vault_plugin_secrets_wkc_reader_url="git@${github}:data-mesh-research/vault-plugin-secrets-wkc-reader.git"
export proprietary_git_url="git@${github}:IBM-Data-Fabric/proprietary.git"
export data_fabric_git_url="git@${github}:IBM-Data-Fabric/data-fabric-control-plane.git"
export cluster_scoped=false
export use_application_namespace=true
export va_scan_namespace=${va_scan_namespace:-mesh-for-data-ci}

if [[ ! -z ${GH_TOKEN} ]]; then
    export git_url="https://${github}/IBM-Data-Fabric/mesh-for-data.git"
    export wkc_connector_git_url="https://${github}/IBM-Data-Fabric/WKC-connector.git"
    export vault_plugin_secrets_wkc_reader_url="https://${github}/data-mesh-research/vault-plugin-secrets-wkc-reader.git"
    export proprietary_git_url="https://${github}/IBM-Data-Fabric/proprietary.git"
    export data_fabric_git_url="https://${github}/IBM-Data-Fabric/data-fabric-control-plane.git"
fi

echo "
## Git credentials

For authenticated registries, if you use a git token instead of ssh key, credentials will not be deleted when the run is complete (and therefore, you will not have to regenerate them when restarting tasks).
https://github.ibm.com/settings/tokens

export GH_TOKEN=xxxxxxx
export git_user=user@email.com
"
