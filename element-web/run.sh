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

# Get ingress entry
INGRESS_ENTRY=""
if [ -n "$SUPERVISOR_TOKEN" ]; then
    ADDON_SLUG=$(hostname | tr '-' '_')
    INGRESS_ENTRY=$(curl -s -H "Authorization: Bearer ${SUPERVISOR_TOKEN}" \
        "http://supervisor/addons/${ADDON_SLUG}/info" 2>/dev/null | jq -r '.data.ingress_entry // empty')
fi

echo "Configuring FluffyChat..."
echo "Homeserver: ${HOMESERVER_URL}"
echo "Ingress: ${INGRESS_ENTRY}"

# Update nginx placeholders
sed -i "s|HOMESERVER_PLACEHOLDER|${HOMESERVER_URL}|g" /etc/nginx/http.d/default.conf
if [ -n "$INGRESS_ENTRY" ]; then
    sed -i "s|WELL_KNOWN_BASE_URL|${INGRESS_ENTRY}/app|g" /etc/nginx/http.d/default.conf
else
    sed -i "s|WELL_KNOWN_BASE_URL|/app|g" /etc/nginx/http.d/default.conf
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

# Fix base href for FluffyChat
if [ -n "$INGRESS_ENTRY" ]; then
    BASE_HREF="${INGRESS_ENTRY}/app/"
else
    BASE_HREF="/app/"
fi
sed -i "s|<base href=\"/web/\">|<base href=\"${BASE_HREF}\">|" /opt/fluffychat/index.html

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

# Create landing page (shown in ingress iframe)
mkdir -p /opt/landing
APP_URL="app/"
cat > /opt/landing/index.html <<EOF
<!DOCTYPE html>
<html>
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>FluffyChat</title>
<style>
body {
  display: flex;
  align-items: center;
  justify-content: center;
  height: 100vh;
  margin: 0;
  background: #1a1a2e;
  color: white;
  font-family: -apple-system, BlinkMacSystemFont, sans-serif;
}
.card {
  text-align: center;
  padding: 40px;
}
.icon { font-size: 64px; margin-bottom: 16px; }
h2 { font-weight: 300; margin: 0 0 8px; }
p { opacity: 0.7; font-size: 14px; margin: 0 0 24px; }
.btn {
  display: inline-block;
  padding: 14px 36px;
  background: #7b2ff7;
  color: white;
  text-decoration: none;
  border-radius: 24px;
  font-size: 16px;
  transition: background 0.2s;
}
.btn:hover { background: #6a1fe0; }
</style>
</head>
<body>
<div class="card">
  <div class="icon">&#x1F4AC;</div>
  <h2>FluffyChat</h2>
  <p>Matrix chat client</p>
  <a class="btn" href="${APP_URL}" target="_blank" rel="noopener">Open FluffyChat</a>
</div>
</body>
</html>
EOF

# Remove static well-known
rm -rf /opt/fluffychat/.well-known

echo "Starting FluffyChat on port 8765..."
exec nginx -g "daemon off;"
