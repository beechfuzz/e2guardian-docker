#!/bin/sh

###
### CONSTANTS
###

app="/app"
appnweb="$app/nweb"
conf="/config"
e2g_ssl="$conf/ssl"
e2g_servercerts="$e2g_ssl/servercerts"
e2g_gencerts="$e2g_ssl/generatedcerts"
e2g_capubkeycrt="$e2g_servercerts/cacertificate.crt"
e2g_capubkeyder="$e2g_servercerts/my_rootCA.der"
nweb_crt="$appnweb/cacertificate.crt"
nweb_der="$appnweb/my_rootCA.der"


###
### FUNCTIONS
###

file_exists() {
    local f="$1"
    stat $f &>/dev/null
}


###
### MAIN
###

#Set UID and GID of e2guardian account
#-------------------------------------
groupmod -o -g $PGID e2guardian
usermod -o -u $PUID e2guardian

#Verify important files in Docker volumes exist
#----------------------------------------------
if (! file_exists "$conf/*"); then
    echo "INFO: $conf is empty -- extracting $app/config.gz to $conf"
    tar xzf $app/config.gz -C /
fi

#Remove any existing .pid file that could prevent e2guardian from starting
#-------------------------------------------------------------------------
rm -rf $app/pid/e2guardian.pid

#Ensure correct ownership and permissions
#----------------------------------------
chown -R e2guardian:e2guardian /app /config
chmod -R 755 $e2g_servercerts
chmod -R 700 $e2g_servercerts/*.pem $e2g_gencerts

#Prep E2Guardian
#---------------
[[ "$E2G_MITM" = "on" ]] && args="e" || args="d"
e2g-mitm.sh -$args

#Deconflict Filebrowser and Nweb ports
#-------------------------------------
if [[ "$FILEBROWSER" = "on"  ]] \
&& [[ "$NWEB" = "on" ]] \
&& [[ "$FILEBROWSER_PORT" = "$NWEB_PORT" ]]; then
    echo "ERROR: Filebrowser and Nweb are both configured for port $FILEBROWSER_PORT!"
    exit 1
fi

#Start Filebrowser
#-----------------
if [[ "$FILEBROWSER" = "on" ]]; then
    filebrowser \
        -a $FILEBROWSER_ADDR \
        -p $FILEBROWSER_PORT \
        -r $FILEBROWSER_ROOT \
        -d $FILEBROWSER_DB \
        -l $FILEBROWSER_LOG &
fi

#Start Nweb
#----------
if [[ "$NWEB" = "on" ]]; then
    if [[ "$E2G_MITM" = "on" ]]; then
        (file_exists $e2g_capubkeycrt) && (! file_exists $nweb_crt) && ln -s $e2g_capubkeycrt $nweb_crt
        (file_exists $e2g_capubkeyder) && (! file_exists $nweb_der) && ln -s $e2g_capubkeyder $nweb_der
	nweb -p "$NWEB_PORT" -r "$appnweb" -l /app/log/nweb.log \
		&& echo INFO: Nweb started and running on port "$NWEB_PORT". \
		|| echo ERROR: Nweb failed to start!
    else
        echo "WARNING: Nweb was configured to start even though SSL MITM is disabled.  Leaving Nweb off as it would serve no function."
    fi
fi

#Start e2guardian
#----------------
e2guardian -N -c $conf/e2guardian.conf
