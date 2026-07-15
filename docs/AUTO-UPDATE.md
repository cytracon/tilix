# Cytracon Tilix — Auto-Update über GitHub

Ziel: **einmal bauen/publishen**, alle Rechner (Desktop, Laptop, Multimedia) holen sich das Binary selbst.

```
[Desktop / CI]
  dub build → package-tilix.sh → GitHub Release (tar.gz)
        │
        ▼
[Jeder PC]  tilix-update  (+ optional systemd --user Timer)
        │
        ▼
  ~/.local/libexec/tilix
```

## Komponenten

| Datei | Rolle |
|-------|--------|
| `scripts/package-tilix.sh` | Tarball bauen (Binary + Schema + Wrapper + Installer) |
| `scripts/publish-github-release.sh` | Tag + Release + Asset (vom Build-PC) |
| `scripts/tilix-update.sh` | Latest Release holen & nach `~/.local` installieren |
| `scripts/install-from-package.sh` | Installer im Tarball |
| `.github/workflows/release.yml` | CI: Tag `v*-cytracon.*` → Build + Release |

## Token (privat Repo)

| Ort | Verwendung |
|-----|------------|
| `~/.config/tilix/github-token` | **empfohlen** auf jedem PC (chmod 600) |
| `$GITHUB_TOKEN` / `$GH_TOKEN` | Env override |
| `/root/.github-token` | Fallback Desktop/Server |

**Update** (read): Fine-grained → Repository `cytracon/tilix` → Contents: **Read**  
**Publish** (write): Contents: **Read and write** (oder classic `repo`)

## Workflow

### A) Neue Version ausrollen (Desktop)

```bash
cd ~/src/tilix
# … code ändern, version in constants.d bumpen …
dub build --compiler=ldc2 --build=release
install -Dm755 tilix ~/.local/libexec/tilix
./scripts/publish-github-release.sh
```

Oder nur taggen und CI bauen lassen:

```bash
git tag -a v1.9.8-cytracon.10 -m "…"
git push origin master --tags
# Actions → Release Cytracon Package
```

### B) Andere PCs (einmalig)

```bash
mkdir -p ~/.config/tilix && chmod 700 ~/.config/tilix
echo 'TOKEN' > ~/.config/tilix/github-token && chmod 600 ~/.config/tilix/github-token

# Updater aus Clone oder per scp:
./scripts/tilix-update.sh
./scripts/tilix-update.sh --install-timer   # täglich
```

### C) Täglich automatisch

```bash
tilix-update --install-timer
systemctl --user list-timers | grep tilix
```

## LAN ohne GitHub

Wenn Laptops offline / kein Token:

```bash
./scripts/deploy-tilix-cytracon-home.sh
```

## Troubleshooting

| Symptom | Fix |
|---------|-----|
| `403` / kein latest Release | Token fehlt oder Contents:Read; Release noch nie published |
| Nach Update alte Version | `pkill -x tilix` und neu starten (Dock hält alten Inode) |
| `tilix` ist Distro-Binary | `~/.local/bin` vor `/usr/bin` in `PATH` |
| CI Build fail | LDC/gtk deps — lokal `publish-github-release.sh` nutzen |

## Sicherheit

- Token **nie** committen
- Fine-grained PAT nur auf `cytracon/tilix` einschränken
- Release-Assets sind Signatur-frei (internes Repo); bei Bedarf später cosign/minisign ergänzen
