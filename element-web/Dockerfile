ARG BUILD_FROM
FROM ${BUILD_FROM}

ENV FLUFFYCHAT_VERSION=v2.4.1

RUN apk add --no-cache nginx curl tar jq

RUN mkdir -p /opt/fluffychat /run/nginx && \
    curl -L -o /tmp/fluffychat-web.tar.gz \
    "https://github.com/krille-chan/fluffychat/releases/download/${FLUFFYCHAT_VERSION}/fluffychat-web.tar.gz" && \
    tar xzf /tmp/fluffychat-web.tar.gz -C /opt/fluffychat --strip-components=2 && \
    rm /tmp/fluffychat-web.tar.gz

COPY nginx.conf /etc/nginx/http.d/default.conf
COPY run.sh /run.sh
RUN chmod +x /run.sh

CMD ["/run.sh"]
