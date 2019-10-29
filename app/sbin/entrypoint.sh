#!/bin/sh
APP="/app"
E2G_CONF="/config"
E2G_SSL="$E2G_CONF/ssl"
E2G_SERVERCERTS="$E2G_SSL/servercerts"
E2G_GENCERTS="$E2G_SSL/generatedcerts"
E2G_MITM=${E2G_MITM:="on"}
FILEBROWSER_ADDR=${FILEBROWSER_ADDR:="0.0.0.0"}
FILEBROWSER_PORT=${FILEBROWSER_ADDR:="80"}
FILEBROWSER_ROOT=${FILEBROWSER_ROOT:="/config"}
FILEBROWSER_DB=${FILEBROWSER_DB:="/config/filebrowser/database.db"}
FILEBROWSER_LOG=${FILEBROWSER_LOG:="/app/log/filebrowser.log"}

#Set UID and GID of e2guardian account
#-------------------------------------
groupmod -o -g $PGID e2guardian
usermod -o -u $PUID e2guardian


#Verify important files in Docker volumes exist
#----------------------------------------------
[[ -z "$(ls -A $E2G_CONF 2>/dev/null)" ]] && tar xzf $APP/config.gz -C /


#Remove any existing .pid file that could prevent e2guardian from starting
#-------------------------------------------------------------------------
rm -rf $APP/pid/e2guardian.pid


#Ensure correct ownership and permissions
#----------------------------------------
chown -R e2guardian:e2guardian /app /config
chmod -R 755 $E2G_SERVERCERTS
chmod -R 700 $E2G_SERVERCERTS/*.pem $E2G_GENCERTS


#Enable/Disable MITM
#-------------------
e2g-mitm.sh -$([[ "$E2G_MITM" = "on" ]] && echo "e" || echo "d")


#Start Filebrowser
#-----------------
[[ -x $(which filebrowser) ]] &&
    filebrowser \
        -a $FILEBROWSER_ADDR \
        -p $FILEBROWSER_PORT \
        -r $FILEBROWSER_ROOT \
        -d $FILEBROWSER_DB \
        -l $FILEBROWSER_LOG &


#Start e2guardian
#----------------
e2guardian -N -c $E2G_CONF/e2guardian.conf
