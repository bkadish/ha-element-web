#!/bin/bash

OPTIONS_FILE="/data/options.json"

if [ -f "$OPTIONS_FILE" ]; then
    HOMESERVER_URL=$(jq -r '.homeserver_url' "$OPTIONS_FILE")
    SERVER_NAME=$(jq -r '.server_name' "$OPTIONS_FILE")
else
    echo "ERROR: No options.json found."
    exit 1
fi

# Validate config
if [ -z "$HOMESERVER_URL" ] || [ "$HOMESERVER_URL" = "null" ]; then
    echo "ERROR: homeserver_url not configured. Set it in the add-on Configuration tab."
    sleep infinity
fi

echo "Configuring Element Web..."
echo "Homeserver URL: ${HOMESERVER_URL}"
echo "Server name: ${SERVER_NAME}"

# Update nginx to proxy to the configured homeserver
sed -i "s|proxy_pass http://192.168.4.120:8008;|proxy_pass ${HOMESERVER_URL};|g" /etc/nginx/http.d/default.conf

# Create well-known directory for auto-discovery
mkdir -p /opt/element-web/.well-known/matrix
cat > /opt/element-web/.well-known/matrix/client <<EOF
{
    "m.homeserver": {
        "base_url": "ELEMENT_ORIGIN_PLACEHOLDER"
    }
}
EOF

# Write Element config - use empty base_url and let well-known handle discovery
# server_name triggers well-known lookup at /.well-known/matrix/client on same origin
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
    "enable_in_iframe": true,
    "setting_defaults": {
        "e2ee.manuallyVerifyAllSessions": false
    },
    "features": {
        "feature_dehydration": true
    },
    "show_labs_settings": true,
    "room_directory": {
        "servers": ["${SERVER_NAME}"]
    }
}
EOF

echo "Starting Element Web on port 8765..."
exec nginx -g "daemon off;"
