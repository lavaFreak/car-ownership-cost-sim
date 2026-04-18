#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$repo_root"

roster_path="catalog/vehicle-roster.json"
helper_path="$(find dist-newstyle -type f -name discover-vehicle-roster | head -n 1)"
batch_input_path="${1:-catalog/roster-batches/2024-mainstream.txt}"
minimum_added_count="${2:-1}"

if [[ -z "${helper_path}" ]]; then
  echo "Could not locate the discover-vehicle-roster executable under dist-newstyle." >&2
  exit 1
fi

if [[ ! -f "${batch_input_path}" ]]; then
  echo "Could not find batch input file: ${batch_input_path}" >&2
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
done < "$batch_input_path"

jq -s '
  reduce .[] as $entries
    ([]; reduce $entries[] as $entry (.;
      if any(.[]; .rosterCatalogId == $entry.rosterCatalogId) then . else . + [$entry] end))
' "$roster_path" "$batch_file" > "$merged_file"

after_count="$(jq 'length' "$merged_file")"
added_count="$((after_count - before_count))"

if (( added_count < minimum_added_count )); then
  echo "Expected to add at least ${minimum_added_count} roster entries, but only added ${added_count}." >&2
  exit 1
fi

mv "$merged_file" "$roster_path"
echo "Added ${added_count} roster entries. New roster count: ${after_count}." >&2
