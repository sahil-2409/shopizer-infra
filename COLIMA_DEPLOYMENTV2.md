# Shopizer Colima Deployment Architecture

## Overview
This document describes the architecture for deploying Shopizer e-commerce suite on Colima (lightweight Docker runtime for macOS).

---

## High-Level Architecture

```
┌─────────────────────────────────────────────────────────────────────┐
│                          macOS Host System                          │
│                                                                     │
│  ┌───────────────────────────────────────────────────────────────┐ │
│  │                    Colima VM (Lima)                           │ │
│  │                  (4 CPU, 8GB RAM, 50GB Disk)                  │ │
│  │                                                               │ │
│  │  ┌─────────────────────────────────────────────────────┐     │ │
│  │  │              Docker Engine (containerd)             │     │ │
│  │  │                                                     │     │ │
│  │  │  ┌──────────────┐  ┌──────────────┐  ┌──────────┐ │     │ │
│  │  │  │   MySQL      │  │   Backend    │  │  Admin   │ │     │ │
│  │  │  │  Container   │  │  Container   │  │Container │ │     │ │
│  │  │  │              │  │              │  │          │ │     │ │
│  │  │  │  Port: 3306  │  │  Port: 8080  │  │Port: 4200│ │     │ │
│  │  │  └──────┬───────┘  └──────┬───────┘  └────┬─────┘ │     │ │
│  │  │         │                 │                │       │     │ │
│  │  │         └─────────────────┴────────────────┘       │     │ │
│  │  │                   Docker Network                   │     │ │
│  │  │                  (shopizer-network)                │     │ │
│  │  └─────────────────────────────────────────────────────┘     │ │
│  │                           │                                   │ │
│  └───────────────────────────┼───────────────────────────────────┘ │
│                              │                                     │
│                    Port Forwarding (Lima)                         │
│                              │                                     │
└──────────────────────────────┼─────────────────────────────────────┘
                               │
                    ┌──────────┴──────────┐
                    │   localhost:8080    │ ← Backend API
                    │   localhost:4200    │ ← Admin UI
                    │   localhost:3306    │ ← MySQL
                    └─────────────────────┘
```

---

## Component Architecture

### 1. MySQL Database Container
```
┌─────────────────────────────────┐
│      MySQL 8.0 Container        │
├─────────────────────────────────┤
│  Image: mysql:8.0               │
│  Port: 3306                     │
│  Volume: mysql-data             │
│                                 │
│  Environment:                   │
│  - MYSQL_ROOT_PASSWORD          │
│  - MYSQL_DATABASE: SALESMANAGER │
│  - MYSQL_USER: shopizer         │
│                                 │
│  Health Check:                  │
│  - mysqladmin ping              │
│  - Interval: 10s                │
└─────────────────────────────────┘
```

### 2. Backend Container (Spring Boot)
```
┌─────────────────────────────────┐
│   Shopizer Backend Container    │
├─────────────────────────────────┤
│  Image: shopizerecomm/shopizer  │
│  Port: 8080                     │
│  Base: adoptopenjdk11-alpine    │
│                                 │
│  Dependencies:                  │
│  - MySQL (wait-for-it)          │
│                                 │
│  Environment:                   │
│  - SPRING_DATASOURCE_URL        │
│  - SPRING_DATASOURCE_USERNAME   │
│  - SPRING_DATASOURCE_PASSWORD   │
│                                 │
│  Health Check:                  │
│  - /actuator/health             │
│  - Interval: 30s                │
└─────────────────────────────────┘
```

### 3. Admin Container (Angular)
```
┌─────────────────────────────────┐
│   Shopizer Admin Container      │
├─────────────────────────────────┤
│  Image: shopizer-admin          │
│  Port: 4200                     │
│  Base: node:14-alpine + nginx   │
│                                 │
│  Dependencies:                  │
│  - Backend API                  │
│                                 │
│  Environment:                   │
│  - API_BASE_URL                 │
│                                 │
│  Health Check:                  │
│  - HTTP GET /                   │
│  - Interval: 30s                │
└─────────────────────────────────┘
```

---

## CI/CD Pipeline Flow

```
┌──────────────────────────────────────────────────────────────────────┐
│                         GitHub Actions CI/CD                         │
└──────────────────────────────────────────────────────────────────────┘
                                  │
                    ┌─────────────┴─────────────┐
                    │                           │
            ┌───────▼────────┐         ┌────────▼────────┐
            │   Build & Test │         │  Security Scan  │
            │                │         │                 │
            │  - Maven Build │         │  - OWASP Check  │
            │  - Unit Tests  │         │  - Dependency   │
            │  - JaCoCo      │         │    Audit        │
            └───────┬────────┘         └────────┬────────┘
                    │                           │
                    └─────────────┬─────────────┘
                                  │
                         ┌────────▼─────────┐
                         │  Docker Build    │
                         │                  │
                         │  DOCKER_BUILDKIT │
                         │  = 0 (legacy)    │
                         └────────┬─────────┘
                                  │
                    ┌─────────────┴─────────────┐
                    │                           │
            ┌───────▼────────┐         ┌────────▼────────┐
            │  Push to       │         │  Save as        │
            │  Docker Hub    │         │  Artifact       │
            └───────┬────────┘         └────────┬────────┘
                    │                           │
                    │                           │
                    └─────────────┬─────────────┘
                                  │
                         ┌────────▼─────────┐
                         │   Local Deploy   │
                         │   (Manual)       │
                         └──────────────────┘
```

---

## Deployment Flow (Artifact-Based)

```
Step 1: Download Artifact
┌─────────────────────────┐
│  GitHub Actions         │
│  Artifact Storage       │
│                         │
│  backend-docker-image   │
│  (shopizer-backend-     │
│   image.tar.gz)         │
└───────────┬─────────────┘
            │
            │ gh run download
            ▼
┌─────────────────────────┐
│  Local macOS            │
│  ~/Downloads/           │
└───────────┬─────────────┘


Step 2: Load into Colima
            │
            │ gunzip -c | docker load
            ▼
┌─────────────────────────┐
│  Colima Docker Engine   │
│                         │
│  Image:                 │
│  shopizerecomm/shopizer │
└───────────┬─────────────┘


Step 3: Deploy with Compose
            │
            │ docker compose up -d
            ▼
┌─────────────────────────┐
│  Running Containers     │
│                         │
│  - MySQL                │
│  - Backend              │
│  - Admin                │
└─────────────────────────┘
```

---

## Deployment Flow (Docker Hub)

```
Step 1: CI Pipeline Push
┌─────────────────────────┐
│  GitHub Actions         │
│  Docker Build           │
└───────────┬─────────────┘
            │
            │ docker push
            ▼
┌─────────────────────────┐
│  Docker Hub Registry    │
│                         │
│  shopizerecomm/shopizer │
└───────────┬─────────────┘


Step 2: Pull to Colima
            │
            │ docker pull
            ▼
┌─────────────────────────┐
│  Colima Docker Engine   │
│                         │
│  Image:                 │
│  shopizerecomm/shopizer │
└───────────┬─────────────┘


Step 3: Deploy with Compose
            │
            │ docker compose up -d
            ▼
┌─────────────────────────┐
│  Running Containers     │
│                         │
│  - MySQL                │
│  - Backend              │
│  - Admin                │
└─────────────────────────┘
```

---

## Network Architecture

```
┌────────────────────────────────────────────────────────────┐
│                    Docker Bridge Network                   │
│                     (shopizer-network)                     │
│                                                            │
│  ┌──────────────┐      ┌──────────────┐      ┌─────────┐ │
│  │   MySQL      │◄─────┤   Backend    │◄─────┤  Admin  │ │
│  │              │      │              │      │         │ │
│  │  mysql:3306  │      │  backend:8080│      │ :4200   │ │
│  └──────┬───────┘      └──────┬───────┘      └────┬────┘ │
│         │                     │                   │       │
└─────────┼─────────────────────┼───────────────────┼───────┘
          │                     │                   │
          │ Port Mapping        │ Port Mapping      │ Port Mapping
          │ 3306:3306           │ 8080:8080         │ 4200:4200
          │                     │                   │
          └─────────────────────┴───────────────────┘
                                │
                    ┌───────────▼───────────┐
                    │   macOS Host          │
                    │   localhost           │
                    └───────────────────────┘
```

---

## Data Persistence

```
┌─────────────────────────────────────────────────────────┐
│                  Docker Volumes                         │
└─────────────────────────────────────────────────────────┘
                          │
        ┌─────────────────┴─────────────────┐
        │                                   │
┌───────▼────────┐                 ┌────────▼────────┐
│  mysql-data    │                 │  backend-files  │
│                │                 │                 │
│  /var/lib/mysql│                 │  /files         │
│                │                 │                 │
│  Persistent    │                 │  Product Images │
│  Database      │                 │  Uploads        │
└────────────────┘                 └─────────────────┘
        │                                   │
        │                                   │
        ▼                                   ▼
┌─────────────────────────────────────────────────────────┐
│         Colima VM Disk Storage (50GB)                   │
│         ~/.colima/_lima/colima/                         │
└─────────────────────────────────────────────────────────┘
```

---

## Resource Allocation

```
┌──────────────────────────────────────────────────────────┐
│              Colima VM Resources                         │
│              Total: 4 CPU, 8GB RAM, 50GB Disk            │
└──────────────────────────────────────────────────────────┘
                          │
        ┌─────────────────┼─────────────────┐
        │                 │                 │
┌───────▼────────┐ ┌──────▼──────┐ ┌────────▼────────┐
│  MySQL         │ │  Backend    │ │  Admin          │
│                │ │             │ │                 │
│  CPU: 1 core   │ │  CPU: 2 core│ │  CPU: 0.5 core  │
│  RAM: 2GB      │ │  RAM: 4GB   │ │  RAM: 1GB       │
│  Disk: 10GB    │ │  Disk: 5GB  │ │  Disk: 2GB      │
└────────────────┘ └─────────────┘ └─────────────────┘
```

---

## Deployment Scripts

### Script Flow
```
deploy-artifact-colima.sh
         │
         ├─► Check Colima Status
         │
         ├─► Load Docker Image
         │   (gunzip -c | docker load)
         │
         ├─► Start MySQL Container
         │   (docker compose up -d mysql)
         │
         ├─► Wait for MySQL Ready
         │   (health check loop)
         │
         ├─► Start Backend Container
         │   (docker compose up -d backend)
         │
         ├─► Wait for Backend Ready
         │   (curl /actuator/health)
         │
         ├─► Start Admin Container
         │   (docker compose up -d admin)
         │
         └─► Health Check All Services
             (verify endpoints)
```

---

## Health Check Flow

```
┌─────────────────────────────────────────────────────────┐
│                  Health Check System                    │
└─────────────────────────────────────────────────────────┘
                          │
        ┌─────────────────┼─────────────────┐
        │                 │                 │
┌───────▼────────┐ ┌──────▼──────┐ ┌────────▼────────┐
│  MySQL         │ │  Backend    │ │  Admin          │
│                │ │             │ │                 │
│  mysqladmin    │ │  /actuator/ │ │  HTTP GET /     │
│  ping          │ │  health     │ │                 │
│                │ │             │ │                 │
│  Every 10s     │ │  Every 30s  │ │  Every 30s      │
│  Retries: 5    │ │  Retries: 3 │ │  Retries: 3     │
└────────────────┘ └─────────────┘ └─────────────────┘
        │                 │                 │
        └─────────────────┴─────────────────┘
                          │
                          ▼
                ┌─────────────────┐
                │  All Healthy?   │
                │  ✅ Ready       │
                └─────────────────┘
```

---

## Backup & Rollback Strategy

```
┌─────────────────────────────────────────────────────────┐
│                    Backup Process                       │
└─────────────────────────────────────────────────────────┘
                          │
        ┌─────────────────┴─────────────────┐
        │                                   │
┌───────▼────────┐                 ┌────────▼────────┐
│  Database      │                 │  Docker Images  │
│  Backup        │                 │  Backup         │
│                │                 │                 │
│  mysqldump     │                 │  docker save    │
│  SALESMANAGER  │                 │  shopizer:tag   │
│                │                 │                 │
│  Daily @ 2 AM  │                 │  Before Deploy  │
└────────┬───────┘                 └────────┬────────┘
         │                                  │
         └──────────────┬───────────────────┘
                        │
                        ▼
         ┌──────────────────────────┐
         │  Backup Storage          │
         │  ~/backups/shopizer/     │
         │                          │
         │  - db_YYYYMMDD.sql.gz    │
         │  - image_YYYYMMDD.tar.gz │
         │                          │
         │  Retention: 7 days       │
         └──────────────────────────┘


┌─────────────────────────────────────────────────────────┐
│                   Rollback Process                      │
└─────────────────────────────────────────────────────────┘
                          │
        ┌─────────────────┴─────────────────┐
        │                                   │
┌───────▼────────┐                 ┌────────▼────────┐
│  Stop Current  │                 │  Load Previous  │
│  Containers    │                 │  Image          │
│                │                 │                 │
│  docker        │                 │  docker load    │
│  compose down  │                 │  backup.tar.gz  │
└────────┬───────┘                 └────────┬────────┘
         │                                  │
         └──────────────┬───────────────────┘
                        │
                        ▼
         ┌──────────────────────────┐
         │  Restore Database        │
         │  (if needed)             │
         │                          │
         │  mysql < backup.sql      │
         └──────────┬───────────────┘
                    │
                    ▼
         ┌──────────────────────────┐
         │  Start Previous Version  │
         │                          │
         │  docker compose up -d    │
         └──────────────────────────┘
```

---

## Monitoring & Logs

```
┌─────────────────────────────────────────────────────────┐
│                  Monitoring Stack                       │
└─────────────────────────────────────────────────────────┘
                          │
        ┌─────────────────┼─────────────────┐
        │                 │                 │
┌───────▼────────┐ ┌──────▼──────┐ ┌────────▼────────┐
│  Container     │ │  Application│ │  Resource       │
│  Logs          │ │  Metrics    │ │  Usage          │
│                │ │             │ │                 │
│  docker logs   │ │  /actuator/ │ │  docker stats   │
│  -f container  │ │  metrics    │ │                 │
│                │ │             │ │  CPU/RAM/Disk   │
└────────────────┘ └─────────────┘ └─────────────────┘
        │                 │                 │
        └─────────────────┴─────────────────┘
                          │
                          ▼
                ┌─────────────────┐
                │  Log Files      │
                │  /var/log/      │
                │  shopizer/      │
                └─────────────────┘
```

---

## Security Architecture

```
┌─────────────────────────────────────────────────────────┐
│                  Security Layers                        │
└─────────────────────────────────────────────────────────┘
                          │
        ┌─────────────────┼─────────────────┐
        │                 │                 │
┌───────▼────────┐ ┌──────▼──────┐ ┌────────▼────────┐
│  Network       │ │  Container  │ │  Application    │
│  Isolation     │ │  Security   │ │  Security       │
│                │ │             │ │                 │
│  - Bridge      │ │  - Non-root │ │  - OWASP Scan   │
│    Network     │ │    User     │ │  - Dependency   │
│  - Internal    │ │  - Read-only│ │    Audit        │
│    DNS         │ │    FS       │ │  - Secret Mgmt  │
│  - No External │ │  - Resource │ │                 │
│    Access      │ │    Limits   │ │                 │
└────────────────┘ └─────────────┘ └─────────────────┘
        │                 │                 │
        └─────────────────┴─────────────────┘
                          │
                          ▼
                ┌─────────────────┐
                │  Secrets        │
                │  Management     │
                │                 │
                │  - .env file    │
                │  - Git ignored  │
                │  - Encrypted    │
                └─────────────────┘
```

---

## Troubleshooting Flow

```
┌─────────────────────────────────────────────────────────┐
│              Deployment Issue?                          │
└─────────────────────────────────────────────────────────┘
                          │
                          ▼
                ┌─────────────────┐
                │  Check Colima   │
                │  Status         │
                │                 │
                │  colima status  │
                └────────┬────────┘
                         │
                    ┌────┴────┐
                    │ Running?│
                    └────┬────┘
                    No   │   Yes
                ┌────────┴────────┐
                │                 │
        ┌───────▼────────┐ ┌──────▼──────┐
        │  Start Colima  │ │  Check      │
        │                │ │  Containers │
        │  colima start  │ │             │
        └────────────────┘ │  docker ps  │
                           └──────┬──────┘
                                  │
                             ┌────┴────┐
                             │ Running?│
                             └────┬────┘
                             No   │   Yes
                         ┌────────┴────────┐
                         │                 │
                 ┌───────▼────────┐ ┌──────▼──────┐
                 │  Check Logs    │ │  Check      │
                 │                │ │  Health     │
                 │  docker logs   │ │             │
                 │  -f container  │ │  curl /     │
                 └────────┬───────┘ │  health     │
                          │         └──────┬──────┘
                          │                │
                          └────────┬───────┘
                                   │
                                   ▼
                         ┌─────────────────┐
                         │  Common Issues: │
                         │                 │
                         │  - Port conflict│
                         │  - DB not ready │
                         │  - Image corrupt│
                         │  - Network issue│
                         └─────────────────┘
```

---

## Performance Optimization

```
┌─────────────────────────────────────────────────────────┐
│              Optimization Strategies                    │
└─────────────────────────────────────────────────────────┘
                          │
        ┌─────────────────┼─────────────────┐
        │                 │                 │
┌───────▼────────┐ ┌──────▼──────┐ ┌────────▼────────┐
│  Image Size    │ │  Resource   │ │  Startup Time   │
│  Optimization  │ │  Tuning     │ │  Optimization   │
│                │ │             │ │                 │
│  - Multi-stage │ │  - CPU      │ │  - Lazy Init    │
│    Build       │ │    Limits   │ │  - Parallel     │
│  - Alpine Base │ │  - Memory   │ │    Start        │
│  - Layer Cache │ │    Limits   │ │  - Health Check │
│                │ │  - Disk I/O │ │    Tuning       │
└────────────────┘ └─────────────┘ └─────────────────┘
```

---

## Key Benefits of Colima

```
┌─────────────────────────────────────────────────────────┐
│              Colima vs Docker Desktop                   │
└─────────────────────────────────────────────────────────┘

Colima                          Docker Desktop
  │                                   │
  ├─► 75% Less RAM                    ├─► Higher RAM Usage
  ├─► 6x Faster Startup               ├─► Slower Startup
  ├─► Open Source (MIT)               ├─► Proprietary
  ├─► No License Required             ├─► License for Enterprise
  ├─► Lightweight VM                  ├─► Full VM
  └─► CLI-First                       └─► GUI-First
```

---

## Quick Commands Reference

### Colima Management
```bash
# Start Colima
colima start --cpu 4 --memory 8 --disk 50 --arch x86_64

# Stop Colima
colima stop

# Delete Colima
colima delete --force

# Check Status
colima status
```

### Deployment
```bash
# Deploy from artifact
./scripts/deploy-artifact-colima.sh shopizer-backend-image.tar.gz

# Deploy from Docker Hub
./scripts/deploy-dockerhub-colima.sh

# Check health
./scripts/health-check.sh
```

### Monitoring
```bash
# View logs
docker logs -f shopizer-backend

# Check resources
docker stats

# List containers
docker ps
```

### Backup & Restore
```bash
# Backup database
./scripts/backup.sh

# Rollback deployment
./scripts/rollback.sh v1.0.0
```

---

## Conclusion

This architecture provides:
- ✅ Lightweight deployment on macOS using Colima
- ✅ Containerized microservices with Docker Compose
- ✅ Automated CI/CD pipeline with GitHub Actions
- ✅ Health monitoring and auto-recovery
- ✅ Backup and rollback capabilities
- ✅ Resource optimization for local development
- ✅ Production-ready configuration

**Total Setup Time**: 2-3 hours  
**Resource Usage**: 4 CPU, 8GB RAM, 50GB Disk  
**Scalability**: Single server, suitable for development and small-scale production
