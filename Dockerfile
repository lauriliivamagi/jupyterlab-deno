# Use official Jupyter base image
FROM jupyter/base-notebook:latest

# Switch to root for system installations
USER root

# Install system dependencies
RUN apt-get update && apt-get install -y \
    curl \
    unzip \
    && rm -rf /var/lib/apt/lists/*

# Install Deno
ENV DENO_INSTALL=/usr/local
RUN curl -fsSL https://deno.land/install.sh | sh

# Make deno available in PATH for all users
RUN ln -s /usr/local/bin/deno /usr/bin/deno

# Install Python packages for kernel management
RUN pip install --no-cache-dir requests

# Switch back to jovyan user
USER ${NB_UID}

# Install Deno Jupyter kernel
RUN deno jupyter --unstable --install

# Create jupyter configuration directory
RUN mkdir -p /home/${NB_USER}/.jupyter

# Configure JupyterLab settings to use Deno kernel by default
RUN mkdir -p /home/${NB_USER}/.jupyter/lab/user-settings/@jupyterlab/notebook-extension && \
    echo '{"defaultCell": {"kernelName": "deno"}}' > \
    /home/${NB_USER}/.jupyter/lab/user-settings/@jupyterlab/notebook-extension/tracker.jupyterlab-settings

# Create a more comprehensive Jupyter config
RUN echo "c = get_config()" > /home/${NB_USER}/.jupyter/jupyter_notebook_config.py && \
    echo "c.MultiKernelManager.default_kernel_name = 'deno'" >> /home/${NB_USER}/.jupyter/jupyter_notebook_config.py && \
    echo "c.KernelManager.autorestart = True" >> /home/${NB_USER}/.jupyter/jupyter_notebook_config.py && \
    echo "c.MappingKernelManager.cull_idle_timeout = 0" >> /home/${NB_USER}/.jupyter/jupyter_notebook_config.py && \
    echo "c.MappingKernelManager.cull_interval = 0" >> /home/${NB_USER}/.jupyter/jupyter_notebook_config.py && \
    echo "c.MappingKernelManager.cull_connected = False" >> /home/${NB_USER}/.jupyter/jupyter_notebook_config.py && \
    echo "c.MappingKernelManager.cull_busy = False" >> /home/${NB_USER}/.jupyter/jupyter_notebook_config.py

# Set the working directory
WORKDIR /home/${NB_USER}/work

# Expose the JupyterLab port
EXPOSE 8888

# Custom entrypoint to handle token authentication and kernel startup
COPY --chown=${NB_UID}:${NB_GID} docker-entrypoint.sh /usr/local/bin/
RUN chmod +x /usr/local/bin/docker-entrypoint.sh

ENTRYPOINT ["/usr/local/bin/docker-entrypoint.sh"]
CMD ["start-notebook.sh"]