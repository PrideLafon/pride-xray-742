FROM alpine:3.19 AS builder

ARG XRAY_VERSION=25.1.1
WORKDIR /tmp

RUN apk add --no-cache curl tar && \
    curl -fsSL -o xray.tar.gz \
    "https://github.com/XTLS/Xray-core/releases/download/v${XRAY_VERSION}/Xray-linux-64.tar.gz" && \
    tar -xzf xray.tar.gz && \
    chmod +x xray

FROM alpine:3.19

RUN apk add --no-cache ca-certificates

COPY --from=builder /tmp/xray /usr/local/bin/xray
COPY server.json /etc/xray/config.json

EXPOSE 8080

ENTRYPOINT ["/usr/local/bin/xray"]
CMD ["-config", "/etc/xray/config.json"]
