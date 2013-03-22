#/bin/bash
sudo add-apt-repository ppa:webupd8team/java
sudo apt-get update
sudo apt-get install oracle-java7-installer

wget http://jruby.org.s3.amazonaws.com/downloads/1.7.2/jruby-bin-1.7.2.tar.gz
tar -xf jruby-bin-1.7.2.tar.gz

sudo apt-get install postgresql redis-server postgresql-server-dev-all 
gem install bundler
bundle install

echo "please check config/database.yml and config/sidekiq.yml and make changes"
echo "please update postgresql configuration to support replication"
