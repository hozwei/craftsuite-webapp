set -eu
set -f
origins=${CRAFTSUITE_ALLOWED_ORIGINS:-}
if printf '%s' "$origins" | grep -q '[^]a-zA-Z0-9.:/ [-]'; then
  echo "craft-web: CRAFTSUITE_ALLOWED_ORIGINS takes origins such as https://cloud.example.com, separated by spaces" >&2
  exit 1
fi
# shellcheck disable=SC2086,SC2116 # split on purpose (set -f): one space between origins
origins=$(echo $origins)
for o in $origins; do
  if ! printf '%s\n' "$o" | grep -Eiqx '(https://([a-z0-9-]+\.)*[a-z0-9-]+|https://\[[0-9a-f:.]+\]|http://(localhost|127\.[0-9]+\.[0-9]+\.[0-9]+|\[::1\]))(:[0-9]{1,5})?'; then
    echo "craft-web: '$o' in CRAFTSUITE_ALLOWED_ORIGINS is not an origin such as https://cloud.example.com" >&2
    exit 1
  fi
done
[ -n "$origins" ] || origins="'none'"
cat > /tmp/nginx.conf <<'EOF'
worker_processes 2;
pid /tmp/nginx.pid;
error_log /dev/stderr warn;
events {
  worker_connections 512;
}
http {
  include /etc/nginx/mime.types;
  types {
    application/javascript mjs;
    font/ttf ttf;
    font/otf otf;
    application/manifest+json webmanifest;
  }
  default_type application/octet-stream;
  charset utf-8;
  client_body_temp_path /tmp/client_temp;
  proxy_temp_path /tmp/proxy_temp;
  fastcgi_temp_path /tmp/fastcgi_temp;
  uwsgi_temp_path /tmp/uwsgi_temp;
  scgi_temp_path /tmp/scgi_temp;
  access_log off;
  sendfile on;
  server_tokens off;
  absolute_redirect off;
  resolver 127.0.0.11 valid=10s ipv6=off;
  gzip_static on;
  gzip on;
  gzip_vary on;
  gzip_proxied any;
  gzip_comp_level 5;
  gzip_types text/css text/plain application/javascript application/json application/manifest+json application/wasm image/svg+xml font/ttf font/otf;

  # A year only for names with Trunk's content hash (app-web-9fbc20856b2df0f8_bg.wasm, up to 16
  # hex digits); names that stay the same across releases (worker.js, sw.js, ...) revalidate.
  map "$status:$uri" $craft_cache_control {
    default "no-cache";
    ~^\d+:/oauth2/ "";
    ~^\d+:/[^/]+/craftsuite-layer/ "no-cache";
    "~^(?:200|206|304):.*-[0-9a-f]{8,16}(?:_bg)?\.(?:js|mjs|wasm)$" "private, max-age=31536000, immutable";
  }

  map $request_uri $craft_return_to {
    default $request_uri;
    ~^/oauth2/ "";
  }

  server {
    listen 8080;
    root /srv/data/www;
    index index.html;
    set $gate http://craft-gate:4180;

    add_header Content-Security-Policy "frame-ancestors @FRAME_ANCESTORS@" always;
    add_header X-Content-Type-Options "nosniff" always;
    add_header Cache-Control $craft_cache_control always;

    auth_request /oauth2/auth;
    error_page 401 = /oauth2/sign_in;

    location = /oauth2/auth {
      internal;
      auth_request off;
      proxy_pass $gate;
      proxy_pass_request_body off;
      proxy_set_header Content-Length "";
      proxy_set_header Host $host;
      proxy_set_header X-Forwarded-Uri $request_uri;
    }

    location /oauth2/ {
      auth_request off;
      proxy_pass $gate;
      proxy_set_header Host $host;
      proxy_set_header X-Real-IP $remote_addr;
      proxy_set_header X-Auth-Request-Redirect $craft_return_to;
      proxy_hide_header X-Content-Type-Options;
    }

    location = /healthz {
      auth_request off;
      default_type text/plain;
      return 200 "ok\n";
    }

    location ^~ /releases/ {
      return 404;
    }

    location ~ /\. {
      return 404;
    }
  }
}
EOF
sed -i "s#@FRAME_ANCESTORS@#$origins#" /tmp/nginx.conf
exec nginx -e stderr -c /tmp/nginx.conf -g 'daemon off;'
