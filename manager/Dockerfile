# Copyright 2020 IBM Corp.
# SPDX-License-Identifier: Apache-2.0

FROM registry.access.redhat.com/ubi8/ubi-minimal
ENV HOME=/tmp
WORKDIR /tmp
COPY manager /
USER 1001

ENTRYPOINT ["/manager"]
