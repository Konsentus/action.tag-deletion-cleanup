FROM alpine:latest

RUN apk add --no-cache \
    bash \
    jq \
    git \
    openssh-client

ADD entrypoint.sh /entrypoint.sh

ENTRYPOINT ["/entrypoint.sh"]
