#!/usr/bin/with-contenv bash

OPTIONS_FILE="/data/options.json"

if [ -f "$OPTIONS_FILE" ]; then
    HOMESERVER_URL=$(jq -r '.homeserver_url' "$OPTIONS_FILE")
    SERVER_NAME=$(jq -r '.server_name' "$OPTIONS_FILE")
else
    echo "ERROR: No options.json found."
    exit 1
fi

if [ -z "$HOMESERVER_URL" ] || [ "$HOMESERVER_URL" = "null" ]; then
    echo "ERROR: homeserver_url not configured."
    sleep infinity
fi

echo "Configuring FluffyChat..."
echo "Homeserver: ${HOMESERVER_URL}"
echo "Server name: ${SERVER_NAME}"

# Update nginx proxy
sed -i "s|HOMESERVER_PLACEHOLDER|${HOMESERVER_URL}|g" /etc/nginx/http.d/default.conf

# FluffyChat config
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

# Fix base href
sed -i 's|<base href="/web/">|<base href="/">|' /opt/fluffychat/index.html

# Disable service worker
python3 -c "
html = open('/opt/fluffychat/index.html').read()
html = html.replace(
    'serviceWorker: {\n          serviceWorkerVersion: \"4014950489\",\n        },\n      onEntrypointLoaded',
    'onEntrypointLoaded'
)
open('/opt/fluffychat/index.html', 'w').write(html)
print('Disabled service worker')
"

rm -rf /opt/fluffychat/.well-known

echo "Starting FluffyChat on port 8765..."
exec nginx -g "daemon off;"
