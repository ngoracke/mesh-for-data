# Tekton pipeline 

[vscode tekton pipelines extension doc](https://github.com/redhat-developer/vscode-tekton)

## Bootstrapping

Initial install for a cluster must happen in fybrik-system (currently).  It won't hurt anything if you aren't sure, and reinstall in fybrik-system.
```
. source-external.sh
bash -x bootstrap-pipeline.sh fybrik-system
# follow on screen instructions
```

Subsequent installs can go in any namespace
```
. source-external.sh
bash -x bootstrap-pipeline.sh fybrik-myname
# follow on screen instructions
```
