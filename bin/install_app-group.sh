#!/bin/bash

APPGROUP=$1
JBOSS_BUILD_HOME=$2
HOSTNAME=`hostname`

source /opt/jboss/apps/$APPGROUP/$APPGROUP.properties 2> >(grep -v ".properties: line" >&2)
source $JBOSS_BUILD_HOME/bin/install.server

#Generate app-group.conf file
cp $JBOSS_BUILD_HOME/conf/app-group.conf $APPS_BASE/$APPGROUP/
grep '^app-group_' $APPS_BASE/$APPGROUP/$APPGROUP.properties | awk -F"app-group_" '{print $2}' | awk -F"=" '{print $1"="$2}' | cat - $APPS_BASE/$APPGROUP/app-group.conf > /tmp/out && mv /tmp/out $APPS_BASE/$APPGROUP/app-group.conf

IFS=',' read -a server_groups <<< "$SERVER_GROUPS";
for server_group_info in "${server_groups[@]}"
do
	#Set up initial server group variables
        IFS=':' read -a server_group_info <<< "$server_group_info";
        server_group=${server_group_info[0]}
        num_of_servers=${server_group_info[1]}
        echo "Creating $num_of_servers servers for $server_group..."

	#Generate server-group.conf file
	mkdir -p $APPS_BASE/$APPGROUP/server-groups/$server_group/
	cp $JBOSS_BUILD_HOME/conf/server-group.conf $APPS_BASE/$APPGROUP/server-groups/$server_group/
#	grep '^server-group_' $APPS_BASE/$APPGROUP/$server_group.properties | awk -F"server-group_" '{print $2}' | awk -F"=" '{print $1"="$2}' | cat - $APPS_BASE/$APPGROUP/server-groups/$server_group/server-group.conf > /tmp/out && mv /tmp/out $APPS_BASE/$APPGROUP/server-groups/$server_group/server-group.conf
	grep '^server-group_' $APPS_BASE/$APPGROUP/$server_group.properties | awk -F"server-group_" '{print $2}' | cat - $APPS_BASE/$APPGROUP/server-groups/$server_group/server-group.conf > /tmp/out && mv /tmp/out $APPS_BASE/$APPGROUP/server-groups/$server_group/server-group.conf
	grep '^sysprop_' $APPS_BASE/$APPGROUP/$server_group.properties | awk -F"sysprop_" '{print $2}' | awk -F"=" '{print "echo \""$1"="$2"\" >> ${PROPERTIES}"}' >> $APPS_BASE/$APPGROUP/server-groups/$server_group/server-group.conf

	# Create servers
	for ((server_num=1; server_num<=$num_of_servers; server_num++))
	do
		export server_name=${server_group//[_]/_$HOSTNAME\_}\_$server_num
		echo "Creating $server_name directories..."
		echo $APPS_BASE/$APPGROUP/server-groups/$server_group/servers/$server_name/{configuration,data,deployments,tmp}
		mkdir -p $APPS_BASE/$APPGROUP/server-groups/$server_group/servers/$server_name/{configuration,data,deployments,tmp}
		echo /opt/$APPGROUP/logs/$server_group/jboss/$server_name
		# Changing logdir to /opt/$APPGROUP/jboss/logs...
		# mkdir -p /opt/$APPGROUP/logs/$server_group/jboss/$server_name
		mkdir -p /opt/$APPGROUP/jboss/logs/$server_group
		cp $JBOSS_HOME/standalone/configuration/* $APPS_BASE/$APPGROUP/server-groups/$server_group/servers/$server_name/configuration/

		#Generate server.conf file
        	cp $JBOSS_BUILD_HOME/conf/server.conf $APPS_BASE/$APPGROUP/server-groups/$server_group/servers/$server_name/
        	grep "^server${server_num}_" $APPS_BASE/$APPGROUP/$server_group.properties | awk -F"server${server_num}_" '{print $2}' | cat - $APPS_BASE/$APPGROUP/server-groups/$server_group/servers/$server_name/server.conf > /tmp/out && mv /tmp/out $APPS_BASE/$APPGROUP/server-groups/$server_group/servers/$server_name/server.conf
		grep "^server${server_num}-sysprop_" $APPS_BASE/$APPGROUP/$server_group.properties | awk -F"server${server_num}-sysprop_" '{print $2}' | awk -F"=" '{print "echo \""$1"="$2"\" >> ${PROPERTIES}"}' >> $APPS_BASE/$APPGROUP/server-groups/$server_group/servers/$server_name/server.conf
		#Install server
		install_server $APPGROUP $server_group $server_name
	done

done

#Clean up properties files.
rm $APPS_BASE/$APPGROUP/*.properties
