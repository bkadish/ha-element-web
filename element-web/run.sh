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

# Get ingress entry from supervisor API
INGRESS_ENTRY=""
if [ -n "$SUPERVISOR_TOKEN" ]; then
    ADDON_SLUG=$(hostname)
    echo "Addon slug/hostname: ${ADDON_SLUG}"
    INGRESS_ENTRY=$(curl -s -H "Authorization: Bearer ${SUPERVISOR_TOKEN}" \
        "http://supervisor/addons/${ADDON_SLUG}/info" 2>/dev/null | jq -r '.data.ingress_entry // empty')
    # Fallback: try 'self'
    if [ -z "$INGRESS_ENTRY" ]; then
        INGRESS_ENTRY=$(curl -s -H "Authorization: Bearer ${SUPERVISOR_TOKEN}" \
            "http://supervisor/addons/self/info" 2>/dev/null | jq -r '.data.ingress_entry // empty')
    fi
else
    echo "WARNING: SUPERVISOR_TOKEN not set"
fi

echo "Configuring Element Web v1.11.57..."
echo "Homeserver URL: ${HOMESERVER_URL}"
echo "Server name: ${SERVER_NAME}"
echo "Ingress entry: ${INGRESS_ENTRY}"

# Update nginx to proxy to the configured homeserver
sed -i "s|HOMESERVER_PLACEHOLDER|${HOMESERVER_URL}|g" /etc/nginx/http.d/default.conf

# Determine base_url for Element
# If ingress is available, use it so requests go through HA (same-origin)
# Otherwise fall back to direct homeserver URL
if [ -n "$INGRESS_ENTRY" ]; then
    BASE_URL="http://homeassistant.local:8123${INGRESS_ENTRY}"
    echo "Using ingress base_url: ${BASE_URL}"
else
    BASE_URL="${HOMESERVER_URL}"
    echo "Using direct base_url: ${BASE_URL}"
fi

# Write Element config
cat > /opt/element-web/config.json <<EOF
{
    "default_server_config": {
        "m.homeserver": {
            "base_url": "${BASE_URL}",
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
    "show_labs_settings": true,
    "room_directory": {
        "servers": ["${SERVER_NAME}"]
    }
}
EOF

echo "Starting Element Web on port 8765..."
exec nginx -g "daemon off;"
