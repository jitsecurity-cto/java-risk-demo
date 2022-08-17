#!/bin/bash -e

API_KEY=$1

wget https://inspector-agent.amazonaws.com/linux/latest/install
chmod +x ./install
sudo ./install
sudo apt-get -y update
sudo apt-get -y upgrade
echo "Installing software"
sudo apt-get -y install default-jre jetty9 docker.io
sudo usermod -G docker ubuntu
sudo apt-get -y install liblog4j2-java=2.11.2-1
echo "Software installed"
# Bug in the installer (doesn't add syslog to the jetty9 log)
sudo chmod -R 777 /var/log/jetty9

sudo tee -a /etc/default/jetty9 << 'EOF'
JAVA_OPTIONS="-DSOLVO_API_KEY=$1 -DSOLVO_COLLECTOR_URL=https://collector.solvo.dev"
EOF

sudo systemctl restart jetty9
