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

# Remove static well-known (nginx serves it dynamically)
rm -rf /opt/fluffychat/.well-known

# Patch index.html
if [ -n "$INGRESS_ENTRY" ]; then
    BASE_HREF="${INGRESS_ENTRY}/"
    BASE_HREF=$(echo "$BASE_HREF" | sed 's|//|/|g')
else
    BASE_HREF="/"
fi
echo "Setting base href to: ${BASE_HREF}"

export BASE_HREF INGRESS_ENTRY

python3 << PYEOF
base_href = "${BASE_HREF}"
ingress_entry = "${INGRESS_ENTRY}"

html = open('/opt/fluffychat/index.html').read()

# Fix base href
html = html.replace('<base href="/web/">', '<base href="' + base_href + '">')

# Disable service worker (breaks in various contexts)
html = html.replace(
    """serviceWorker: {
          serviceWorkerVersion: "4014950489",
        },
      onEntrypointLoaded""",
    "onEntrypointLoaded"
)

# Inject iframe detection using document.write() - runs synchronously
# and completely replaces the page before Flutter can load
iframe_script = '''<script>
if (window.self !== window.top) {
  document.write('<!DOCTYPE html><html><head><meta charset="utf-8"><style>body{display:flex;align-items:center;justify-content:center;height:100vh;margin:0;background:#1a1a2e;color:white;font-family:sans-serif}a{display:inline-block;padding:12px 32px;background:#7b2ff7;color:white;text-decoration:none;border-radius:24px;font-size:16px}.c{text-align:center}</style></head><body><div class="c"><div style="font-size:64px;margin-bottom:20px">&#x1F4AC;</div><h2 style="font-weight:300">FluffyChat</h2><p style="opacity:0.7;font-size:14px">Matrix chat client</p><a href="' + window.location.href + '" target="_blank" rel="noopener">Open FluffyChat</a></div></body></html>');
  document.close();
} else {
  // In new tab - override config fetch for dynamic homeserver
  var _of = window.fetch;
  window.fetch = function(u, o) {
    if (typeof u === "string" && u.indexOf("config.json") !== -1) {
      return _of.apply(this, arguments).then(function(r) {
        return r.text().then(function(t) {
          try {
            var c = JSON.parse(t);
            c.defaultHomeserver = window.location.origin + window.location.pathname.replace(/\\\\/$/, "");
            return new Response(JSON.stringify(c), {status:200, headers:{"Content-Type":"application/json"}});
          } catch(e) { return new Response(t, {status:200}); }
        });
      });
    }
    return _of.apply(this, arguments);
  };
}
</script>'''

html = html.replace('<head>', '<head>' + iframe_script, 1)

open('/opt/fluffychat/index.html', 'w').write(html)
print('Patched index.html: base href, service worker, iframe detection, dynamic homeserver')
PYEOF

echo "Starting FluffyChat on port 8765..."
exec nginx -g "daemon off;"
