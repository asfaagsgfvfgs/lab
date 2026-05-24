#!/usr/bin/env bash
set -euo pipefail

# Cerebrium sets these env vars for your app (used in their Gradio example too)
PROJECT_ID="${PROJECT_ID:-}"
APP_NAME="${APP_NAME:-}"

# External URL prefix your users will hit:
#   https://api.aws.us-east-1.cerebrium.ai/v4/<PROJECT_ID>/<APP_NAME>/
PREFIX="/v4/${PROJECT_ID}/${APP_NAME}"

echo "PROJECT_ID=${PROJECT_ID}"
echo "APP_NAME=${APP_NAME}"
echo "PREFIX=${PREFIX}"

# Build nginx config from template
export PREFIX
envsubst '${PREFIX}' < /etc/nginx/conf.d/default.conf.template > /etc/nginx/conf.d/default.conf

# Notebooks persisted on Cerebrium's persistent volume <!--citation:3-->
mkdir -p /persistent-storage/notebooks

# Jupyter security:
# - Recommended: set JUPYTER_TOKEN as a Cerebrium Secret (env var)
# - If you don't set it, Jupyter will generate a random token (check logs).
TOKEN_ARG=()
if [[ -n "${JUPYTER_TOKEN:-}" ]]; then
  TOKEN_ARG=( "--ServerApp.token=${JUPYTER_TOKEN}" )
fi

# Run Jupyter on localhost, nginx is the public-facing server
# Extra flags help when running behind proxies.
jupyter lab \
  --ServerApp.ip=127.0.0.1 \
  --ServerApp.port=8888 \
  --ServerApp.root_dir=/persistent-storage/notebooks \
  --ServerApp.allow_remote_access=True \
  --ServerApp.trust_xheaders=True \
  --ServerApp.allow_root=True \
  --ServerApp.disable_check_xsrf=True \
  --ServerApp.allow_origin="*" \
  --no-browser \
  "${TOKEN_ARG[@]}" &

# Run nginx in foreground
nginx -g 'daemon off;'
