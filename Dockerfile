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
RUN curl -fsSL https://deno.land/install.sh | sh

# Make deno available in PATH for all users
RUN ln -s /usr/local/bin/deno /usr/bin/deno

# Install Python packages for kernel management
RUN pip install --no-cache-dir requests

# Switch back to jovyan user
USER ${NB_UID}

# Pre-create jupyter directories to avoid permission issues
RUN mkdir -p /home/${NB_USER}/.jupyter \
    /home/${NB_USER}/.local/share/jupyter/kernels \
    /home/${NB_USER}/.jupyter/lab/user-settings/@jupyterlab/notebook-extension

# Install Deno Jupyter kernel with force flag
RUN deno jupyter --force --install 2>/dev/null || \
    deno jupyter --unstable --force --install 2>/dev/null || true

# Configure JupyterLab to use Deno kernel by default
RUN echo '{"kernelPreference": {"autoStartDefault": "deno"}}' > \
    /home/${NB_USER}/.jupyter/lab/user-settings/@jupyterlab/notebook-extension/tracker.jupyterlab-settings

# Create the entrypoint script directly in the Dockerfile to avoid line ending issues
RUN cat > /usr/local/bin/docker-entrypoint.sh << 'SCRIPT_END' && \
    chmod +x /usr/local/bin/docker-entrypoint.sh
#!/bin/bash
set -e

# Configure Jupyter with the provided token
if [ -n "$JUPYTER_TOKEN" ]; then
    echo "Configuring Jupyter with authentication token..."
    
    # Create jupyter config directory if it doesn't exist
    mkdir -p /home/jovyan/.jupyter
    
    # Generate config non-interactively (skip if exists)
    if [ ! -f /home/jovyan/.jupyter/jupyter_notebook_config.py ]; then
        jupyter notebook --generate-config -y 2>/dev/null || true
    fi
    
    # Create or overwrite the config file with our settings
    cat > /home/jovyan/.jupyter/jupyter_server_config.py << EOF
c = get_config()

# Authentication
c.ServerApp.token = '${JUPYTER_TOKEN}'
c.ServerApp.password = ''

# Network settings
c.ServerApp.ip = '0.0.0.0'
c.ServerApp.port = 8888
c.ServerApp.open_browser = False
c.ServerApp.allow_root = True
c.ServerApp.base_url = '/'

# CORS and API settings for Open WebUI
c.ServerApp.allow_origin = '*'
c.ServerApp.allow_credentials = True
c.ServerApp.disable_check_xsrf = True

# Kernel settings
c.MultiKernelManager.default_kernel_name = 'deno'
c.KernelManager.autorestart = True

# Disable kernel culling to keep kernels alive
c.MappingKernelManager.cull_idle_timeout = 0
c.MappingKernelManager.cull_interval = 0
c.MappingKernelManager.cull_connected = False
c.MappingKernelManager.cull_busy = False
EOF

    echo "Jupyter configuration complete."
fi

# Install/reinstall Deno kernel with proper flags for Deno 2.0+
echo "Installing Deno Jupyter kernel..."
if deno --version | grep -q "^deno 2\."; then
    # Deno 2.0+ uses granular unstable flags
    deno jupyter --unstable-kv --unstable-broadcast-channel --force --install 2>/dev/null || \
    deno jupyter --force --install 2>/dev/null || true
else
    # Older Deno versions
    deno jupyter --unstable --force --install 2>/dev/null || true
fi

# Create a Python script to start a kernel after Jupyter starts
cat > /home/jovyan/start-kernel.py << 'PYTHON_SCRIPT'
import time
import requests
import json
import os
import sys

token = os.environ.get('JUPYTER_TOKEN', '')
base_url = 'http://localhost:8888'

print("Waiting for Jupyter to be ready...")
# Wait for Jupyter to be ready
for i in range(30):
    try:
        response = requests.get(f'{base_url}/api', params={'token': token})
        if response.status_code == 200:
            print("Jupyter is ready!")
            break
    except:
        pass
    time.sleep(1)
else:
    print("Jupyter failed to start in time")
    sys.exit(1)

# Check if a Deno kernel already exists
try:
    response = requests.get(f'{base_url}/api/kernels', params={'token': token})
    if response.status_code == 200:
        kernels = response.json()
        deno_kernels = [k for k in kernels if k.get('name') == 'deno']
        
        if not deno_kernels:
            # Start a new Deno kernel
            print("Starting Deno kernel...")
            headers = {'Content-Type': 'application/json'}
            data = {'name': 'deno'}
            response = requests.post(
                f'{base_url}/api/kernels',
                params={'token': token},
                headers=headers,
                json=data
            )
            if response.status_code == 201:
                kernel = response.json()
                print(f"Deno kernel started: {kernel['id']}")
            else:
                print(f"Failed to start kernel: {response.status_code}")
                print(f"Response: {response.text}")
        else:
            print(f"Deno kernel already running: {deno_kernels[0]['id']}")
    else:
        print(f"Failed to check kernels: {response.status_code}")
except Exception as e:
    print(f"Error managing kernel: {e}")
PYTHON_SCRIPT

# Start the kernel manager in background after a delay
(sleep 10 && python /home/jovyan/start-kernel.py) &

# Execute the original command
exec "$@"
SCRIPT_END

# Set the working directory
WORKDIR /home/${NB_USER}/work

# Expose the JupyterLab port
EXPOSE 8888

# Set environment variables for better Deno experience
ENV DENO_DIR=/home/${NB_USER}/.deno \
    DENO_INSTALL_ROOT=/home/${NB_USER}/.deno/bin

ENTRYPOINT ["/usr/local/bin/docker-entrypoint.sh"]
CMD ["start-notebook.sh"]