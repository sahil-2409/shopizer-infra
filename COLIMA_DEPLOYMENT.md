# Shopizer — Colima Local Deployment Guide

> From CI artifact (zip) to running app on your Mac using Colima.

---

## End-to-End Flow

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                          GITHUB ACTIONS (CI)                                │
│                                                                             │
│  PR → Build → Test → Docker Build → Save .tar → Upload Artifact            │
│                                                                             │
│  Artifact: shopizer-<sha>.zip                                               │
│  Contains: shopizer-image.tar                                               │
└──────────────────────────────────┬──────────────────────────────────────────┘
                                   │
                                   │  Download from GitHub Actions UI
                                   │  or: gh run download <run-id>
                                   │
                                   ▼
┌─────────────────────────────────────────────────────────────────────────────┐
│                            YOUR MAC                                         │
│                                                                             │
│  ~/Downloads/shopizer-<sha>.zip                                             │
│                                                                             │
│  ┌───────────────────────────────────────────────────────────────────────┐  │
│  │  Step 1: Unzip                                                        │  │
│  │  $ unzip shopizer-<sha>.zip                                           │  │
│  │                                                                       │  │
│  │  Result: shopizer-image.tar                                           │  │
│  └───────────────────────────────────────────────────────────────────────┘  │
│                                   │                                         │
│                                   ▼                                         │
│  ┌───────────────────────────────────────────────────────────────────────┐  │
│  │                        Colima VM (Linux)                              │  │
│  │                                                                       │  │
│  │  ┌───────────────────────────────────────────────────────────────┐    │  │
│  │  │                     Docker Engine                             │    │  │
│  │  │                                                               │    │  │
│  │  │  Step 2: Load image                                           │    │  │
│  │  │  $ docker load -i shopizer-image.tar                          │    │  │
│  │  │                                                               │    │  │
│  │  │  ┌─────────────────────────────────────────────────────┐      │    │  │
│  │  │  │  Docker Image                                       │      │    │  │
│  │  │  │  shopizer:<sha>                                     │      │    │  │
│  │  │  │  ~200MB (Java 11 + Spring Boot + App)               │      │    │  │
│  │  │  └─────────────────────┬───────────────────────────────┘      │    │  │
│  │  │                        │                                      │    │  │
│  │  │  Step 3: Run           │                                      │    │  │
│  │  │  $ docker run -d       ▼                                      │    │  │
│  │  │    -p 8080:8080                                               │    │  │
│  │  │    --name shopizer                                            │    │  │
│  │  │    shopizer:<sha>                                             │    │  │
│  │  │                                                               │    │  │
│  │  │  ┌─────────────────────────────────────────────────────┐      │    │  │
│  │  │  │  Running Container                                  │      │    │  │
│  │  │  │                                                     │      │    │  │
│  │  │  │  ┌──────────────┐  ┌─────────────┐                 │      │    │  │
│  │  │  │  │ Spring Boot  │  │  H2 DB      │                 │      │    │  │
│  │  │  │  │ App Server   │─▶│  (embedded) │                 │      │    │  │
│  │  │  │  │ :8080        │  │             │                 │      │    │  │
│  │  │  │  └──────┬───────┘  └─────────────┘                 │      │    │  │
│  │  │  │         │                                           │      │    │  │
│  │  │  └─────────┼───────────────────────────────────────────┘      │    │  │
│  │  │            │                                                  │    │  │
│  │  └────────────┼──────────────────────────────────────────────────┘    │  │
│  │               │  Port forwarded: VM 8080 → Host 8080                 │  │
│  └───────────────┼──────────────────────────────────────────────────────┘  │
│                  │                                                         │
│                  ▼                                                         │
│       http://localhost:8080/swagger-ui.html  ✅                            │
└─────────────────────────────────────────────────────────────────────────────┘
```

---

## Quick Start

```bash
# One-time setup
brew install colima docker
colima start

# Deploy
unzip shopizer-<sha>.zip
docker load -i shopizer-image.tar
docker run -d -p 8080:8080 --name shopizer shopizer:<sha>

# Verify
curl -s -o /dev/null -w "%{http_code}" http://localhost:8080/swagger-ui.html
# Expected: 200
```

---

## Update to a New Version

```bash
# Stop old version
docker stop shopizer && docker rm shopizer

# Load and run new version
unzip shopizer-<new-sha>.zip
docker load -i shopizer-image.tar
docker run -d -p 8080:8080 --name shopizer shopizer:<new-sha>
```

---

## Troubleshooting

```bash
# Colima not running?
colima status
colima start

# Container won't start?
docker logs shopizer

# Port already in use?
docker ps                          # check what's using 8080
docker stop <container-id>         # stop it

# Clean up old images
docker image prune -a
```
