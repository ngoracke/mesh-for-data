# Tekton pipeline 

[vscode tekton pipelines extension doc](https://github.com/redhat-developer/vscode-tekton)

## Bootstrapping

Initial install for a cluster must happen in m4d-system (currently).  It won't hurt anything if you aren't sure, and reinstall in m4d-system.
```
bash -x bootstrap-pipeline.sh m4d-system
# follow on screen instructions
```

Subsequent installs can go in any namespace
```
bash -x bootstrap-pipeline.sh m4d-myname
# follow on screen instructions
```
