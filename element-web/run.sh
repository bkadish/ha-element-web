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

echo "Configuring Element Web..."
echo "Homeserver URL: ${HOMESERVER_URL}"
echo "Server name: ${SERVER_NAME}"

# Update nginx to proxy to the configured homeserver
sed -i "s|HOMESERVER_PLACEHOLDER|${HOMESERVER_URL}|g" /etc/nginx/http.d/default.conf

# Write Element config (base_url is overridden dynamically by the injected script)
cat > /opt/element-web/config.json <<EOF
{
    "default_server_config": {
        "m.homeserver": {
            "base_url": "${HOMESERVER_URL}",
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
    "features": {
        "feature_dehydration": true
    },
    "show_labs_settings": true,
    "room_directory": {
        "servers": ["${SERVER_NAME}"]
    }
}
EOF

# Inject script into Element's index.html that:
# 1. Dynamically sets the correct base_url for both direct and ingress access
# 2. Auto-dismisses the unsupported browser warning
read -r -d '' INJECT_SCRIPT << 'SCRIPTEOF'
<script>
// Override config.json fetch to set base_url dynamically
var _origFetch = window.fetch;
window.fetch = function(url, opts) {
    if (typeof url === "string" && url.endsWith("/config.json")) {
        return _origFetch.apply(this, arguments).then(function(resp) {
            return resp.json().then(function(config) {
                var ingressMatch = window.location.pathname.match(/\/api\/hassio_ingress\/[^\/]+/);
                var baseUrl = ingressMatch
                    ? window.location.origin + ingressMatch[0]
                    : window.location.origin;
                config.default_server_config["m.homeserver"].base_url = baseUrl;
                return new Response(JSON.stringify(config), {
                    status: 200,
                    headers: {"Content-Type": "application/json"}
                });
            });
        });
    }
    return _origFetch.apply(this, arguments);
};
// Auto-dismiss browser compatibility warning after short delay
var _dismissInterval = setInterval(function() {
    var btns = document.querySelectorAll("button");
    for (var i = 0; i < btns.length; i++) {
        var t = btns[i].textContent.toLowerCase();
        if (t.indexOf("continue") !== -1 || t.indexOf("dismiss") !== -1 || t.indexOf("accept") !== -1 || t.indexOf("understand") !== -1) {
            btns[i].click();
            clearInterval(_dismissInterval);
            break;
        }
    }
}, 500);
setTimeout(function() { clearInterval(_dismissInterval); }, 15000);
</script>
SCRIPTEOF

# Use a temp file approach to avoid sed escaping issues
{
    head -n -1 /opt/element-web/index.html | sed 's|</head>||'
    echo "${INJECT_SCRIPT}"
    echo "</head>"
    tail -n 1 /opt/element-web/index.html
} > /tmp/index_patched.html
# Only use patched version if it looks valid
if grep -q "matrixchat" /tmp/index_patched.html; then
    cp /tmp/index_patched.html /opt/element-web/index.html
    echo "Injected dynamic config and auto-dismiss scripts."
else
    echo "WARNING: Failed to patch index.html, using default."
fi

echo "Starting Element Web on port 8765..."
exec nginx -g "daemon off;"
