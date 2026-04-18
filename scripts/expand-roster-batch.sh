#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$repo_root"

roster_path="catalog/vehicle-roster.json"
helper_path="$(find dist-newstyle -type f -name discover-vehicle-roster | head -n 1)"

if [[ -z "${helper_path}" ]]; then
  echo "Could not locate the discover-vehicle-roster executable under dist-newstyle." >&2
  exit 1
fi

before_count="$(jq 'length' "$roster_path")"
batch_file="$(mktemp "${TMPDIR:-/tmp}/roster-batch.XXXXXX.json")"
merged_file="$(mktemp "${TMPDIR:-/tmp}/roster-merged.XXXXXX.json")"

cleanup() {
  rm -f "$batch_file" "$merged_file"
}
trap cleanup EXIT

printf '[]\n' > "$batch_file"

while IFS='|' read -r vehicle_year vehicle_make vehicle_model; do
  [[ -z "${vehicle_year}" ]] && continue
  echo "Discovering ${vehicle_year} ${vehicle_make} ${vehicle_model}..." >&2
  if ! discovered_rows="$("$helper_path" "$vehicle_year" "$vehicle_make" "$vehicle_model")"; then
    echo "Skipping ${vehicle_year} ${vehicle_make} ${vehicle_model} because discovery failed." >&2
    continue
  fi
  jq -s '.[0] + .[1]' "$batch_file" <(printf '%s\n' "$discovered_rows") > "${batch_file}.next"
  mv "${batch_file}.next" "$batch_file"
done <<'EOF'
2024|Toyota|4Runner 2WD
2024|Toyota|4Runner 4WD
2024|Toyota|Camry
2024|Toyota|Camry AWD LE/SE
2024|Toyota|Camry AWD XLE/XSE
2024|Toyota|Camry LE/SE
2024|Toyota|Camry XLE/XSE
2024|Toyota|Corolla Hatchback
2024|Toyota|Corolla Cross
2024|Toyota|Corolla Cross AWD
2024|Toyota|Corolla Cross Hybrid AWD
2024|Toyota|Crown AWD
2024|Toyota|Highlander
2024|Toyota|Highlander AWD
2024|Toyota|Highlander Hybrid
2024|Toyota|Highlander Hybrid AWD
2024|Toyota|Land Cruiser
2024|Toyota|RAV4
2024|Toyota|RAV4 AWD
2024|Toyota|RAV4 Prime 4WD
2024|Toyota|Tacoma 2WD
2024|Toyota|Tacoma 4WD
2024|Toyota|Tundra 2WD
2024|Toyota|Tundra 4WD
2024|Toyota|Venza AWD
2024|Honda|Accord Hybrid
2024|Honda|Accord Hybrid Sport/Touring
2024|Honda|CR-V AWD
2024|Honda|CR-V FWD
2024|Honda|Odyssey
2024|Honda|Passport AWD
2024|Honda|Ridgeline AWD
2024|Hyundai|Elantra
2024|Hyundai|Ioniq 6 Long range AWD (18 inch Wheels)
2024|Hyundai|Ioniq 6 Long range AWD (20 inch Wheels)
2024|Hyundai|Ioniq 6 Long range RWD (18 inch Wheels)
2024|Hyundai|Ioniq 6 Long range RWD (20 inch Wheels)
2024|Hyundai|Ioniq 6 Standard Range RWD
2024|Hyundai|Kona AWD
2024|Hyundai|Kona FWD
2024|Hyundai|Palisade AWD
2024|Hyundai|Palisade FWD
2024|Hyundai|Santa Fe AWD
2024|Hyundai|Santa Fe FWD
2024|Hyundai|Santa Fe Hybrid AWD
2024|Hyundai|Santa Fe Hybrid FWD
2024|Hyundai|Sonata AWD
2024|Hyundai|Sonata FWD
2024|Hyundai|Tucson AWD
2024|Hyundai|Tucson FWD
2024|Hyundai|Venue
2024|Tesla|Model 3 Long Range AWD
2024|Tesla|Model 3 Performance AWD
2024|Tesla|Model S
2024|Tesla|Model X
2024|Mazda|3 4-Door 2WD
2024|Mazda|3 5-Door 2WD
2024|Mazda|CX-50 4WD
2024|Mazda|CX-90 4WD
2024|Mazda|MX-5
EOF

jq -s '
  reduce .[] as $entries
    ([]; reduce $entries[] as $entry (.;
      if any(.[]; .rosterCatalogId == $entry.rosterCatalogId) then . else . + [$entry] end))
' "$roster_path" "$batch_file" > "$merged_file"

after_count="$(jq 'length' "$merged_file")"
added_count="$((after_count - before_count))"

if (( added_count < 50 )); then
  echo "Expected to add at least 50 roster entries, but only added ${added_count}." >&2
  exit 1
fi

mv "$merged_file" "$roster_path"
echo "Added ${added_count} roster entries. New roster count: ${after_count}." >&2
