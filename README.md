# JupyterLab with Deno Kernel for Open WebUI

This repository contains a Docker setup for running JupyterLab with Deno kernel as the default runtime, designed to work with Open WebUI's Code Interpreter feature.

## Features

- 🦕 **Deno Kernel by Default**: TypeScript/JavaScript execution environment
- 🔐 **Token Authentication**: Secure access via environment variable
- 💾 **Persistent Storage**: Notebooks saved in Docker volume
- 🚀 **Ready for Portainer**: Deploy directly from GitHub
- 🌐 **Open WebUI Compatible**: Works with the Jupyter backend integration

## Quick Start

### Option 1: Deploy with Portainer

1. In Portainer, go to **Stacks** → **Add Stack**
2. Choose **Repository** as the build method
3. Enter your GitHub repository URL
4. Set the following environment variables:
   - `JUPYTER_TOKEN`: Your secure authentication token (required)
5. Deploy the stack

### Option 2: Local Docker Compose

1. Clone this repository:

```bash
git clone https://github.com/yourusername/jupyterlab-deno.git
cd jupyterlab-deno
```

2. Create a `.env` file:

```bash
echo "JUPYTER_TOKEN=your-secure-token-here" > .env
```

3. Build and run:

```bash
docker-compose up -d --build
```

4. Access JupyterLab at `http://localhost:8889?token=your-secure-token-here`

## Configuration

### Environment Variables

| Variable             | Description                      | Default                  |
| -------------------- | -------------------------------- | ------------------------ |
| `JUPYTER_TOKEN`      | Authentication token for Jupyter | `your-secure-token-here` |
| `JUPYTER_ENABLE_LAB` | Enable JupyterLab interface      | `yes`                    |
| `GRANT_SUDO`         | Grant sudo access to jovyan user | `no`                     |

### Ports

- **8889**: JupyterLab web interface (maps to internal 8888)

### Volumes

- `jupyter_notebooks`: Persistent storage for notebooks at `/home/jovyan/work`

## Open WebUI Integration

### Setup

1. Deploy this JupyterLab stack first
2. In Open WebUI settings, configure the Code Interpreter:
   - **Jupyter URL**: `http://your-host:8889` (or container name if in same network)
   - **Token**: The same token you set in `JUPYTER_TOKEN`

### Custom Deno/TypeScript Prompt

Override the default Python interpreter prompt in Open WebUI with the custom Deno prompt provided in `deno-code-interpreter-prompt.md`.

## Using Deno in Notebooks

### Basic Example

```typescript
// TypeScript is fully supported
interface Person {
  name: string;
  age: number;
}

const greet = (person: Person): string => {
  return `Hello, ${person.name}! You are ${person.age} years old.`;
};

console.log(greet({ name: "Alice", age: 30 }));
```

### Import NPM Packages

```typescript
// Import directly from npm
import _ from "npm:lodash";
import axios from "npm:axios";

const data = _.chunk([1, 2, 3, 4, 5, 6], 2);
console.log(data);
```

### Rich Output with Jupyter APIs

```typescript
// Display HTML
Deno.jupyter.html`
  <h1>Welcome to Deno Jupyter!</h1>
  <p style="color: blue;">This is rendered HTML</p>
`;

// Display Markdown
Deno.jupyter.md`
# Data Analysis Report
- **Status**: Complete
- **Results**: Successful
`;

// Display images
const imageData = await Deno.readFile("./chart.png");
Deno.jupyter.image(imageData);
```

### Data Visualization

```typescript
import * as Plot from "npm:@observablehq/plot";
import { document } from "jsr:@ry/jupyter-helper";

const data = [
  { x: 1, y: 2 },
  { x: 2, y: 4 },
  { x: 3, y: 1 },
  { x: 4, y: 3 },
];

Plot.plot({
  marks: [Plot.dot(data, { x: "x", y: "y", fill: "blue", r: 5 })],
  document,
});
```

## Troubleshooting

### Cannot connect to Jupyter

1. Check if the container is running: `docker ps`
2. Verify the token in logs: `docker logs jupyterlab-deno`
3. Ensure port 8889 is not blocked by firewall

### Deno kernel not available

The kernel should be installed automatically. If not:

```bash
docker exec -it jupyterlab-deno deno jupyter --unstable --install
docker restart jupyterlab-deno
```

### Notebooks not persisting

Ensure the volume is properly mounted:

```bash
docker volume ls | grep jupyterlab_deno_notebooks
```

## Security Notes

- **Change the default token** before deploying to production
- Consider using HTTPS with a reverse proxy (nginx, Traefik)
- The Deno kernel runs with `--allow-all` permissions (Jupyter limitation)
- Restrict network access if running sensitive code

## File Structure

```
.
├── Dockerfile                 # Main container definition
├── docker-entrypoint.sh      # Custom startup script
├── docker-compose.yml        # Stack configuration
└── README.md                 # This file
```

## Support

For issues related to:

- **Deno Kernel**: Check [Deno documentation](https://docs.deno.com/runtime/manual/tools/jupyter/)
- **JupyterLab**: See [Jupyter documentation](https://jupyterlab.readthedocs.io/)
- **Open WebUI**: Refer to [Open WebUI docs](https://docs.openwebui.com/)

## License

MIT License - Feel free to use and modify as needed.
