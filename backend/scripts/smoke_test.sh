#!/usr/bin/env bash
set -euo pipefail

BASE_URL="${BACKEND_URL:-http://localhost:8000}"

require_cmd() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "Missing required command: $1" >&2
    exit 1
  fi
}

require_cmd curl

pretty_print() {
  local body="$1"
  if command -v jq >/dev/null 2>&1; then
    echo "$body" | jq .
  else
    echo "$body"
  fi
}

call_get() {
  local path="$1"
  local label="$2"
  local response
  response="$(curl -sS -w '\n%{http_code}' "${BASE_URL}${path}")"
  local body
  body="$(echo "$response" | sed '$d')"
  local code
  code="$(echo "$response" | tail -n1)"

  echo ""
  echo "=== ${label} (${path}) ==="
  if [ "$code" != "200" ]; then
    echo "FAILED: HTTP ${code}" >&2
    echo "$body" >&2
    exit 1
  fi
  pretty_print "$body"
}

call_post() {
  local path="$1"
  local label="$2"
  local payload="$3"
  local response
  response="$(curl -sS -w '\n%{http_code}' -H 'Content-Type: application/json' -d "$payload" "${BASE_URL}${path}")"
  local body
  body="$(echo "$response" | sed '$d')"
  local code
  code="$(echo "$response" | tail -n1)"

  echo ""
  echo "=== ${label} (${path}) ==="
  if [ "$code" != "200" ]; then
    echo "FAILED: HTTP ${code}" >&2
    echo "$body" >&2
    exit 1
  fi
  pretty_print "$body"
}

call_get "/health" "Health Check"

call_post "/solve/transport" "Transport" '{
  "forests": [
    {"name": "Pine", "capacity": 40, "regen_rate": 0.8, "position": [100, 200], "current_stock": 12},
    {"name": "Oak", "capacity": 35, "regen_rate": 0.7, "position": [400, 300]}
  ],
  "factory_position": [900, 500],
  "trucks": [
    {"type": "Small", "speed": 300, "capacity": 2},
    {"type": "Large", "speed": 120, "capacity": 8}
  ],
  "time_remaining": 180
}'

call_post "/solve/machine_placement" "Machine Placement" '{
  "budget": 1000,
  "time_remaining": 180,
  "corpse_count": 6
}'

call_post "/solve/packing" "Packing" '{
  "crate_size": [6, 6],
  "items": [
    {"id": 1, "type": "Chair", "w": 2, "h": 2},
    {"id": 2, "type": "Table", "w": 3, "h": 2},
    {"id": 3, "type": "Stool", "w": 1, "h": 1},
    {"id": 4, "type": "Shelf", "w": 3, "h": 1}
  ],
  "time_remaining": 180,
  "budget_remaining": 600,
  "packaging_cost_per_crate": 50
}'

call_post "/solve/tsp" "TSP" '{
  "depot": [100, 100],
  "shops": [
    {"name": "Market", "position": [500, 200], "demand": 3},
    {"name": "Boutique", "position": [800, 250], "demand": 2},
    {"name": "Office", "position": [600, 600], "demand": 2}
  ],
  "truck_capacity": 10,
  "available_crates": 6,
  "depot_restock_rate": 1.0,
  "truck_speed": 200,
  "time_remaining": 180
}'

call_post "/solve/full" "Full Solve" '{
  "budget": 1000,
  "transport_forests": [
    {"name": "Pine", "capacity": 5000, "regen_rate": 3.0, "position": [120, 220], "current_stock": 18},
    {"name": "Oak", "capacity": 5000, "regen_rate": 100.0, "position": [380, 140], "current_stock": 10}
  ],
  "factory_position": [900, 500],
  "owned_trucks": {"Small": 1},
  "trucks": [
    {"type": "Medium", "speed": 200, "capacity": 4, "cost": 150},
    {"type": "Large", "speed": 200, "capacity": 8, "cost": 250}
  ],
  "crate_size": [6, 6],
  "items": [
    {"id": 0, "type": "Chair", "w": 5, "h": 1},
    {"id": 1, "type": "Table", "w": 5, "h": 2},
    {"id": 2, "type": "Shelf", "w": 4, "h": 3}
  ],
  "depot": [100, 100],
  "shops": [
    {"name": "Market", "position": [500, 200], "demand": 3},
    {"name": "Boutique", "position": [800, 250], "demand": 2},
    {"name": "Office", "position": [600, 600], "demand": 2}
  ],
  "truck_capacity": 10,
  "time_remaining": 180,
  "truck_speed": 200,
  "packaging_cost_per_crate": 50,
  "item_arrival_interval": 2.0
}'

echo ""
echo "Smoke test completed successfully against ${BASE_URL}"
