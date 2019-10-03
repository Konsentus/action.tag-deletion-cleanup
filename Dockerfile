FROM alpine:latest

ADD entrypoint.sh /entrypoint.sh

RUN apk add --no-cache bash
RUN apk add --no-cache jq

ENTRYPOINT ["/entrypoint.sh"]
