#!/usr/bin/env bash
set -euo pipefail

#######################################################################
# Shopizer Deploy — Pull CI-built images from Docker Hub & run on Colima
#
# The CircleCI pipelines for all 3 repos push their final Docker images
# to Docker Hub. This script pulls those pre-built images and deploys
# them locally on Colima.
#
# Prerequisites: colima (running), docker CLI
# Usage:         ./build-and-deploy.sh
#######################################################################

SHOPIZER_IMAGE="${SHOPIZER_IMAGE:-shopizerecomm/shopizer:3.2.7}"
ADMIN_IMAGE="${ADMIN_IMAGE:-shopizerecomm/shopizer-admin:latest}"
REACT_IMAGE="${REACT_IMAGE:-shopizerecomm/shopizer-shop-reactjs:latest}"
PLATFORM="linux/amd64"
NETWORK="shopizer-net"

CYAN='\033[0;36m'; GREEN='\033[0;32m'; RED='\033[0;31m'; NC='\033[0m'

log()  { echo -e "${GREEN}[INFO]${NC}  $*"; }
err()  { echo -e "${RED}[ERROR]${NC} $*" >&2; }

# ── Pull with percentage progress ──────────────────────────────────
pull_with_progress() {
  local label="$1" image="$2"
  local logfile
  logfile=$(mktemp)

  printf "  ${CYAN}%-28s${NC} pulling...\r" "$label"

  # Pull in background, tee output to logfile
  docker pull --platform "$PLATFORM" "$image" > "$logfile" 2>&1 &
  local pid=$!

  while kill -0 "$pid" 2>/dev/null; do
    local total done_count pct
    total=$(grep -cE 'Pulling fs layer|Already exists|Pull complete' "$logfile" 2>/dev/null || true)
    total=${total:-0}; total=$(echo "$total" | tail -1)
    done_count=$(grep -cE 'Already exists|Pull complete' "$logfile" 2>/dev/null || true)
    done_count=${done_count:-0}; done_count=$(echo "$done_count" | tail -1)

    if [ "$total" -gt 0 ] 2>/dev/null; then
      pct=$(( done_count * 100 / total ))
      local filled=$(( pct / 2 ))
      local empty=$(( 50 - filled ))
      local bar="" space=""
      for ((i=0; i<filled; i++)); do bar+="█"; done
      for ((i=0; i<empty; i++)); do space+="░"; done
      printf "\r  ${CYAN}%-28s %s%s %3d%%${NC}" "$label" "$bar" "$space" "$pct"
    fi
    sleep 0.5
  done

  wait "$pid"
  local rc=$?

  if [ $rc -eq 0 ]; then
    local bar=""
    for ((i=0; i<50; i++)); do bar+="█"; done
    printf "\r  ${GREEN}%-28s %s %3d%%${NC}\n" "$label ✓" "$bar" 100
  else
    printf "\r  ${RED}%-28s FAILED${NC}\n" "$label"
    cat "$logfile"
    rm -f "$logfile"
    return 1
  fi
  rm -f "$logfile"
}

# ── Pre-flight ─────────────────────────────────────────────────────
preflight() {
  if ! command -v docker &>/dev/null; then
    err "docker CLI not found. Install Docker or Colima first."
    exit 1
  fi
  if ! docker info &>/dev/null; then
    err "Docker daemon not reachable. Start Colima first: colima start"
    exit 1
  fi
  log "Docker (Colima) is reachable ✓"
}

# ── Cleanup existing containers ────────────────────────────────────
cleanup() {
  log "Removing existing shopizer containers..."
  for name in shopizer shopizer-admin shopizer-react; do
    docker rm -f "$name" 2>/dev/null || true
  done
}

# ── Pull all CI-built images ───────────────────────────────────────
pull_images() {
  log "═══ Downloading CI-built images from Docker Hub ═══"
  echo "  (images are amd64, using emulation on Apple Silicon)"
  echo ""
  pull_with_progress "shopizer (backend)"    "$SHOPIZER_IMAGE"
  pull_with_progress "shopizer-admin"        "$ADMIN_IMAGE"
  pull_with_progress "shopizer-shop-reactjs" "$REACT_IMAGE"
  echo ""
  log "All images downloaded ✓"
}

# ── Deploy ─────────────────────────────────────────────────────────
deploy() {
  log "═══ Deploying to Colima Docker ═══"

  docker network create "$NETWORK" 2>/dev/null || true

  docker run -d --name shopizer --network "$NETWORK" \
    --platform "$PLATFORM" \
    -e "SPRING_PROFILES_ACTIVE=docker" \
    -e "mailSender.protocol=smtp" \
    -e "mailSender.host=localhost" \
    -e "mailSender.port=25" \
    -e "mailSender.username=test" \
    -e "mailSender.password=test" \
    -e "mailSender.auth=false" \
    -e "mailSender.starttls.enable=false" \
    -p 8080:8080 \
    "$SHOPIZER_IMAGE"
  log "Started shopizer backend → http://localhost:8080"

  docker run -d --name shopizer-admin --network "$NETWORK" \
    --platform "$PLATFORM" \
    -e "APP_BASE_URL=http://shopizer:8080/api" \
    -p 82:80 \
    "$ADMIN_IMAGE"
  log "Started shopizer-admin  → http://localhost:82"

  docker run -d --name shopizer-react --network "$NETWORK" \
    --platform "$PLATFORM" \
    -e "APP_MERCHANT=DEFAULT" \
    -e "APP_BASE_URL=http://shopizer:8080" \
    -p 80:80 \
    "$REACT_IMAGE"
  log "Started shopizer-react  → http://localhost:80"

  echo ""
  log "═══ All services running ═══"
  echo ""
  echo "  Backend API:   http://localhost:8080/swagger-ui.html"
  echo "  Admin Panel:   http://localhost:82    (admin@shopizer.com / password)"
  echo "  React Shop:    http://localhost:80"
  echo ""
  docker ps --filter "network=$NETWORK" --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"
}

# ── Main ───────────────────────────────────────────────────────────
main() {
  preflight
  cleanup
  pull_images
  deploy
}

main "$@"
