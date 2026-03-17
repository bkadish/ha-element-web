#!/usr/bin/with-contenv bashio

bashio::log.info "Starting Element Web on port 8765..."
exec nginx -g "daemon off;"
