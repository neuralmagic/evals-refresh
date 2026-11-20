#!/usr/bin/env bash
set -euo pipefail
repo_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"

reassemble() {
  local relative="$1"
  local expected_sha256="$2"
  local output="$repo_root/$relative"
  cat "$output.part-001" "$output.part-002" "$output.part-003" > "$output"
  printf '%s  %s\n' "$expected_sha256" "$output" | sha256sum --check -
}

reassemble \
  'llm-compressor_Mistral-Large-4-1T-A52B-MXFP4xFP8/knowledge-and-reasoning/mmlu-pro/logs/2026-11-03T22-15-24-00-00_mmlu-pro_GcoTYMxQL2bDRuJbkm4smi.eval' \
  '7c12171d432d1f384d580cda020d9d0dca4d790af0eb58ceb9264e98e9828a71'
reassemble \
  'mistralai_Mistral-Large-4-1T-A52B/knowledge-and-reasoning/mmlu-pro/logs/2026-11-04T03-41-51-00-00_mmlu-pro_JBMAtCatQTPgYp9GFsBbbH.eval' \
  'ff70c43c5c0b2e385ba0b8bdd75804ec50d66488854b6a672df19814cf75445e'
