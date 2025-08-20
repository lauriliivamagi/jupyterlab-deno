# Use official Jupyter base image
FROM jupyter/base-notebook:latest

# Switch to root for system installations
USER root

# Install system dependencies
RUN apt-get update && apt-get install -y \
    curl \
    unzip \
    jq \
    && rm -rf /var/lib/apt/lists/*

# Install Deno (latest stable)
ENV DENO_INSTALL=/usr/local
RUN curl -fsSL https://deno.land/install.sh | sh && \
    ln -s /usr/local/bin/deno /usr/bin/deno

# Install Python packages
RUN pip install --no-cache-dir requests websocket-client

# Switch back to jovyan user
USER ${NB_UID}

# Install Deno Jupyter kernel first
RUN deno jupyter --force --install 2>/dev/null || \
    deno jupyter --unstable --force --install 2>/dev/null || true

# Create the kernel wrapper for debugging
RUN cat > /home/${NB_USER}/kernel-wrapper.ts << 'EOF'
#!/usr/bin/env -S deno run --allow-all

// Kernel wrapper to debug message issues
const logFile = "/tmp/kernel-debug.log";

function log(message: string) {
  const timestamp = new Date().toISOString();
  try {
    Deno.writeTextFileSync(logFile, `${timestamp}: ${message}\n`, { append: true });
  } catch (e) {
    console.error(`Failed to write log: ${e}`);
  }
}

log("=== Kernel wrapper started ===");

// Start the actual Deno kernel
const kernelProcess = new Deno.Command("deno", {
  args: ["jupyter", "--kernel"],
  stdin: "piped",
  stdout: "piped",
  stderr: "piped",
});

log("Starting Deno kernel process...");
const kernel = kernelProcess.spawn();

// Forward stdin but log it
(async () => {
  const reader = Deno.stdin.readable.getReader();
  const writer = kernel.stdin.getWriter();
  
  try {
    while (true) {
      const { done, value } = await reader.read();
      if (done) break;
      
      const decoder = new TextDecoder();
      const text = decoder.decode(value);
      
      // Log first 500 chars of the message
      const preview = text.length > 500 ? text.substring(0, 500) + "..." : text;
      log(`STDIN received (${value.length} bytes): ${preview}`);
      
      // Check for JSON structure issues
      if (text.includes("{")) {
        const openBraces = (text.match(/{/g) || []).length;
        const closeBraces = (text.match(/}/g) || []).length;
        if (openBraces !== closeBraces) {
          log(`WARNING: Unbalanced braces! Open: ${openBraces}, Close: ${closeBraces}`);
        }
      }
      
      // Forward to kernel
      await writer.write(value);
    }
  } catch (e) {
    log(`Error processing stdin: ${e}`);
  }
})();

// Forward stdout
(async () => {
  const reader = kernel.stdout.getReader();
  const writer = Deno.stdout.writable.getWriter();
  
  try {
    while (true) {
      const { done, value } = await reader.read();
      if (done) break;
      await writer.write(value);
    }
  } catch (e) {
    log(`Error processing stdout: ${e}`);
  }
})();

// Forward stderr and log it
(async () => {
  const reader = kernel.stderr.getReader();
  const writer = Deno.stderr.writable.getWriter();
  const decoder = new TextDecoder();
  
  try {
    while (true) {
      const { done, value } = await reader.read();
      if (done) break;
      
      const text = decoder.decode(value);
      log(`STDERR: ${text}`);
      
      // Look for the specific error
      if (text.includes("premature end of input")) {
        log("ERROR: JSON parsing failed - message was truncated!");
      }
      
      await writer.write(value);
    }
  } catch (e) {
    log(`Error processing stderr: ${e}`);
  }
})();

// Wait for kernel to exit
const status = await kernel.status;
log(`Kernel exited with status: ${status.code}`);
Deno.exit(status.code);
EOF

# Make the wrapper executable
RUN chmod +x /home/${NB_USER}/kernel-wrapper.ts

# Now modify the Deno kernel to use our wrapper
RUN cat > /home/${NB_USER}/install-debug-kernel.sh << 'EOF'
#!/bin/bash

# Get the kernel directory
KERNEL_DIR="/home/jovyan/.local/share/jupyter/kernels/deno"

# Backup original kernel.json
if [ -f "$KERNEL_DIR/kernel.json" ]; then
    cp "$KERNEL_DIR/kernel.json" "$KERNEL_DIR/kernel.json.backup"
fi

# Create new kernel.json that uses our wrapper
cat > "$KERNEL_DIR/kernel.json" << KERNELJSON
{
  "argv": [
    "/home/jovyan/kernel-wrapper.ts"
  ],
  "display_name": "Deno (Debug)",
  "language": "typescript",
  "interrupt_mode": "signal",
  "env": {}
}
KERNELJSON

echo "Debug kernel installed. Logs will be written to /tmp/kernel-debug.log"
EOF

RUN chmod +x /home/${NB_USER}/install-debug-kernel.sh

# Create directories
RUN mkdir -p /home/${NB_USER}/.jupyter

# Create Jupyter configuration
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
c.ServerApp.tornado_settings = {{
    'headers': {{'Content-Security-Policy': ""}},
    'websocket_max_message_size': 100 * 1024 * 1024,
}}
c.MultiKernelManager.default_kernel_name = 'deno'
c.MappingKernelManager.cull_idle_timeout = 0
c.MappingKernelManager.cull_interval = 0
c.KernelManager.shutdown_wait_time = 10.0
"""

token = os.environ.get('JUPYTER_TOKEN', 'default-token-please-change')
config_content = config_template.format(token=token)

with open('/home/jovyan/.jupyter/jupyter_server_config.py', 'w') as f:
    f.write(config_content)

print(f"Jupyter configured with token: {token[:10]}...")
EOF

# Create startup script
RUN cat > /home/${NB_USER}/start.sh << 'EOF'
#!/bin/bash

# Configure Jupyter
python /home/jovyan/configure_jupyter.py

# Install Deno kernel
echo "Installing Deno kernel..."
deno jupyter --force --install 2>/dev/null || true

# Install debug wrapper (uncomment to enable debugging)
# echo "Installing debug kernel wrapper..."
# /home/jovyan/install-debug-kernel.sh

# To enable debugging, uncomment the line above or run:
# docker exec jupyterlab-deno /home/jovyan/install-debug-kernel.sh
# docker restart jupyterlab-deno

# List kernels
echo "Available kernels:"
jupyter kernelspec list

# Create initial kernel after delay
(
    sleep 15
    curl -X POST "http://localhost:8888/api/kernels?token=${JUPYTER_TOKEN}" \
         -H "Content-Type: application/json" \
         -d '{"name": "deno"}' 2>/dev/null || true
    echo "Initial kernel created"
) &

# Start Jupyter
exec start-notebook.sh "$@"
EOF

RUN chmod +x /home/${NB_USER}/start.sh

WORKDIR /home/${NB_USER}/work
EXPOSE 8888

ENV DENO_DIR=/home/${NB_USER}/.deno \
    DENO_INSTALL_ROOT=/home/${NB_USER}/.deno/bin

ENTRYPOINT ["/home/jovyan/start.sh"]