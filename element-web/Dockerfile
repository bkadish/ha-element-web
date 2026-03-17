ARG BUILD_FROM
FROM ${BUILD_FROM}

ENV ELEMENT_WEB_VERSION=v1.12.11

RUN apk add --no-cache nginx curl tar

RUN mkdir -p /opt/element-web && \
    curl -L -o /tmp/element-web.tar.gz \
    "https://github.com/element-hq/element-web/releases/download/${ELEMENT_WEB_VERSION}/element-${ELEMENT_WEB_VERSION}.tar.gz" && \
    tar xzf /tmp/element-web.tar.gz -C /opt/element-web --strip-components=1 && \
    rm /tmp/element-web.tar.gz

RUN mkdir -p /run/nginx

COPY nginx.conf /etc/nginx/http.d/default.conf

# s6-overlay v3 service setup
RUN mkdir -p /etc/s6-overlay/s6-rc.d/element/dependencies.d \
    && mkdir -p /etc/s6-overlay/s6-rc.d/user/contents.d \
    && echo "longrun" > /etc/s6-overlay/s6-rc.d/element/type \
    && touch /etc/s6-overlay/s6-rc.d/user/contents.d/element

COPY run.sh /etc/s6-overlay/s6-rc.d/element/run
RUN chmod a+x /etc/s6-overlay/s6-rc.d/element/run

# Init script for config generation
COPY init.sh /etc/cont-init.d/element.sh
RUN chmod a+x /etc/cont-init.d/element.sh
