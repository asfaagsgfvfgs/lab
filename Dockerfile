FROM quay.io/jupyter/minimal-notebook:latest

USER root

# Install nginx + envsubst (to template nginx config) + dumb-init for clean shutdowns
RUN apt-get update \
 && apt-get install -y --no-install-recommends nginx dumb-init gettext-base ca-certificates \
 && rm -rf /var/lib/apt/lists/*

# Cerebrium Dockerfile requirements: WORKDIR, EXPOSE, CMD <!--citation:1-->
WORKDIR /app

# Nginx template + start script
COPY nginx.conf.template /etc/nginx/conf.d/default.conf.template
COPY start.sh /app/start.sh
RUN chmod +x /app/start.sh

# Cerebrium will route traffic to the port you configure in cerebrium.toml
EXPOSE 8192

CMD ["dumb-init", "--", "/app/start.sh"]
