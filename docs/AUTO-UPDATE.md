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

## Sichtbarkeit

Repo ist **öffentlich**: https://github.com/cytracon/tilix  
→ `tilix-update` braucht **keinen Token**.

Optional Token nur gegen API-Rate-Limits (60/h unauth) bzw. zum **Publishen**:

| Ort | Verwendung |
|-----|------------|
| `~/.config/tilix/github-token` | optional (chmod 600) |
| `$GITHUB_TOKEN` / `$GH_TOKEN` | Env override |

**Publish** (write): Contents: **Read and write** (oder classic `repo` / `gh` login)

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
# Updater aus Clone / Drive / nach erstem Install:
./scripts/tilix-update.sh
./scripts/tilix-update.sh --install-timer   # täglich
# kein Token nötig (public repo)
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
| `403` / rate limit | kurz warten oder optional Token setzen; Release noch nie published |
| Nach Update alte Version | `pkill -x tilix` und neu starten (Dock hält alten Inode) |
| `tilix` ist Distro-Binary | `~/.local/bin` vor `/usr/bin` in `PATH` |
| CI Build fail | LDC/gtk deps — lokal `publish-github-release.sh` nutzen |

## Sicherheit

- Token **nie** committen
- Fine-grained PAT nur auf `cytracon/tilix` einschränken
- Release-Assets sind Signatur-frei (internes Repo); bei Bedarf später cosign/minisign ergänzen
