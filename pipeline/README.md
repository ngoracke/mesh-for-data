# Tekton pipeline 

[vscode tekton extension doc](https://github.com/redhat-developer/vscode-tekton)

## Bootstrapping

Initial install for a cluster must happen in m4d-system (currently)
```
bash -x bootstrap-pipeline.sh m4d-system
# follow on screen instructions
```

Subsequent installs can go in any namespace
```
bash -x bootstrap-pipeline.sh m4d-myname
# follow on screen instructions
```
