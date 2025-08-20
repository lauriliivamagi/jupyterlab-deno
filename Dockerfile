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

# Install Python packages with specific versions for compatibility
RUN pip install --no-cache-dir \
    requests \
    websocket-client \
    jupyter-client==8.3.1 \
    jupyter-core==5.3.1

# Switch back to jovyan user
USER ${NB_UID}

# Install Deno Jupyter kernel
RUN deno jupyter --force --install 2>/dev/null || \
    deno jupyter --unstable --force --install 2>/dev/null || true

# Create directories
RUN mkdir -p /home/${NB_USER}/.jupyter

# Create Jupyter configuration with message size limits
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

# Increase WebSocket message size limits
c.ServerApp.tornado_settings = {{
    'headers': {{'Content-Security-Policy': ""}},
    'websocket_max_message_size': 100 * 1024 * 1024,  # 100 MB
}}

# Kernel settings
c.MultiKernelManager.default_kernel_name = 'deno'
c.MappingKernelManager.cull_idle_timeout = 0
c.MappingKernelManager.cull_interval = 0
c.MappingKernelManager.cull_connected = False
c.MappingKernelManager.cull_busy = False

# Increase kernel startup timeout
c.KernelManager.shutdown_wait_time = 10.0
c.ZMQChannelsWebsocketConnection.iopub_msg_rate_limit = 1000000
c.ZMQChannelsWebsocketConnection.iopub_data_rate_limit = 10000000000
c.ZMQChannelsWebsocketConnection.rate_limit_window = 1.0
"""

token = os.environ.get('JUPYTER_TOKEN', 'default-token-please-change')
config_content = config_template.format(token=token)

with open('/home/jovyan/.jupyter/jupyter_server_config.py', 'w') as f:
    f.write(config_content)

print(f"Jupyter configured with token: {token[:10]}...")
EOF

# Create a message interceptor for debugging
RUN cat > /home/${NB_USER}/message_proxy.py << 'EOF'
import asyncio
import websockets
import json
import sys
from datetime import datetime

async def proxy_messages():
    """Proxy WebSocket messages to debug JSON issues"""
    
    # This would need to be integrated into Jupyter's WebSocket handler
    # For now, it's a reference implementation
    
    async def handle_message(message):
        try:
            # Try to parse as JSON
            data = json.loads(message)
            print(f"[{datetime.now()}] Valid JSON message received", file=sys.stderr)
            return message
        except json.JSONDecodeError as e:
            print(f"[{datetime.now()}] Invalid JSON: {e}", file=sys.stderr)
            print(f"Message preview: {message[:200]}...", file=sys.stderr)
            # Try to fix common issues
            if message.endswith('"}'):
                # Missing closing bracket
                fixed = message + '}'
                try:
                    json.loads(fixed)
                    print("Fixed by adding closing bracket", file=sys.stderr)
                    return fixed
                except:
                    pass
            return None
    
    return handle_message

if __name__ == "__main__":
    # Test the proxy
    test_message = '{"test": "data"'  # Intentionally broken
    asyncio.run(proxy_messages()(test_message))
EOF

# Create an improved startup script
RUN cat > /home/${NB_USER}/start.sh << 'EOF'
#!/bin/bash
set -e

# Configure Jupyter
python /home/jovyan/configure_jupyter.py

# Ensure Deno kernel is installed with verbose output
echo "Installing Deno kernel..."
deno jupyter --force --install || true

# List installed kernels
echo "Installed kernels:"
jupyter kernelspec list

# Create a test kernel to ensure everything works
(
    sleep 15
    echo "Creating test kernel..."
    response=$(curl -s -X POST "http://localhost:8888/api/kernels?token=${JUPYTER_TOKEN}" \
                    -H "Content-Type: application/json" \
                    -d '{"name": "deno"}')
    kernel_id=$(echo $response | jq -r '.id')
    echo "Test kernel created: $kernel_id"
    
    # Send a simple test message
    sleep 2
    echo "Testing kernel execution..."
    
    # Use Python to send proper WebSocket message
    python3 << PYTEST
import websocket
import json
import uuid

try:
    ws = websocket.create_connection(
        f"ws://localhost:8888/api/kernels/${kernel_id}/channels?token=${JUPYTER_TOKEN}",
        timeout=5
    )
    
    msg = {
        "header": {
            "msg_id": str(uuid.uuid4()),
            "msg_type": "execute_request",
            "username": "test",
            "session": str(uuid.uuid4()),
            "date": "",
            "version": "5.3"
        },
        "parent_header": {},
        "metadata": {},
        "content": {
            "code": "console.log('Kernel test successful')",
            "silent": False,
            "store_history": True,
            "user_expressions": {},
            "allow_stdin": False,
            "stop_on_error": True
        },
        "channel": "shell",
        "buffers": []
    }
    
    ws.send(json.dumps(msg))
    print("Test message sent successfully")
    ws.close()
except Exception as e:
    print(f"Kernel test failed: {e}")
PYTEST
) &

# Start Jupyter
exec start-notebook.sh "$@"
EOF

RUN chmod +x /home/${NB_USER}/start.sh

WORKDIR /home/${NB_USER}/work
EXPOSE 8888

# Set environment variables
ENV DENO_DIR=/home/${NB_USER}/.deno \
    DENO_INSTALL_ROOT=/home/${NB_USER}/.deno/bin \
    DENO_NO_UPDATE_CHECK=1 \
    RUST_BACKTRACE=1

ENTRYPOINT ["/home/jovyan/start.sh"]