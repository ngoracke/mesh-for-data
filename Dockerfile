FROM wcp-ibm-streams-docker-local.artifactory.swg-devops.com/dev_ngoracke/suede:latest as builder

RUN yum -y install tree
WORKDIR /build
ADD . /build/


RUN mkdir /tmp/cache
RUN make -C manager manager
RUN ls -l && tree && pwd

FROM gcr.io/distroless/static:nonroot
WORKDIR /
COPY --from=builder /build/manager/manager/* .
USER nonroot:nonroot

ENTRYPOINT ["/manager"]
