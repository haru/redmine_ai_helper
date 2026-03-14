#!/bin/sh

cd `dirname $0`
cd ..
BASEDIR=`pwd`
PLUGIN_NAME=`basename $BASEDIR`

if [ ! -f ~/.bashrc ]; then
    cd ~/
    tar xfz /.home.tgz
    cd $BASEDIR
fi

echo 'export PATH="$HOME/.local/bin:$PATH"' >> $HOME/.bashrc


rm -rf .ruby-lsp
ln -s /dev/null .ruby-lsp

cd $REDMINE_ROOT

rm -rf .ruby-lsp
ln -s /dev/null .ruby-lsp

git pull

bundle install
bundle exec rake redmine:plugins:ai_helper:setup_scm

initdb() {
    if [ $DB != "sqlite3" ]
    then
        bundle exec rake db:create
    fi
    bundle exec rake db:migrate
    bundle exec rake redmine:plugins:migrate

    if [ $DB != "sqlite3" ]
    then
        bundle exec rake db:drop RAILS_ENV=test
        bundle exec rake db:create RAILS_ENV=test
    fi

    bundle exec rake db:migrate RAILS_ENV=test
    bundle exec rake redmine:plugins:migrate RAILS_ENV=test
}

export DB=mysql2
export DB_NAME=redmine
export DB_USERNAME=root
export DB_PASSWORD=root
export DB_HOST=mysql
export DB_PORT=3306

initdb

export DB=postgresql
export DB_NAME=redmine
export DB_USERNAME=postgres
export DB_PASSWORD=postgres
export DB_HOST=postgres
export DB_PORT=5432

initdb

rm -f db/redmine.sqlite3_test
export DB=sqlite3
initdb
