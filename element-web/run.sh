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

# Inject iframe detection script right after <head>
# If in iframe: show "Open in new tab" button
# If in new tab: load FluffyChat normally and set homeserver base_url dynamically
iframe_script = """
<script>
(function() {
  // Detect if we're in an iframe
  if (window.self !== window.top) {
    // We're in an iframe (HA sidebar) - show redirect page
    document.addEventListener('DOMContentLoaded', function() {
      // Stop Flutter from loading
      document.body.innerHTML = '';
      document.body.style.cssText = 'display:flex;align-items:center;justify-content:center;height:100vh;margin:0;background:#1a1a2e;color:white;font-family:sans-serif;flex-direction:column;';

      var container = document.createElement('div');
      container.style.cssText = 'text-align:center;padding:20px;';

      var icon = document.createElement('div');
      icon.style.cssText = 'font-size:64px;margin-bottom:20px;';
      icon.textContent = '💬';

      var title = document.createElement('h2');
      title.style.cssText = 'margin:0 0 10px 0;font-weight:300;';
      title.textContent = 'FluffyChat';

      var subtitle = document.createElement('p');
      subtitle.style.cssText = 'margin:0 0 20px 0;opacity:0.7;font-size:14px;';
      subtitle.textContent = 'Matrix chat client';

      var btn = document.createElement('a');
      btn.href = window.location.href;
      btn.target = '_blank';
      btn.rel = 'noopener';
      btn.style.cssText = 'display:inline-block;padding:12px 32px;background:#7b2ff7;color:white;text-decoration:none;border-radius:24px;font-size:16px;cursor:pointer;';
      btn.textContent = 'Open FluffyChat';

      container.appendChild(icon);
      container.appendChild(title);
      container.appendChild(subtitle);
      container.appendChild(btn);
      document.body.appendChild(container);
    });
    return; // Don't execute the rest of this script
  }

  // We're in a new tab - override config.json to set base_url dynamically
  var _origFetch = window.fetch;
  window.fetch = function(url, opts) {
    var urlStr = (typeof url === 'string') ? url : '';
    if (urlStr.indexOf('config.json') !== -1) {
      return _origFetch.apply(this, arguments).then(function(resp) {
        return resp.text().then(function(text) {
          try {
            var config = JSON.parse(text);
            // Set base_url to current origin + ingress path
            var path = window.location.pathname.replace(/\\/$/, '');
            config.defaultHomeserver = window.location.origin + path;
            return new Response(JSON.stringify(config), {
              status: 200,
              headers: {'Content-Type': 'application/json'}
            });
          } catch(e) {
            return new Response(text, {status: 200, headers: {'Content-Type': 'application/json'}});
          }
        });
      });
    }
    return _origFetch.apply(this, arguments);
  };
})();
</script>
"""

html = html.replace('<head>\n', '<head>\n' + iframe_script)
# Also try without newline
if iframe_script not in html:
    html = html.replace('<head>', '<head>' + iframe_script)

open('/opt/fluffychat/index.html', 'w').write(html)
print('Patched index.html: base href, service worker, iframe detection, dynamic homeserver')
PYEOF

echo "Starting FluffyChat on port 8765..."
exec nginx -g "daemon off;"
