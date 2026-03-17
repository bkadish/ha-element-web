ARG BUILD_FROM
FROM alpine:3.19

ENV ELEMENT_WEB_VERSION=v1.12.11

RUN apk add --no-cache nginx curl tar bash jq

RUN mkdir -p /opt/element-web && \
    curl -L -o /tmp/element-web.tar.gz \
    "https://github.com/element-hq/element-web/releases/download/${ELEMENT_WEB_VERSION}/element-${ELEMENT_WEB_VERSION}.tar.gz" && \
    tar xzf /tmp/element-web.tar.gz -C /opt/element-web --strip-components=1 && \
    rm /tmp/element-web.tar.gz

RUN mkdir -p /run/nginx

COPY nginx.conf /etc/nginx/http.d/default.conf
COPY run.sh /run.sh
RUN chmod a+x /run.sh

CMD ["/run.sh"]
