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

# Create landing page with cookie debug
mkdir -p /opt/landing
cat > /opt/landing/index.html <<'LANDINGEOF'
<!DOCTYPE html>
<html>
<head>
<meta charset="utf-8">
<title>FluffyChat</title>
<style>
body { background: #1a1a2e; color: white; font-family: sans-serif; padding: 20px; }
a { color: #7dd3fc; }
pre { background: #16213e; padding: 10px; border-radius: 8px; white-space: pre-wrap; word-break: break-all; }
.btn { display: inline-block; padding: 12px 24px; background: #7b2ff7; color: white; text-decoration: none; border-radius: 24px; margin: 8px; cursor: pointer; border: none; font-size: 16px; }
</style>
</head>
<body>
<h2>FluffyChat</h2>
<a class="btn" href="app/">Open FluffyChat</a>
<button class="btn" onclick="testCookie()">Test Cookie</button>
<button class="btn" onclick="testMatrix()">Test Matrix API</button>
<pre id="output">Click a test button...</pre>
<script>
function log(msg) { document.getElementById('output').textContent += '\n' + msg; }
function testCookie() {
  document.getElementById('output').textContent = 'Document cookies: ' + document.cookie;
  fetch('cookie-test').then(r => r.text()).then(t => log('Server sees: ' + t)).catch(e => log('Error: ' + e));
}
function testMatrix() {
  document.getElementById('output').textContent = 'Testing /_matrix/client/versions...';
  fetch('_matrix/client/versions').then(r => {
    log('Status: ' + r.status);
    return r.text();
  }).then(t => log('Response: ' + t.substring(0, 200))).catch(e => log('Error: ' + e));
}
</script>
</body>
</html>
LANDINGEOF

# Remove static well-known and config.json (nginx serves config.json dynamically)
rm -rf /opt/fluffychat/.well-known
rm -f /opt/fluffychat/config.json

echo "Starting FluffyChat on port 8765..."
exec nginx -g "daemon off;"
