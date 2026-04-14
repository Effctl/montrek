#!/bin/bash
set -euo pipefail
set -x

echo "Syncing Python environment with uv..."

# Create .venv only if it does not already exist.
# This avoids permission errors when stale files exist in an existing venv.
if [ ! -d ".venv" ]; then
  uv venv
else
  echo "Using existing .venv"
fi

# Combine all requirements.in files into one
temporary_requirements_file="all_requirements.in"
>"$temporary_requirements_file"
find . -name 'requirements.in' -exec sh -c 'cat "$1"; echo' _ {} \; >>"$temporary_requirements_file"

# Compile and sync using uv
uv pip compile "$temporary_requirements_file" --output-file requirements.txt
uv pip sync requirements.txt

rm "$temporary_requirements_file"
