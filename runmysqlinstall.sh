#!/bin/bash

# Installs pre-requsite software for Jamf on-prem server running on Ubuntu 20.04
# If using a newly created virtual machine or newly resored snapshot, 
# please allow sufficient time for those processes to finish before attempting
# to run this script(Usually this takes a few minutes).

# Set the root password
root_password="root"

# Step 1: Run apt update
sudo apt update

# Step 2: Install Java OpenJDK 11
sudo apt install openjdk-11-jdk << EOF
y
EOF

# Step 3: Set the Java Path
export JAVA_HOME="/usr/lib/jvm/java-11-openjdk-amd64"
export PATH="$PATH:$JAVA_HOME/bin"

# Step 4: Download MySQL 8.0.28
cd /tmp
wget -c https://dev.mysql.com/get/Downloads/MySQL-8.0/mysql-server_8.0.28-1ubuntu20.04_amd64.deb-bundle.tar

# Step 5: Extract the downloaded archive
tar -xvf mysql-server_8.0.28-1ubuntu20.04_amd64.deb-bundle.tar

# Step 6: Install operating system dependancies
sudo apt install -y libaio1 libmecab2:amd64 << EOF
yes
EOF

# Step 7: Comfigure installation package for automation
export DEBIAN_FRONTEND="noninteractive"
sudo echo "UNREGISTER mysql-community-server/data-dir" | sudo debconf-communicate mysql-community-server
sudo echo "mysql-community-server mysql-community-server/root-pass password $root_password" | sudo debconf-set-selections
sudo echo "mysql-community-server mysql-community-server/re-root-pass password $root_password" | sudo debconf-set-selections
sudo echo "mysql-community-server mysql-community-server/new-auth-types select Ok" | sudo debconf-set-selections
sudo echo "mysql-community-server mysql-server/default-auth-override select Use Legacy Authentication Method (Retain MySQL 5.x Compatibility)" | sudo debconf-set-selections
sudo echo "mysql-community-server mysql-community-server/default-auth-override select Use Legacy Authentication Method (Retain MySQL 5.x Compatibility)" | sudo debconf-set-selections


# Step 8: Install MySQL
sudo dpkg -i mysql-common_8.0.28-1ubuntu20.04_amd64.deb
sudo dpkg -i mysql-community-client-plugins_8.0.28-1ubuntu20.04_amd64.deb
sudo dpkg -i mysql-community-client-core_8.0.28-1ubuntu20.04_amd64.deb
sudo dpkg -i mysql-community-client_8.0.28-1ubuntu20.04_amd64.deb 
sudo dpkg -i mysql-client_8.0.28-1ubuntu20.04_amd64.deb
sudo dpkg -i mysql-community-server-core_8.0.28-1ubuntu20.04_amd64.deb
sudo dpkg -i mysql-community-server_8.0.28-1ubuntu20.04_amd64.deb

# Step 9: Start MySQL as service
sudo systemctl daemon-reload
sudo systemctl start mysql.service

# Step 10: Stop MySQL from auto-updating
sudo apt-mark hold mysql-server
sudo apt-mark hold mysql-common
sudo apt-mark hold mysql-server-core-*
sudo apt-mark hold mysql-client-core-*

# Step 11: Create group and user for Apache Tomcat
sudo groupadd tomcat
sudo useradd -r -g tomcat -d /opt/apache-tomcat-8.5.42 -s /bin/nologin tomcat

# Step 12: Create temporary directory for the download and move to that directory
mkdir /tmp/tomcat && cd /tmp/tomcat

# Step 13: Download Apache Tomcat & verify the file
wget https://archive.apache.org/dist/tomcat/tomcat-8/v8.5.84/bin/apache-tomcat-8.5.84.tar.gz
wget https://archive.apache.org/dist/tomcat/tomcat-8/v8.5.84/bin/apache-tomcat-8.5.84.tar.gz.sha512
sha512sum -c apache-tomcat-8.5.84.tar.gz.sha512

# Step 14: Exit script if file cannot be verified
if [ "apache-tomcat-8.5.84.tar.gz: OK" ]; then
    echo "Package integrity is valid, continuing with script..."

# Step 15: Extract the Apache Tomcat Package and move it to /opt/
    sudo tar -zxvf apache-tomcat-8.5.84.tar.gz
    sudo mv apache-tomcat-8.5.84 /opt/

# Step 16: Give ownership of the directory to tomcat
    sudo chown -R tomcat:tomcat /opt/apache-tomcat-8.5.84

# Step 17: Create a system link to the tomcat directory 
    sudo ln -s /opt/apache-tomcat-8.5.84 /opt/tomcat

# Step 18: Create the file and insert the unit file
    sudo cat > /etc/systemd/system/tomcat.service
    echo -e "[Unit]\n    Description=Jamf Pro Web Application Container\n    Wants=network.target\n    After=syslog.target network.target\n\n    [Service]\n    Type=forking\n\n    Environment=JAVA_HOME=/usr/lib/jvm/java-11-openjdk-amd64\n    Environment=CATALINA_PID=/opt/tomcat/temp/tomcat.pid\n    Environment=CATALINA_HOME=/opt/tomcat\n    Environment=CATALINA_BASE=/opt/tomcat\n    Environment='CATALINA_OPTS=-server -XX:+UseParallelGC'\n    Environment='JAVA_OPTS=-Djava.awt.headless=true -Djava.net.preferIPv4Stack=true'\n\n    ExecStart=/opt/tomcat/bin/startup.sh\n    ExecStop=/opt/tomcat/bin/shutdown.sh\n\n    User=tomcat\n    Group=tomcat\n    UMask=0007\n    RestartSec=10\n    Restart=always\n\n    [Install]\n    WantedBy=multi-user.target" | sudo tee -a "/etc/systemd/system/tomcat.service"
# Step 19: Reload the system daemon
    sudo systemctl daemon-reload

# Step 20: Enable the tomcat service
    sudo systemctl enable tomcat.service

# Step 21: Start the tomcat service
    sudo systemctl start tomcat.service

# Step 22: Check the status of the tomcat service
    sudo systemctl status tomcat.service

# Step 23: Enable auto startup of the Tomcat service at boot
    sudo systemctl enable tomcat

else
    echo "Package integrity check failed, exiting script..."
    exit 1
fi
