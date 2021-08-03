# Tekton pipeline 

[vscode tekton pipelines extension doc](https://github.com/redhat-developer/vscode-tekton)

## Bootstrapping

Initial install for a cluster must happen in fybrik-system (currently).  It won't hurt anything if you aren't sure, and reinstall in fybrik-system.
```
bash -x bootstrap-pipeline.sh fybrik-system
# follow on screen instructions
```

Subsequent installs can go in any namespace
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
