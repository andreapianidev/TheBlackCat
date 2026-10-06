#!/bin/zsh
# Raises CURRENT_PROJECT_VERSION by one for every target and regenerates the project.
# Run it in the same commit as the change it numbers.
set -e
cd "$(dirname "$0")/.."
current=$(grep -E 'CURRENT_PROJECT_VERSION:' project.yml | head -1 | grep -oE '[0-9]+')
next=$((current + 1))
sed -i '' "s/CURRENT_PROJECT_VERSION: \"$current\"/CURRENT_PROJECT_VERSION: \"$next\"/" project.yml
xcodegen generate >/dev/null
echo "build $current -> $next"
