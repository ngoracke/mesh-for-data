FROM wcp-ibm-streams-docker-local.artifactory.swg-devops.com/dev_ngoracke/suede:latest as builder

WORKDIR /build
ADD . /build/


RUN mkdir /tmp/cache
RUN make -C manager managerforimage
#CGO_ENABLED=0 GOOS=linux GOARCH=amd64 GO111MODULE=on go build -o manager main.go
RUN ls -l && pwd && ls -l manager

FROM gcr.io/distroless/static:nonroot
WORKDIR /
COPY --from=builder /build/manager/manager /manager
USER nonroot:nonroot

ENTRYPOINT ["/manager"]
