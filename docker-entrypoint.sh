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
fi

# Ensure Deno kernel is properly registered
deno jupyter --unstable --install || true

# Execute the original command
exec "$@"