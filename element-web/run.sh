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

# Update nginx - replace all placeholders
sed -i "s|HOMESERVER_PLACEHOLDER|${HOMESERVER_URL}|g" /etc/nginx/http.d/default.conf
sed -i "s|INGRESS_PATH_PLACEHOLDER|${INGRESS_ENTRY}|g" /etc/nginx/http.d/default.conf

# Fix base href for FluffyChat
if [ -n "$INGRESS_ENTRY" ]; then
    BASE_HREF="${INGRESS_ENTRY}/app/"
else
    BASE_HREF="/app/"
fi
sed -i "s|<base href=\"/web/\">|<base href=\"${BASE_HREF}\">|" /opt/fluffychat/index.html

# Disable service worker and inject homeserver auto-detection
python3 << 'PYEOF'
html = open('/opt/fluffychat/index.html').read()

# Disable service worker
html = html.replace(
    'serviceWorker: {\n          serviceWorkerVersion: "4014950489",\n        },\n      onEntrypointLoaded',
    'onEntrypointLoaded'
)

# Inject fetch override to auto-set homeserver from current URL
# This catches FluffyChat's Dart HTTP requests for config.json
script = '''<script>
(function() {
  var _of = window.fetch;
  window.fetch = function(u, o) {
    var s = (typeof u === "string") ? u : (u && u.url ? u.url : "");
    if (s.indexOf("config.json") !== -1) {
      return _of.apply(this, arguments).then(function(r) {
        return r.text().then(function(t) {
          try {
            var c = JSON.parse(t);
            var p = window.location.pathname.replace(/\\/app\\/?.*/,"");
            c.defaultHomeserver = window.location.origin + p;
            return new Response(JSON.stringify(c), {status:200, headers:{"Content-Type":"application/json"}});
          } catch(e) { return new Response(t, {status:200}); }
        });
      });
    }
    return _of.apply(this, arguments);
  };
})();
</script>'''

html = html.replace('<head>', '<head>' + script, 1)

open('/opt/fluffychat/index.html', 'w').write(html)
print('Patched: service worker disabled, fetch override injected')
PYEOF

# Create landing page - auto-redirects to FluffyChat
mkdir -p /opt/landing
cat > /opt/landing/index.html <<'LANDINGEOF'
<!DOCTYPE html>
<html>
<head>
<meta charset="utf-8">
<meta http-equiv="refresh" content="0;url=app/">
<title>Loading FluffyChat...</title>
</head>
<body>
<p>Loading FluffyChat... <a href="app/">Click here if not redirected</a></p>
</body>
</html>
LANDINGEOF

# Remove static well-known and config.json (nginx serves config.json dynamically)
rm -rf /opt/fluffychat/.well-known
rm -f /opt/fluffychat/config.json

echo "Starting FluffyChat on port 8765..."
exec nginx -g "daemon off;"
