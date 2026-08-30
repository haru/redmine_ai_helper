#!/bin/bash

set -e

cd `dirname $0`
. ./env.sh
cd ../..

if [ "$NAME_OF_PLUGIN" == "" ]
then
  export NAME_OF_PLUGIN=`basename $PATH_TO_PLUGIN`
fi

cd $PATH_TO_REDMINE

# create scms for test
bundle exec rake test:scm:setup:all

# run tests
# bundle exec rake TEST=test/unit/role_test.rb
bundle exec rake redmine:plugins:test NAME=$NAME_OF_PLUGIN 2>&1 | tee $PATH_TO_PLUGIN/ruby-test-output.log
test ${PIPESTATUS[0]} -eq 0

cp -pr plugins/$NAME_OF_PLUGIN/coverage $PATH_TO_PLUGIN
