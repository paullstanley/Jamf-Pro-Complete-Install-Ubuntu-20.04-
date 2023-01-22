#!/bin/bash

# Title: installjamf.sh
# Author: Paull Stanley

# Description:
# Installs pre-requsite software for Jamf on-prem server running on Ubuntu 20.04
# If using a newly created virtual machine or newly resored snapshot, 
# please allow sufficient time for those processes to finish before attempting
# to run this script(Usually this takes a few minutes).

# Instructions: 
# Make Sure you have the Jamf Pro manual install file(ROOT.war) in your /tmp directory before runnng the script.
# This directory can be modified by changing the root_war_dir variable.

# Customize the installation here
root_war_dir='/tmp'

root_user='root'
root_password='root'

jamf_database_name='jamfsoftware'
jamf_database_user='jamfsoftware'
jamf_user_host='localhost'
jamf_database_password='password'

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

# Step 11: Configure MySQL database and user for Tomcat
mysql -u $root_user -p$root_password -e "CREATE DATABASE $jamf_database_name;"
mysql -u $root_user -p$root_password -e "CREATE USER '$jamf_database_user'@'$jamf_user_host' IDENTIFIED WITH mysql_native_password BY '$jamf_database_password';"
mysql -u $root_user -p$root_password -e "GRANT ALL ON $jamf_database_name.* to '$jamf_database_user'@'$jamf_user_host';"


# Step 12: Create group and user for Apache Tomcat
sudo groupadd tomcat
sudo useradd -r -g tomcat -d /opt/apache-tomcat-8.5.42 -s /bin/nologin tomcat

# Step 13: Create temporary directory for the download and move to that directory
mkdir /tmp/tomcat && cd /tmp/tomcat

# Step 14: Download Apache Tomcat & verify the file
wget https://archive.apache.org/dist/tomcat/tomcat-8/v8.5.84/bin/apache-tomcat-8.5.84.tar.gz
wget https://archive.apache.org/dist/tomcat/tomcat-8/v8.5.84/bin/apache-tomcat-8.5.84.tar.gz.sha512
sha512sum -c apache-tomcat-8.5.84.tar.gz.sha512

# Step 15: Exit script if file cannot be verified
if [ "apache-tomcat-8.5.84.tar.gz: OK" ]; then
    echo "Package integrity is valid, continuing with script..."

# Step 16: Extract the Apache Tomcat Package and move it to /opt/
    sudo tar -zxvf apache-tomcat-8.5.84.tar.gz
    sudo mv apache-tomcat-8.5.84 /opt/

# Step 17: Give ownership of the directory to tomcat
    sudo chown -R tomcat:tomcat /opt/apache-tomcat-8.5.84

# Step 18: Create a system link to the tomcat directory 
    sudo ln -s /opt/apache-tomcat-8.5.84 /opt/tomcat

# Step 19: Create the file and insert the unit failed
    sudo echo -e "[Unit]\n    Description=Jamf Pro Web Application Container\n    Wants=network.target\n    After=syslog.target network.target\n\n    [Service]\n    Type=forking\n\n    Environment=JAVA_HOME=/usr/lib/jvm/java-11-openjdk-amd64\n    Environment=CATALINA_PID=/opt/tomcat/temp/tomcat.pid\n    Environment=CATALINA_HOME=/opt/tomcat\n    Environment=CATALINA_BASE=/opt/tomcat\n    Environment='CATALINA_OPTS=-server -XX:+UseParallelGC'\n    Environment='JAVA_OPTS=-Djava.awt.headless=true -Djava.net.preferIPv4Stack=true'\n\n    ExecStart=/opt/tomcat/bin/startup.sh\n    ExecStop=/opt/tomcat/bin/shutdown.sh\n\n    User=tomcat\n    Group=tomcat\n    UMask=0007\n    RestartSec=10\n    Restart=always\n\n    [Install]\n    WantedBy=multi-user.target" | sudo tee -a "/etc/systemd/system/tomcat.service"

    sudo rm -rf /opt/apache-tomcat-8.5.84/webapps/ROOT/
    sudo mv "$root_war_dir/ROOT.war" /opt/apache-tomcat-8.5.84/webapps/

# Step 20: Reload the system daemon
    sudo systemctl daemon-reload

# Step 21: Start the tomcat service
    sudo systemctl start tomcat

# Step 22: Enable auto startup of the Tomcat service at boot
    sudo systemctl enable tomcat

# Step 23: Wait for the ROOT.war file to unpack
    sleep 10

# Step 24: Edit Tomecat's DataBase.xml file with the MySQL user credentials
    sudo sed -i "s|<ServerName>.*</ServerName>|<ServerName>$jamf_user_host</ServerName>|g" /opt/apache-tomcat-8.5.84/webapps/ROOT/WEB-INF/xml/DataBase.xml
    sudo sed -i "s|<DataBaseName>.*</DataBaseName>|<DataBaseName>$jamf_database_name</DataBaseName>|g" /opt/apache-tomcat-8.5.84/webapps/ROOT/WEB-INF/xml/DataBase.xml
    sudo sed -i "s|<DataBaseUser>.*</DataBaseUser>|<DataBaseUser>$jamf_database_user</DataBaseUser>|g" /opt/apache-tomcat-8.5.84/webapps/ROOT/WEB-INF/xml/DataBase.xml
    sudo sed -i "s|<DataBasePassword>.*</DataBasePassword>|<DataBasePassword>$jamf_database_password</DataBasePassword>|g" /opt/apache-tomcat-8.5.84/webapps/ROOT/WEB-INF/xml/DataBase.xml
    

# Step 25: Restart Tomcat
    sudo systemctl restart tomcat

else
    echo "Package integrity check failed, exiting script..."
    exit 1
fi
