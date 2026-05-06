#!/bin/bash
set -euo pipefail
set -x

echo "Syncing Python environment with uv..."

# Get the project root directory
PROJECT_ROOT="$(git rev-parse --show-toplevel)"
echo "PROJECT_ROOT=${PROJECT_ROOT}"

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

# Replace relative paths with .whl with absolute path based on the project root

while IFS= read -r line; do
  line="${line%$'\r'}"
  if [[ "$line" == *.whl ]] && [[ "$line" !=  /* ]]; then
    new_path="$PROJECT_ROOT/$line"
    echo "Rewriting wheel path: '$line' -> '$new_path'"
    echo "$PROJECT_ROOT/$line" >> "$temporary_requirements_file"
    echo "$new_path" >> "$temporary_requirements_file"
  else
    echo "$line" >> "$temporary_requirements_file"
  fi
done < <(find . -name 'requirements.in' -exec cat {} +)

# find . -name 'requirements.in' -exec sh -c 'cat "$1"; echo' _ {} \; >>"$temporary_requirements_file"

# Compile and sync using uv
uv pip compile "$temporary_requirements_file" --output-file requirements.txt
uv pip sync requirements.txt

rm "$temporary_requirements_file"
