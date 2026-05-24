FROM python:3.12-slim

# Set the working directory in the container
WORKDIR /app

# Install system dependencies for data science packages
RUN apt-get update && apt-get install -y \
    build-essential \
    libcurl4-openssl-dev \
    libssl-dev \
    libffi-dev \
    && apt-get clean

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

# Set the default command to launch Jupyter Lab
CMD ["jupyter", "lab", "--ip='*'", "--port=8888", "--no-browser", "--allow-root"]
