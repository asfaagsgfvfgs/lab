FROM python:3.12-slim

# Set the working directory in the container
WORKDIR /app

# Install system dependencies (added curl and gnupg for ngrok installation)
RUN apt-get update && apt-get install -y \
    build-essential \
    libcurl4-openssl-dev \
    libssl-dev \
    libffi-dev \
    curl \
    gnupg \
    && apt-get clean

# Install Ngrok
RUN curl -s https://ngrok-agent.s3.amazonaws.com/ngrok.asc \
    | tee /etc/apt/keyrings/ngrok.asc >/dev/null \
    && echo "deb [signed-by=/etc/apt/keyrings/ngrok.asc] https://ngrok-agent.s3.amazonaws.com buster main" \
    | tee /etc/apt/sources.list.d/ngrok.list \
    && apt-get update && apt-get install -y ngrok

# Install Jupyter Lab and common data science packages
RUN pip install --no-cache-dir \
    jupyterlab \
    numpy \
    pandas \
    matplotlib \
    scikit-learn \
    seaborn \
    scipy \
    plotly \
    statsmodels \
    && pip install --upgrade pip

# Expose Jupyter Lab's default port
EXPOSE 8888

# Set an environment variable for the Ngrok Auth Token
ENV NGROK_AUTHTOKEN="3DulmdV0HaKMzfui8UenLjMyndG_2U451LoLF2TtHQG2Xydb9"

# Start Jupyter in the background with the token set to '123', wait 3 seconds, authenticate ngrok, and start the tunnel
CMD jupyter lab --ip='0.0.0.0' --port=8888 --no-browser --allow-root --ServerApp.token='123' & \
    sleep 3 && \
    if [ -n "$NGROK_AUTHTOKEN" ]; then ngrok config add-authtoken $NGROK_AUTHTOKEN; fi && \
    ngrok http 8888 --log=stdout
