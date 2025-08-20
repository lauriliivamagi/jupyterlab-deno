#!/bin/bash

# Healthcheck script for JupyterLab with Deno kernel

TOKEN="${JUPYTER_TOKEN:-your-secure-token-here}"
API_URL="http://localhost:8888/api"

# Check if Jupyter is responding
if ! curl -sf "${API_URL}?token=${TOKEN}" > /dev/null; then
    echo "Jupyter API not responding"
    exit 1
fi

# Check if Deno kernel is available
KERNELSPECS=$(curl -sf "${API_URL}/kernelspecs?token=${TOKEN}" | grep -o '"deno"' || true)
if [ -z "$KERNELSPECS" ]; then
    echo "Deno kernel not available"
    exit 1
fi

# Check if at least one kernel is running (for Open WebUI)
KERNEL_COUNT=$(curl -sf "${API_URL}/kernels?token=${TOKEN}" | grep -o '"id"' | wc -l)
if [ "$KERNEL_COUNT" -eq 0 ]; then
    echo "No kernels running, starting one..."
    # Try to start a kernel
    curl -sf -X POST "${API_URL}/kernels?token=${TOKEN}" \
        -H "Content-Type: application/json" \
        -d '{"name": "deno"}' > /dev/null || true
    sleep 2
    # Check again
    KERNEL_COUNT=$(curl -sf "${API_URL}/kernels?token=${TOKEN}" | grep -o '"id"' | wc -l)
    if [ "$KERNEL_COUNT" -eq 0 ]; then
        echo "Failed to start kernel"
        exit 1
    fi
fi

echo "Health check passed: Jupyter running with $KERNEL_COUNT kernel(s)"
exit 0