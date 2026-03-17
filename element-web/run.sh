#!/usr/bin/with-contenv bashio

HOMESERVER_URL=$(bashio::config 'homeserver_url')
SERVER_NAME=$(bashio::config 'server_name')
INGRESS_ENTRY=$(bashio::addon.ingress_entry)

bashio::log.info "Configuring Element Web..."
bashio::log.info "Homeserver URL: ${HOMESERVER_URL}"
bashio::log.info "Server name: ${SERVER_NAME}"
bashio::log.info "Ingress entry: ${INGRESS_ENTRY}"

# Write Element Web config
cat > /opt/element-web/config.json <<EOF
{
    "default_server_config": {
        "m.homeserver": {
            "base_url": "${HOMESERVER_URL}",
            "server_name": "${SERVER_NAME}"
        }
    },
    "disable_custom_urls": false,
    "disable_guests": true,
    "brand": "Element",
    "default_theme": "dark",
    "room_directory": {
        "servers": ["${SERVER_NAME}"]
    }
}
EOF

# Update nginx config with ingress path
sed -i "s|%%INGRESS_ENTRY%%|${INGRESS_ENTRY}|g" /etc/nginx/http.d/default.conf

bashio::log.info "Starting Element Web on port 8765..."
exec nginx -g "daemon off;"
