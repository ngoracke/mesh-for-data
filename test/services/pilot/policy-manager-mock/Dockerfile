FROM registry.access.redhat.com/ubi8/ubi-minimal

ENV HOME=/tmp
WORKDIR /tmp

COPY policy-manager-mock /
USER 1001

ENTRYPOINT ["/policy-manager-mock"]
