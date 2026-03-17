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

# Write Element config
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

# Remove any stale well-known files
rm -rf /opt/element-web/.well-known

# Patch index.html:
# 1. Update CSP meta tag to allow 'unsafe-inline' scripts
# 2. Inject fetch override script to dynamically set base_url
# 3. Inject auto-dismiss script for browser warning
python3 << 'PYEOF'
html = open('/opt/element-web/index.html').read()

# Fix CSP meta tag to allow unsafe-inline scripts
html = html.replace(
    "script-src 'self' 'wasm-unsafe-eval'",
    "script-src 'self' 'unsafe-inline' 'wasm-unsafe-eval'"
)

script = """<script>
(function() {
    // Override fetch to dynamically set base_url based on current URL
    var _origFetch = window.fetch;
    window.fetch = function(url, opts) {
        var urlStr = (typeof url === 'string') ? url : (url && url.url ? url.url : '');
        if (urlStr.indexOf('config.json') !== -1 && urlStr.indexOf('config.json.') === -1) {
            return _origFetch.apply(this, arguments).then(function(resp) {
                return resp.text().then(function(text) {
                    try {
                        var config = JSON.parse(text);
                        var ingressMatch = window.location.pathname.match(/\\/api\\/hassio_ingress\\/[^\\/]+/);
                        var baseUrl = ingressMatch
                            ? window.location.origin + ingressMatch[0]
                            : window.location.origin;
                        config.default_server_config['m.homeserver'].base_url = baseUrl;
                        console.log('[Element HA] Set base_url to:', baseUrl);
                        return new Response(JSON.stringify(config), {
                            status: 200,
                            headers: {'Content-Type': 'application/json'}
                        });
                    } catch(e) {
                        console.error('[Element HA] Failed to patch config:', e);
                        return new Response(text, {status: 200, headers: {'Content-Type': 'application/json'}});
                    }
                });
            });
        }
        return _origFetch.apply(this, arguments);
    };
    // Auto-dismiss browser compatibility warning
    var _di = setInterval(function() {
        var btns = document.querySelectorAll('button');
        for (var i = 0; i < btns.length; i++) {
            var t = btns[i].textContent.toLowerCase();
            if (t.indexOf('continue') !== -1 || t.indexOf('dismiss') !== -1 ||
                t.indexOf('accept') !== -1 || t.indexOf('understand') !== -1) {
                btns[i].click();
                clearInterval(_di);
                console.log('[Element HA] Auto-dismissed browser warning');
                break;
            }
        }
    }, 500);
    setTimeout(function() { clearInterval(_di); }, 15000);
})();
</script>"""

# Insert right after <meta charset="utf-8">
html = html.replace('<meta charset="utf-8">', '<meta charset="utf-8">' + script, 1)

open('/opt/element-web/index.html', 'w').write(html)
print('Patched index.html: CSP updated and scripts injected.')
PYEOF

echo "Starting Element Web on port 8765..."
exec nginx -g "daemon off;"
