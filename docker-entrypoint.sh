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

# Set the working directory
WORKDIR /home/${NB_USER}/work

# Expose the JupyterLab port
EXPOSE 8888

# Copy custom entrypoint
COPY --chown=${NB_UID}:${NB_GID} docker-entrypoint.sh /usr/local/bin/
RUN chmod +x /usr/local/bin/docker-entrypoint.sh

# Set environment variables for better Deno experience
ENV DENO_DIR=/home/${NB_USER}/.deno \
    DENO_INSTALL_ROOT=/home/${NB_USER}/.deno/bin

ENTRYPOINT ["/usr/local/bin/docker-entrypoint.sh"]
CMD ["start-notebook.sh"]