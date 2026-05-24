# Cerebrium custom Dockerfiles need: WORKDIR, EXPOSE, and a CMD that starts your server. <!--citation:1-->
FROM python:3.12-bookworm

# dumb-init helps with signal handling (SIGTERM) so the process shuts down cleanly.
RUN apt-get update \
 && apt-get install -y --no-install-recommends dumb-init ca-certificates \
 && rm -rf /var/lib/apt/lists/* \
 && update-ca-certificates

WORKDIR /app

# (Optional) if you have a requirements.txt, keep this layer for caching
COPY requirements.txt /app/requirements.txt
RUN pip install --no-cache-dir -r /app/requirements.txt

# Install JupyterLab (add extra libs you want here, e.g. pandas, numpy, etc.)
RUN pip install --no-cache-dir jupyterlab ipykernel

# If you want your repo files in the image (optional)
COPY . /app

# Cerebrium will route traffic to the port you set in cerebrium.toml; expose the same port here. <!--citation:1-->
EXPOSE 8192

# Notes:
# - We store notebooks in /persistent-storage so they persist across deployments. <!--citation:2-->
# - For browser access, you’ll typically set `disable_auth=true` in cerebrium.toml (Cerebrium auth is token-based by default). <!--citation:3-->
# - Set JUPYTER_TOKEN as a Cerebrium Secret if you want a stable login token (recommended).
CMD ["dumb-init", "--", "sh", "-lc", "\
  mkdir -p /persistent-storage/notebooks; \
  EXTRA_ARGS=''; \
  if [ -n \"${JUPYTER_TOKEN:-}\" ]; then EXTRA_ARGS=\"$EXTRA_ARGS --ServerApp.token=${JUPYTER_TOKEN}\"; fi; \
  jupyter lab \
    --ServerApp.ip=0.0.0.0 \
    --ServerApp.port=8192 \
    --ServerApp.root_dir=/persistent-storage/notebooks \
    --ServerApp.allow_remote_access=True \
    --ServerApp.trust_xheaders=True \
    --no-browser \
    $EXTRA_ARGS \
"]
