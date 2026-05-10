# Git Server

Git storage backend (SSH + HTTP) designed to run behind a microservice layer.

- **SSH (port 22)** — clients connect here. Every operation is checked by the `git-auth` hook, which calls your microservice before allowing access.
- **HTTP (port 80, internal)** — your microservice proxies git HTTP requests to this port. Never exposed to clients.

Your microservice owns all user management, authentication, and access control. This server stores bare repos and enforces the decisions your microservice makes.

## Quick reference

```bash
# Configure
cp .env.example .env   # set MICROSERVICE_URL and MICROSERVICE_AUTH_TOKEN

# Start
docker compose up -d

# Admin
docker exec git-server manage-repo list
docker exec git-server manage-repo create alice/myapp.git
docker exec git-server manage-repo delete alice/myapp.git
```

## Full documentation

See **[SETUP.md](SETUP.md)** for:
- Architecture diagram
- Deployment instructions
- How to create repos from the microservice (JGit)
- How to register SSH keys (key file format)
- How to implement `/internal/ssh-access`
- How to proxy HTTP git traffic
- Environment variables reference
