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

# FluffyChat config - leave defaultHomeserver empty
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

# Disable service worker only (no fetch override - Flutter doesn't use window.fetch for config)
python3 -c "
html = open('/opt/fluffychat/index.html').read()
html = html.replace(
    'serviceWorker: {\n          serviceWorkerVersion: \"4014950489\",\n        },\n      onEntrypointLoaded',
    'onEntrypointLoaded'
)
open('/opt/fluffychat/index.html', 'w').write(html)
print('Disabled service worker')
"

# Create landing page - detects current URL and shows instructions
# The ingress path is the same regardless of LAN or Nabu Casa
mkdir -p /opt/landing
cat > /opt/landing/index.html <<'LANDINGEOF'
<!DOCTYPE html>
<html>
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>FluffyChat</title>
<style>
* { box-sizing: border-box; }
body {
  display: flex; align-items: center; justify-content: center;
  min-height: 100vh; margin: 0; padding: 16px;
  background: #1a1a2e; color: white;
  font-family: -apple-system, BlinkMacSystemFont, sans-serif;
}
.card { text-align: center; max-width: 480px; width: 100%; }
h2 { font-weight: 300; margin: 0 0 24px; font-size: 24px; }
.url-box {
  background: #16213e; border-radius: 8px; padding: 12px;
  margin: 16px 0; word-break: break-all; font-family: monospace;
  font-size: 13px; color: #7dd3fc; cursor: pointer;
  border: 1px solid #334155;
}
.url-box:hover { border-color: #7b2ff7; }
.btn {
  display: inline-block; padding: 14px 36px; margin: 8px;
  background: #7b2ff7; color: white; text-decoration: none;
  border-radius: 24px; font-size: 16px;
}
.btn:hover { background: #6a1fe0; }
.step { text-align: left; margin: 20px 0; line-height: 1.8; }
.step b { color: #7dd3fc; }
.copied { color: #4ade80; font-size: 14px; margin-top: 4px; }
.note { opacity: 0.5; font-size: 12px; margin-top: 16px; }
</style>
</head>
<body>
<div class="card">
  <h2>&#x1F4AC; FluffyChat</h2>
  <a class="btn" href="app/" id="openBtn">Open FluffyChat</a>
  <div class="step">
    <p>On the FluffyChat login screen, enter this as your homeserver:</p>
    <div class="url-box" id="urlBox" onclick="copyUrl()"></div>
    <div class="copied" id="copiedMsg" style="display:none">Copied!</div>
    <p class="note">Tap the URL to copy it. You only need to enter this once.</p>
  </div>
</div>
<script>
  // Detect the correct homeserver URL based on current page location
  var path = window.location.pathname.replace(/\/$/, '');
  var hsUrl = window.location.origin + path;
  document.getElementById('urlBox').textContent = hsUrl;

  function copyUrl() {
    navigator.clipboard.writeText(document.getElementById('urlBox').textContent).then(function() {
      var msg = document.getElementById('copiedMsg');
      msg.style.display = 'block';
      setTimeout(function() { msg.style.display = 'none'; }, 2000);
    });
  }
</script>
</body>
</html>
LANDINGEOF

# Remove static well-known
rm -rf /opt/fluffychat/.well-known

echo "Starting FluffyChat on port 8765..."
exec nginx -g "daemon off;"
