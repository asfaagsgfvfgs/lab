FROM python:3.12-bookworm

RUN apt-get update \
 && apt-get install -y --no-install-recommends dumb-init ca-certificates \
 && rm -rf /var/lib/apt/lists/*

WORKDIR /workspace

RUN pip install --no-cache-dir --upgrade pip \
 && pip install --no-cache-dir jupyterlab

EXPOSE 8192

ENV NOTEBOOK_DIR=/persistent-storage/notebooks
ENV JUPYTER_PORT=8192

CMD ["dumb-init", "--", "sh", "-lc", "\
  mkdir -p \"$NOTEBOOK_DIR\"; \
  BASE_URL=\"/\"; \
  if [ -n \"${PROJECT_ID:-}\" ] && [ -n \"${APP_NAME:-}\" ]; then \
    BASE_URL=\"/v4/${PROJECT_ID}/${APP_NAME}/\"; \
  fi; \
  echo \"Starting JupyterLab on :${JUPYTER_PORT} with base_url=${BASE_URL}\"; \
  jupyter lab \
    --ServerApp.ip=0.0.0.0 \
    --ServerApp.port=${JUPYTER_PORT} \
    --ServerApp.root_dir=${NOTEBOOK_DIR} \
    --ServerApp.base_url=${BASE_URL} \
    --ServerApp.allow_remote_access=True \
    --ServerApp.trust_xheaders=True \
    --ServerApp.allow_root=True \
    --no-browser \
"]
