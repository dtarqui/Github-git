# Git Server Docker (Git + SSH)

Este README solo cubre:
- como correr el Docker
- setup minimo para autenticar por SSH
- ejemplo de clone, push y pull

## 1. Construir la imagen

```bash
docker build -t git-ssh-server:latest .
```

## 2. Setup minimo de llaves y carpetas

### Linux / macOS / WSL

```bash
mkdir -p ./git-server/keys ./git-server/repos
ssh-keygen -t ed25519 -f ~/.ssh/id_ed25519 -N "" -C "git-server-client"
cp ~/.ssh/id_ed25519.pub ./git-server/keys/
```

### Windows PowerShell

```powershell
New-Item -ItemType Directory -Force -Path .\git-server\keys | Out-Null
New-Item -ItemType Directory -Force -Path .\git-server\repos | Out-Null
ssh-keygen -t ed25519 -f $env:USERPROFILE\.ssh\id_ed25519 -N "" -C "git-server-client"
Copy-Item $env:USERPROFILE\.ssh\id_ed25519.pub .\git-server\keys\ -Force
```

## 3. Correr el contenedor (2222:22)

### Linux / macOS / WSL

```bash
docker run -d --name git-server \
  -p 2222:22 \
  -e DEFAULT_BARE_REPO=proyecto.git \
  -v "$(pwd)/git-server/keys:/git-server/keys" \
  -v "$(pwd)/git-server/repos:/git-server/repos" \
  git-ssh-server:latest
```

### Git Bash en Windows

```bash
MSYS_NO_PATHCONV=1 docker run -d --name git-server \
  -p 2222:22 \
  -e DEFAULT_BARE_REPO=proyecto.git \
  -v "$(pwd)/git-server/keys:/git-server/keys" \
  -v "$(pwd)/git-server/repos:/git-server/repos" \
  git-ssh-server:latest
```

### Windows PowerShell

```powershell
docker run -d --name git-server `
  -p 2222:22 `
  -e DEFAULT_BARE_REPO=proyecto.git `
  -v "${PWD}/git-server/keys:/git-server/keys" `
  -v "${PWD}/git-server/repos:/git-server/repos" `
  git-ssh-server:latest
```

## 4. Crear un repo en el server

Ejemplo: crear `equipo-api.git` dentro del contenedor.

```bash
docker exec -it git-server su -s /bin/bash git -c "git init --bare --initial-branch=main /git-server/repos/equipo-api.git"
```

Verificar repos disponibles:

```bash
docker exec -it git-server ls -la /git-server/repos
```

## 5. Ejemplo completo de ese repo: clone, push y pull

### 5.1 Clonar

```bash
git clone ssh://git@localhost:2222/git-server/repos/equipo-api.git
cd equipo-api
```

### 5.2 Crear cambios y hacer push

```bash
git checkout -b main
echo "hola" > README.md
git add README.md
git commit -m "primer commit"
git push -u origin main
```

### 5.3 Hacer pull

```bash
git pull origin main
```
