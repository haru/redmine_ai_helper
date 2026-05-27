#!/bin/sh
set -ex

cd $(dirname $0)

cd ..
yard stats --list-undoc | tee /dev/stderr |  grep -q "100.00%"

rubocop

cd /usr/local/redmine

bundle exec rake redmine:plugins:test
