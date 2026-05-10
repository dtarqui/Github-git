# Git Server — Setup & Integration Guide

This server is a **storage backend** for a microservice-based GitHub-like platform. It exposes two Git transport protocols:

- **SSH (port 22)** — clients connect directly; every operation passes through the `git-auth` hook, which calls your microservice to check permissions.
- **HTTP (port 80, internal only)** — used exclusively by your microservice as a reverse proxy; never exposed to clients.

Your microservice owns all auth logic, user management, and repo lifecycle. This server just stores bare repos and enforces the access decisions your microservice makes.

---

## Architecture

```
Clients
  ├─ SSH git  ──────────────────────────────────────────────────────────────┐
  │                                                                         ▼
  │                                                                  git-server:22
  │                                                                  git-auth hook
  │                                                                       │
  │                                          ┌──────────────────────────  │  permission check
  │                                          ▼                            │
  └─ HTTPS git ──► your microservice ─────────── GET /internal/ssh-access ◄┘
       REST API        (git-service)         │
                            │               │  allow → exec git command
                            │  HTTP proxy   │  deny  → connection closed
                            ▼
                      git-server:80
                   (Apache, no auth)
                            │
                    /git-server/repos/
                     ├── alice/
                     │    └── myapp.git
                     └── bob/
                          └── api.git
```

---

## Deployment

### 1. Configure environment

```bash
cp .env.example .env
```

Edit `.env`:

| Variable | Description |
|----------|-------------|
| `MICROSERVICE_URL` | Internal URL of your microservice. The `git-auth` script calls `${MICROSERVICE_URL}/internal/ssh-access` on every SSH git operation. Example: `http://git-service:8080` |
| `MICROSERVICE_AUTH_TOKEN` | Shared secret. Sent as `Authorization: Bearer <token>`. Your microservice must verify this on `/internal/ssh-access`. |

### 2. Start

Development (git-server only, microservice started separately):
```bash
docker compose up -d
```

Production (git-server + microservice together):
```bash
# Edit docker-compose.prod.yml — replace your-git-service:latest with your image
docker compose -f docker-compose.prod.yml up -d
```

### 3. Verify

```bash
docker logs git-server
```

Expected output:
```
---
SSH access checks → http://git-service:8080/internal/ssh-access
HTTP git (internal): http://localhost:80/git/<owner>/<repo>.git
SSH git:             ssh://git@<host>:22/git-server/repos/<owner>/<repo>.git
---
```

---

## Volume contract

Both the git-server and your microservice must mount these volumes:

| Volume | Mount path | Who writes | Purpose |
|--------|-----------|------------|---------|
| `git-repos` | `/git-server/repos` | Microservice (JGit) | All bare repos |
| `git-keys` | `/git-server/keys` | Microservice | SSH authorized_keys entries |
| `git-ssh-host-keys` | `/git-server/ssh-host-keys` | git-server (once) | Persists SSH host keys across restarts |

The `git-keys` volume is watched every 5 seconds. Any file change triggers an automatic rebuild of `authorized_keys` — no restart required.

---

## Microservice integration

### A. Creating repos

Mount `git-repos` in your microservice and create bare repos with JGit:

```java
// application.yml
// git.repos-path: /git-server/repos

@Service
public class GitOpsService {

    @Value("${git.repos-path}")
    private String reposPath;

    public void createRepo(String owner, String name) throws GitAPIException {
        Path repoDir = Paths.get(reposPath, owner, name + ".git");
        Files.createDirectories(repoDir);
        Git.init()
            .setDirectory(repoDir.toFile())
            .setBare(true)
            .call();
        repoDir.toFile().setWritable(true, false);   // group-writable for Apache
    }

    public void deleteRepo(String owner, String name) throws IOException {
        Path repoDir = Paths.get(reposPath, owner, name + ".git");
        try (Stream<Path> walk = Files.walk(repoDir)) {
            walk.sorted(Comparator.reverseOrder())
                .map(Path::toFile)
                .forEach(File::delete);
        }
    }
}
```

Repo path on disk:   `/git-server/repos/{owner}/{name}.git`
HTTP URL (internal): `http://git-server:80/git/{owner}/{name}.git`
SSH URL (client):    `ssh://git@yourserver/git-server/repos/{owner}/{name}.git`

### B. Registering SSH keys

Mount `git-keys` in your microservice. When a user adds an SSH key, write a file named `{username}.key` containing one line per key with the `command=` prefix:

```java
@Service
public class SshKeyService {

    @Value("${git.keys-path}")
    private String keysPath;

    // Call this after any add or remove operation for a user.
    public void syncUserKeys(String username, List<String> publicKeys) throws IOException {
        Path keyFile = Paths.get(keysPath, username + ".key");
        if (publicKeys.isEmpty()) {
            Files.deleteIfExists(keyFile);
            return;
        }
        StringBuilder sb = new StringBuilder();
        for (String key : publicKeys) {
            sb.append(String.format(
                "command=\"/usr/local/bin/git-auth %s\",no-pty,no-port-forwarding %s\n",
                username, key.strip()
            ));
        }
        Files.writeString(keyFile, sb.toString(),
            StandardOpenOption.CREATE, StandardOpenOption.TRUNCATE_EXISTING);
    }
}
```

**File format in `git-keys/{username}.key`:**
```
command="/usr/local/bin/git-auth alice",no-pty,no-port-forwarding ssh-ed25519 AAAA...key1
command="/usr/local/bin/git-auth alice",no-pty,no-port-forwarding ssh-ed25519 AAAA...key2
```

The `command=` prefix forces every SSH connection through `git-auth`, which calls your microservice before executing any git command. Multiple keys for the same user = multiple lines in the same file.

### C. SSH access check endpoint

The `git-auth` script calls this on every SSH git operation. Implement it in your microservice:

**Request:**
```
GET /internal/ssh-access
Authorization: Bearer <MICROSERVICE_AUTH_TOKEN>
X-Git-User: alice
X-Git-Repo: alice/myapp.git
X-Git-Op:   read | write
```

**Response:**
- `200` → allow the git operation
- `403` or any other status → deny

**Spring Boot implementation:**

```java
@RestController
@RequestMapping("/internal")
class InternalController {

    @Value("${microservice.auth-token}")
    private String authToken;

    @GetMapping("/ssh-access")
    ResponseEntity<Void> sshAccess(
            @RequestHeader("Authorization")  String authHeader,
            @RequestHeader("X-Git-User")     String username,
            @RequestHeader("X-Git-Repo")     String repo,
            @RequestHeader("X-Git-Op")       String op) {

        if (!authHeader.equals("Bearer " + authToken))
            return ResponseEntity.status(403).build();

        boolean allowed = switch (op) {
            case "read"  -> accessService.canRead(username, repo);
            case "write" -> accessService.canWrite(username, repo);
            default      -> false;
        };

        return allowed
            ? ResponseEntity.ok().build()
            : ResponseEntity.status(403).build();
    }
}
```

Make sure `/internal/**` is **not reachable from the public internet** — it should only be accessible inside the Docker network.

### D. HTTP git proxy

Your microservice intercepts all `/{owner}/{repo}.git/**` requests, checks JWT/session auth and permissions, then streams to the git server internally.

**Git Smart HTTP URL patterns:**

| Operation | Method | URL pattern |
|-----------|--------|------------|
| Clone / fetch (negotiate) | GET | `/{owner}/{repo}.git/info/refs?service=git-upload-pack` |
| Clone / fetch (data) | POST | `/{owner}/{repo}.git/git-upload-pack` |
| Push (negotiate) | GET | `/{owner}/{repo}.git/info/refs?service=git-receive-pack` |
| Push (data) | POST | `/{owner}/{repo}.git/git-receive-pack` |

**Spring Boot proxy controller (sketch):**

```java
@Controller
public class GitProxyController {

    private final GitProxyService proxy;
    private final AccessService access;

    // Matches: /alice/myapp.git/info/refs  /alice/myapp.git/git-upload-pack  etc.
    @RequestMapping("/{owner}/{repo:.+\\.git}/**")
    public StreamingResponseBody proxy(
            HttpServletRequest req,
            HttpServletResponse res,
            @PathVariable String owner,
            @PathVariable String repo) {

        String repoPath = owner + "/" + repo;
        String op       = resolveOp(req);         // "read" or "write"
        String user     = resolveUser(req);       // from JWT

        access.checkOrThrow(user, repoPath, op);  // throws 401/403

        // Forward to git-server internal HTTP, stream response back.
        String upstreamUrl = gitServerUrl + "/git/" + repoPath +
                             req.getRequestURI().substring(("/" + owner + "/" + repo).length()) +
                             (req.getQueryString() != null ? "?" + req.getQueryString() : "");

        return out -> proxy.stream(req, res, upstreamUrl, out);
    }
}
```

**Critical:** use `StreamingResponseBody` (or reactive streams). Never buffer the full body — git pushes can be gigabytes. Also pass `Content-Type`, `Content-Encoding`, and `Transfer-Encoding` headers through unchanged.

---

## Admin commands

For debugging and manual recovery — not part of normal operation:

```bash
# Inspect repos on disk
docker exec git-server manage-repo list

# Manually create a repo (normally done by the microservice via JGit)
docker exec git-server manage-repo create alice/myapp.git

# Manually delete a repo
docker exec git-server manage-repo delete alice/myapp.git

# Inspect current authorized_keys
docker exec git-server cat /home/git/.ssh/authorized_keys

# Check what key files the microservice has written
docker exec git-server ls /git-server/keys/

# Tail git HTTP logs
docker exec git-server tail -f /var/log/apache2/git-access.log
docker exec git-server tail -f /var/log/apache2/git-error.log
```

---

## Environment variables reference

| Variable | Default | Description |
|----------|---------|-------------|
| `MICROSERVICE_URL` | — | **Required.** Base URL of the microservice. Used by `git-auth` for SSH permission checks. |
| `MICROSERVICE_AUTH_TOKEN` | — | **Required.** Shared secret for `/internal/ssh-access`. |
| `REPOS_DIR` | `/git-server/repos` | Root directory for all bare repos. |
| `KEYS_DIR` | `/git-server/keys` | Directory watched for SSH key files. |
| `SSH_KEYS_DIR` | `/git-server/ssh-host-keys` | Persists SSH host keys so clients don't see "host key changed" on restart. |
| `AUTO_CREATE_BARE_REPO` | `false` | If `true`, creates `DEFAULT_BARE_REPO` on startup if it doesn't exist. |
| `DEFAULT_BARE_REPO` | — | Repo path to auto-create (e.g. `alice/service.git`). Requires `AUTO_CREATE_BARE_REPO=true`. |
