# Git Server Docker (SSH + HTTP)

Este contenedor expone Git por:

- SSH (puerto 22 interno)
- HTTP Smart Git (puerto 80 interno)

## 1. Construir imagen

```bash
docker build -t git-ssh-http-server:latest .
```

## 2. Setup minimo de carpetas y llaves SSH

Linux/macOS/WSL:

```bash
mkdir -p ./git-server/keys ./git-server/repos ./git-server/http
ssh-keygen -t ed25519 -f ~/.ssh/id_ed25519 -N "" -C "git-server-client"
cp ~/.ssh/id_ed25519.pub ./git-server/keys/
```

Windows PowerShell:

```powershell
New-Item -ItemType Directory -Force -Path .\git-server\keys | Out-Null
New-Item -ItemType Directory -Force -Path .\git-server\repos | Out-Null
New-Item -ItemType Directory -Force -Path .\git-server\http | Out-Null
ssh-keygen -t ed25519 -f $env:USERPROFILE\.ssh\id_ed25519 -N "" -C "git-server-client"
Copy-Item $env:USERPROFILE\.ssh\id_ed25519.pub .\git-server\keys\ -Force
```

## 3. Correr en local (simple)

Este modo deja HTTP abierto para pruebas locales (clone/pull/push por HTTP sin auth).

Linux/macOS/WSL:

```bash
docker run -d --name git-server \
  -p 2222:22 \
  -p 8080:80 \
  -e DEFAULT_BARE_REPO=proyecto.git \
  -e HTTP_AUTH_REQUIRED=false \
  -e HTTP_PUSH_AUTH_REQUIRED=false \
  -v "$(pwd)/git-server/keys:/git-server/keys" \
  -v "$(pwd)/git-server/repos:/git-server/repos" \
  -v "$(pwd)/git-server/http:/git-server/http" \
  git-ssh-http-server:latest
```

Git Bash en Windows:

```bash
MSYS_NO_PATHCONV=1 docker run -d --name git-server \
  -p 2222:22 \
  -p 8080:80 \
  -e DEFAULT_BARE_REPO=proyecto.git \
  -e HTTP_AUTH_REQUIRED=false \
  -e HTTP_PUSH_AUTH_REQUIRED=false \
  -v "$(pwd)/git-server/keys:/git-server/keys" \
  -v "$(pwd)/git-server/repos:/git-server/repos" \
  -v "$(pwd)/git-server/http:/git-server/http" \
  git-ssh-http-server:latest
```

PowerShell:

```powershell
docker run -d --name git-server `
  -p 2222:22 `
  -p 8080:80 `
  -e DEFAULT_BARE_REPO=proyecto.git `
  -e HTTP_AUTH_REQUIRED=false `
  -e HTTP_PUSH_AUTH_REQUIRED=false `
  -v "${PWD}/git-server/keys:/git-server/keys" `
  -v "${PWD}/git-server/repos:/git-server/repos" `
  -v "${PWD}/git-server/http:/git-server/http" `
  git-ssh-http-server:latest
```

## 4. Correr para produccion (recomendado)

Activa auth HTTP basica. Para SSH ya se usa llave publica.

```bash
docker run -d --name git-server \
  -p 2222:22 \
  -p 8080:80 \
  -e DEFAULT_BARE_REPO=proyecto.git \
  -e HTTP_AUTH_REQUIRED=true \
  -e HTTP_USER=gitadmin \
  -e HTTP_PASSWORD='cambia-esto-ya' \
  -v "$(pwd)/git-server/keys:/git-server/keys" \
  -v "$(pwd)/git-server/repos:/git-server/repos" \
  -v "$(pwd)/git-server/http:/git-server/http" \
  git-ssh-http-server:latest
```

En produccion real, coloca HTTPS delante (Nginx/ALB/Traefik) y no expongas HTTP plano a internet.

## 5. Crear un repo

```bash
docker exec -it git-server su -s /bin/bash git -c "git init --bare --initial-branch=main /git-server/repos/equipo-api.git"
docker exec -it git-server ls -la /git-server/repos
```

## 6. Usar el repo por SSH y HTTP

### 6.1 Clone

SSH:

```bash
git clone ssh://git@localhost:2222/git-server/repos/equipo-api.git
```

HTTP:

```bash
git clone http://localhost:8080/git/equipo-api.git
```

Si HTTP auth esta activa:

```bash
git clone http://gitadmin@localhost:8080/git/equipo-api.git
```

### 6.2 Push

```bash
cd equipo-api
git checkout -b main
echo "hola" > README.md
git add README.md
git commit -m "primer commit"
git push -u origin main
```

### 6.3 Pull

```bash
git pull origin main
```
