# Tekton pipeline 

[vscode tekton pipelines extension doc](https://github.com/redhat-developer/vscode-tekton)

## Running cluster scoped or namespace scoped
In the following section the *system* namespace is the namespace specified when running the bootstrap script.

You can deploy Fybrik using the pipeline as cluster scoped or namespaced scoped. Deploying as namespaced scoped allows multiple instanced of Fybrik to be installed in unique namespaces in the same cluster. 

### Environment variables
| Name  | Default  | Valid Values | Description |
|-------|----------|--------------|-------------|
| cluster_scoped | false | true, false | Indicates if deploy as cluster scoped or not. If cluster_scoped=true; you can only install one Fybrik instance per cluster. |
| use_application_namespace | false | true, false | Specifies if you want the bootstrap script to create a namespace for FybrikApplications. This will be ignore if cluster_scoped=true. If set to false the *system* namespace will be used. |

### Tips
1. When deploying a Fybrik instance as cluster scoped:
   1. There can only be one instance deployed in cluster. 
   2. All FybrikApplication custom resources will be processed by the cluster scoped Fybrik.  
   3. You cannot run namespaced scoped and cluster scoped in same cluster.

2. When deploying a Fybrik instance as namespaced scoped:
   1. You can only create FybrikApplication custom resources from one namespace. The default will be to allow only creating from the *system* namespace. You can override this behavior by setting the use_application_namespace environment variable to true, the bootstrap code will create the *system*-app namespace and necessary objects to allow creating FybrikApplications. Hint: You will see the application namespace in the -p mesh-for-data-values= in the tkn command.

3. When using wkc-connector, the wkc-credentials secret must be in the same namespace you are using when creating FybrikApplication custom resources. The bootstrap script will unconditionally create a wkc-credentials secret in *system* namespace. 
   1. If running cluster_scoped=true and you use a different namespace than *system* for your FybrikApplications, you will need to create a wkc-credentials secret in that namespace. 
   2. If running cluster_scoped=false AND use_application_namespace=true, bootstrap will create the secret in *system*-app.


## Bootstrapping

Run the following command to bootstrap a Fybrik instance. The instance will be cluster scoped or namespace scoped depending on environment variables see [Running cluster scoped or namespace scoped](#running-cluster-scoped-or-namespace-scoped)
```
bash -x bootstrap-pipeline.sh fybrik-myname
# follow on screen instructions
```

## Git credentials

If you use a git token instead of ssh key, credentials will not be deleted when the run is complete (and therefore, you will not have to regenerate them when restarting tasks).
[Create a github token](https://github.ibm.com/settings/tokens)
```
export GH_TOKEN=xxxxxxx
export git_user=ngoracke@us.ibm.com
```
