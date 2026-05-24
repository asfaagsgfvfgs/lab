FROM python:3.11-slim

ENV DEBIAN_FRONTEND=noninteractive \
    PIP_DISABLE_PIP_VERSION_CHECK=on \
    PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    JUPYTER_ENABLE_LAB=yes

RUN apt-get update \ 
    && apt-get install -y --no-install-recommends build-essential curl git tini \ 
    && apt-get clean \ 
    && rm -rf /var/lib/apt/lists/*

ARG NB_USER=jovyan
ARG NB_UID=1000
ARG NB_GID=100
ENV USER=${NB_USER} \
    HOME=/home/${NB_USER}

RUN groupadd --gid ${NB_GID} ${NB_USER} \ 
    && useradd --no-log-init --create-home --uid ${NB_UID} --gid ${NB_GID} --shell /bin/bash ${NB_USER}

WORKDIR ${HOME}

RUN pip install --no-cache-dir \ 
    jupyterlab \ 
    jupyterlab-git \ 
    jupyterlab-code-formatter \ 
    black isort

RUN mkdir -p /workspace \ 
    && chown -R ${NB_UID}:${NB_GID} /workspace ${HOME}

EXPOSE 8888

USER ${NB_USER}

ENTRYPOINT ["/usr/bin/tini", "--"]
CMD ["jupyter", "lab", "--ip=0.0.0.0", "--port=8888", "--no-browser", "--ServerApp.token=", "--ServerApp.password=", "--ServerApp.allow_origin=*", "--ServerApp.root_dir=/workspace"]
      
