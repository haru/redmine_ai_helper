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

# Roll back all plugin migrations to verify each is reversible.
bundle exec rake redmine:plugins:migrate NAME=$NAME_OF_PLUGIN VERSION=0

# Re-run forward migrations to verify round-trip integrity.
bundle exec rake redmine:plugins:migrate NAME=$NAME_OF_PLUGIN
