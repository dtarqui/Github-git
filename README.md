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

## Usage

Quick start to run the stack and use the git server locally:

```bash
# Copy example env and edit values (MICROSERVICE_URL and MICROSERVICE_AUTH_TOKEN required)
cp .env.example .env

# Start services (git-server + mongodb added in compose)
docker compose up -d

# View git-server logs
docker compose logs -f git-server

# Create a repo (inside the git-server container)
docker exec git-server manage-repo create alice/myapp.git
```

Notes:
- The SSH service is published on host port 2222 by default; clone using `ssh://git@localhost:2222/git-server/repos/alice/myapp.git`.

## Use case: create a repo, add an SSH key, clone and push

1. Ensure `.env` contains `MICROSERVICE_URL` and `MICROSERVICE_AUTH_TOKEN` and start the stack (see Usage).

2. Create a bare repo on the server:

```bash
docker exec git-server manage-repo create alice/myapp.git
```

3. Register an SSH public key for `alice` (the microservice normally writes this file). Example format for `/git-server/keys/alice.key`:

```
command="/usr/local/bin/git-auth alice",no-pty,no-port-forwarding ssh-ed25519 AAAA... alice@example.com
```

To test quickly from the host (replace the key line with a real public key):

```bash
echo 'command="/usr/local/bin/git-auth alice",no-pty,no-port-forwarding ssh-ed25519 AAAA... alice@example.com' \
	| docker exec -i git-server tee /git-server/keys/alice.key
```

4. Clone the repo (use host port 2222):

```bash
git clone ssh://git@localhost:2222/git-server/repos/alice/myapp.git
cd myapp
echo hello > README.md
git add README.md
git commit -m "add README"
git push origin master
```

5. How the auth check works:
- On every SSH operation the `git-auth` hook calls `${MICROSERVICE_URL}/internal/ssh-access` with headers `Authorization: Bearer <MICROSERVICE_AUTH_TOKEN>`, `X-Git-User`, `X-Git-Repo`, and `X-Git-Op` (read/write). A `200` response allows the operation; other statuses deny it. See `SETUP.md` for an implementation sketch.

---
