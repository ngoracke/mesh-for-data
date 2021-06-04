FROM wcp-ibm-streams-docker-local.artifactory.swg-devops.com/dev_ngoracke/suede:latest as builder

WORKDIR /build
ADD . /build/


RUN mkdir /tmp/cache
RUN make -C manager manager

FROM gcr.io/distroless/static:nonroot
WORKDIR /
COPY manager .
RUN ls -l /
USER nonroot:nonroot

ENTRYPOINT ["/manager"]
