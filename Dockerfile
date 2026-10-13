FROM alpine:3.20 AS builder

WORKDIR /tmp

RUN apk add --no-cache curl unzip && \
    curl -fsSL -o xray.zip \
    "https://github.com/XTLS/Xray-core/releases/latest/download/Xray-linux-64.zip" && \
    unzip xray.zip xray && \
    chmod +x xray

FROM alpine:3.20

RUN apk add --no-cache ca-certificates

COPY --from=builder /tmp/xray /usr/local/bin/xray
COPY server.json /etc/xray/config.json

EXPOSE 8080

ENTRYPOINT ["/usr/local/bin/xray"]
CMD ["run", "-config", "/etc/xray/config.json"]
