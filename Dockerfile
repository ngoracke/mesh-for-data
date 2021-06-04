FROM wcp-ibm-streams-docker-local.artifactory.swg-devops.com/dev_ngoracke/suede:latest as builder

WORKDIR /build
ADD . /build/


RUN mkdir /tmp/cache
RUN make -C manager manager
RUN ls -l

FROM gcr.io/distroless/static:nonroot
WORKDIR /
COPY --from=builder manager .
USER nonroot:nonroot

ENTRYPOINT ["/manager"]
