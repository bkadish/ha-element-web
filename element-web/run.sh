#!/bin/bash

OPTIONS_FILE="/data/options.json"

if [ -f "$OPTIONS_FILE" ]; then
    HOMESERVER_URL=$(jq -r '.homeserver_url' "$OPTIONS_FILE")
    SERVER_NAME=$(jq -r '.server_name' "$OPTIONS_FILE")
else
    echo "ERROR: No options.json found. Configure homeserver_url and server_name in add-on settings."
    exit 1
fi

echo "Configuring Element Web..."
echo "Homeserver URL: ${HOMESERVER_URL}"
echo "Server name: ${SERVER_NAME}"

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

echo "Starting Element Web on port 8765..."
exec nginx -g "daemon off;"
