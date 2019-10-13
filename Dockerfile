FROM alpine:latest

RUN apk add --no-cache \
    bash \
    jq \
    git \
    openssh-client \
    hub

ADD entrypoint.sh /entrypoint.sh

ENTRYPOINT ["/entrypoint.sh"]
