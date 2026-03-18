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

# Get ingress entry from supervisor API
INGRESS_ENTRY=""
if [ -n "$SUPERVISOR_TOKEN" ]; then
    ADDON_SLUG=$(hostname | tr '-' '_')
    INGRESS_ENTRY=$(curl -s -H "Authorization: Bearer ${SUPERVISOR_TOKEN}" \
        "http://supervisor/addons/${ADDON_SLUG}/info" 2>/dev/null | jq -r '.data.ingress_entry // empty')
fi

echo "Configuring FluffyChat v2.4.1..."
echo "Homeserver URL: ${HOMESERVER_URL}"
echo "Server name: ${SERVER_NAME}"
echo "Ingress entry: ${INGRESS_ENTRY}"

# Update nginx to proxy to the configured homeserver
sed -i "s|HOMESERVER_PLACEHOLDER|${HOMESERVER_URL}|g" /etc/nginx/http.d/default.conf

# Update nginx well-known
if [ -n "$INGRESS_ENTRY" ]; then
    sed -i "s|WELL_KNOWN_BASE_URL|${INGRESS_ENTRY}|g" /etc/nginx/http.d/default.conf
else
    sed -i "s|WELL_KNOWN_BASE_URL|/|g" /etc/nginx/http.d/default.conf
fi

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

# Remove static well-known (nginx serves it dynamically now)
rm -rf /opt/fluffychat/.well-known

# Patch index.html using python3 for reliability
if [ -n "$INGRESS_ENTRY" ]; then
    BASE_HREF="${INGRESS_ENTRY}/"
    # Normalize double slashes
    BASE_HREF=$(echo "$BASE_HREF" | sed 's|//|/|g')
else
    BASE_HREF="/"
fi
echo "Setting base href to: ${BASE_HREF}"

python3 << PYEOF
html = open('/opt/fluffychat/index.html').read()

# Fix base href
html = html.replace('<base href="/web/">', '<base href="${BASE_HREF}">')

# Disable service worker (breaks in ingress/iframe context)
html = html.replace(
    '''serviceWorker: {
          serviceWorkerVersion: "4014950489",
        },
      onEntrypointLoaded''',
    'onEntrypointLoaded'
)

open('/opt/fluffychat/index.html', 'w').write(html)
print('Patched index.html: base href and service worker')
PYEOF

echo "Starting FluffyChat on port 8765..."
exec nginx -g "daemon off;"
