#!/bin/sh
set -ex

cd $(dirname $0)

cd ..

if ! command -v npm >/dev/null 2>&1; then
  echo "npm not found: Node.js (>=22) is a required development dependency of this plugin." >&2
  echo "Install it (e.g. via nvm: https://github.com/nvm-sh/nvm) and re-run this script." >&2
  exit 1
fi

if [ ! -d node_modules ]; then
  npm ci
fi

npm run lint
npm run test:coverage

yard stats --list-undoc | tee /dev/stderr |  grep -q "100.00%"

rubocop --ignore-parent-exclusion

cd /usr/local/redmine

bundle exec rake redmine:plugins:test
