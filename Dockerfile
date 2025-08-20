# Use official Jupyter base image
FROM jupyter/base-notebook:latest

# Switch to root for system installations
USER root

# Install system dependencies
RUN apt-get update && apt-get install -y \
    curl \
    unzip \
    && rm -rf /var/lib/apt/lists/*

# Install Deno (latest stable)
ENV DENO_INSTALL=/usr/local
RUN curl -fsSL https://deno.land/install.sh | sh && \
    ln -s /usr/local/bin/deno /usr/bin/deno

# Install Python packages
RUN pip install --no-cache-dir requests

# Switch back to jovyan user
USER ${NB_UID}

# Install Deno Jupyter kernel
RUN deno jupyter --force --install 2>/dev/null || \
    deno jupyter --unstable --force --install 2>/dev/null || true

# Create directories
RUN mkdir -p /home/${NB_USER}/.jupyter

# Create a Python script that generates the Jupyter config
RUN cat > /home/${NB_USER}/configure_jupyter.py << 'EOF'
import os

config_template = """
c = get_config()
c.ServerApp.token = '{token}'
c.ServerApp.password = ''
c.ServerApp.ip = '0.0.0.0'
c.ServerApp.port = 8888
c.ServerApp.open_browser = False
c.ServerApp.allow_root = True
c.ServerApp.base_url = '/'
c.ServerApp.allow_origin = '*'
c.ServerApp.allow_credentials = True
c.ServerApp.disable_check_xsrf = True
c.MultiKernelManager.default_kernel_name = 'deno'
c.MappingKernelManager.cull_idle_timeout = 0
c.MappingKernelManager.cull_interval = 0
c.MappingKernelManager.cull_connected = False
c.MappingKernelManager.cull_busy = False
"""

token = os.environ.get('JUPYTER_TOKEN', 'default-token-please-change')
config_content = config_template.format(token=token)

with open('/home/jovyan/.jupyter/jupyter_server_config.py', 'w') as f:
    f.write(config_content)

print(f"Jupyter configured with token: {token[:10]}...")
EOF

# Create a simple startup script
RUN cat > /home/${NB_USER}/start.sh << 'EOF'
#!/bin/bash
# Configure Jupyter
python /home/jovyan/configure_jupyter.py

# Ensure Deno kernel is installed
deno jupyter --force --install 2>/dev/null || true

# Start Jupyter with a background task to create a kernel
(
    sleep 10
    curl -X POST "http://localhost:8888/api/kernels?token=${JUPYTER_TOKEN}" \
         -H "Content-Type: application/json" \
         -d '{"name": "deno"}' 2>/dev/null || true
) &

# Start Jupyter
exec start-notebook.sh "$@"
EOF

RUN chmod +x /home/${NB_USER}/start.sh

# Set working directory
WORKDIR /home/${NB_USER}/work

# Expose port
EXPOSE 8888

# Set environment variables
ENV DENO_DIR=/home/${NB_USER}/.deno \
    DENO_INSTALL_ROOT=/home/${NB_USER}/.deno/bin

# Use our startup script
ENTRYPOINT ["/home/jovyan/start.sh"]