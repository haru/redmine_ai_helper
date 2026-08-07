#!/bin/sh
set -ex

cd $(dirname $0)

cd ..
yard stats --list-undoc | tee /dev/stderr |  grep -q "100.00%"

rubocop --ignore-parent-exclusion

cd /usr/local/redmine

bundle exec rake redmine:plugins:test
