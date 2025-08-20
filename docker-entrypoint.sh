#!/bin/bash
set -e

# Configure Jupyter with the provided token
if [ -n "$JUPYTER_TOKEN" ]; then
    echo "Configuring Jupyter with authentication token..."
    
    # Create jupyter config if it doesn't exist
    jupyter notebook --generate-config -y || true
    
    # Set the token in the config
    echo "c.NotebookApp.token = '${JUPYTER_TOKEN}'" >> /home/jovyan/.jupyter/jupyter_notebook_config.py
    echo "c.ServerApp.token = '${JUPYTER_TOKEN}'" >> /home/jovyan/.jupyter/jupyter_notebook_config.py
    echo "c.LabApp.token = '${JUPYTER_TOKEN}'" >> /home/jovyan/.jupyter/jupyter_notebook_config.py
    
    # Disable password prompt
    echo "c.NotebookApp.password = ''" >> /home/jovyan/.jupyter/jupyter_notebook_config.py
    echo "c.ServerApp.password = ''" >> /home/jovyan/.jupyter/jupyter_notebook_config.py
    
    # Allow connections from any IP (needed for Docker)
    echo "c.NotebookApp.ip = '0.0.0.0'" >> /home/jovyan/.jupyter/jupyter_notebook_config.py
    echo "c.ServerApp.ip = '0.0.0.0'" >> /home/jovyan/.jupyter/jupyter_notebook_config.py
    
    # Disable browser auto-open
    echo "c.NotebookApp.open_browser = False" >> /home/jovyan/.jupyter/jupyter_notebook_config.py
    echo "c.ServerApp.open_browser = False" >> /home/jovyan/.jupyter/jupyter_notebook_config.py
    
    # Set base URL
    echo "c.NotebookApp.base_url = '/'" >> /home/jovyan/.jupyter/jupyter_notebook_config.py
    echo "c.ServerApp.base_url = '/'" >> /home/jovyan/.jupyter/jupyter_notebook_config.py
    
    # Allow root access if needed
    echo "c.NotebookApp.allow_root = True" >> /home/jovyan/.jupyter/jupyter_notebook_config.py
    echo "c.ServerApp.allow_root = True" >> /home/jovyan/.jupyter/jupyter_notebook_config.py
    
    # Enable CORS for Open WebUI
    echo "c.NotebookApp.allow_origin = '*'" >> /home/jovyan/.jupyter/jupyter_notebook_config.py
    echo "c.ServerApp.allow_origin = '*'" >> /home/jovyan/.jupyter/jupyter_notebook_config.py
    echo "c.NotebookApp.allow_credentials = True" >> /home/jovyan/.jupyter/jupyter_notebook_config.py
    echo "c.ServerApp.allow_credentials = True" >> /home/jovyan/.jupyter/jupyter_notebook_config.py
    
    # Disable some security features for API access
    echo "c.NotebookApp.disable_check_xsrf = True" >> /home/jovyan/.jupyter/jupyter_notebook_config.py
    echo "c.ServerApp.disable_check_xsrf = True" >> /home/jovyan/.jupyter/jupyter_notebook_config.py
fi

# Ensure Deno kernel is properly registered
deno jupyter --unstable --install || true

# Create a startup script that will create a kernel after Jupyter starts
cat > /home/jovyan/start-kernel.py << 'EOF'
import time
import requests
import json
import os

token = os.environ.get('JUPYTER_TOKEN', '')
base_url = 'http://localhost:8888'

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
    exit(1)

# Check if a Deno kernel already exists
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
    else:
        print(f"Deno kernel already running: {deno_kernels[0]['id']}")
EOF

# Start Jupyter in the background, wait a bit, then start a kernel
(sleep 10 && python /home/jovyan/start-kernel.py) &

# Execute the original command
exec "$@"