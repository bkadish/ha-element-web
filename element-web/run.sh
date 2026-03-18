#!/usr/bin/with-contenv bash

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

echo "Configuring FluffyChat v2.4.1..."
echo "Homeserver URL: ${HOMESERVER_URL}"
echo "Server name: ${SERVER_NAME}"

# Update nginx to proxy to the configured homeserver
sed -i "s|HOMESERVER_PLACEHOLDER|${HOMESERVER_URL}|g" /etc/nginx/http.d/default.conf

# FluffyChat config - leave defaultHomeserver empty so user enters it
# On first login, user should enter their Matrix ID (e.g. @user:servername)
# and FluffyChat will prompt for the homeserver URL
cat > /opt/fluffychat/config.json <<EOF
{
    "applicationName": "FluffyChat",
    "defaultHomeserver": "",
    "renderHtml": true,
    "hideUnknownEvents": true,
    "autoplayImages": true,
    "sendOnEnter": true
}
EOF

# Serve .well-known from our nginx so that if FluffyChat looks up
# the well-known on the current origin, it gets directed to use
# the same origin as the homeserver (our nginx proxy)
mkdir -p /opt/fluffychat/.well-known/matrix
cat > /opt/fluffychat/.well-known/matrix/client <<EOF
{
    "m.homeserver": {
        "base_url": "https://please-enter-url-manually"
    }
}
EOF

echo "Starting FluffyChat on port 8765..."
exec nginx -g "daemon off;"
