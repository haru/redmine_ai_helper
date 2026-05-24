#!/bin/sh
set -ex

cd $(dirname $0)

cd ..
yard stats --list-undoc
rubocop

cd /usr/local/redmine

bundle exec rake redmine:plugins:test
