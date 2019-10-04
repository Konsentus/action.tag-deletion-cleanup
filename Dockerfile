FROM alpine:latest

ADD entrypoint.sh /entrypoint.sh

RUN apk add --no-cache bash
RUN apk add --no-cache jq
RUN apk add --no-cache git

ENTRYPOINT ["/entrypoint.sh"]
