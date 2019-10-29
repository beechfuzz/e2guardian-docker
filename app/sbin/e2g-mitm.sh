#!/bin/sh
CONF="/config"
SSL="$CONF/ssl"
SERVERCERTS="$SSL/servercerts"
GENERATEDCERTS="$SSL/generatedcerts"
CAPRIVKEY="$SERVERCERTS/caprivatekey.pem"
CAPUBKEYCRT="$SERVERCERTS/cacertificate.crt"
CAPUBKEYDER="$SERVERCERTS/my_rootCA.der"
UPSTREAMPRIVKEY="$SERVERCERTS/certprivatekey.pem"

###
### Functions
###

usage() {
    echo -e "Usage:  e2g-mitm.sh [options] \n" \
    "\n" \
    " -b  Backup any certs that are present before overwriting/deleting them \n" \
    " -d  Disable SSL MITM; can't be used with -g. \n" \
    " -D  Disable SSL MITM and delete any certs that are present; can't be used with -g. \n" \
    " -e  Enable SSL MITM\n" \
    " -E  Enable SSL MIT and generate new SSL certs (same as -eg)\n" \
    " -g  Generate new SSL certs (overwrites previous ones); can't be used with -d or -D. \n" \
    " -h  Display this help menu\n"
    exit 1
}

exists() {
    local f="$1"
    return $(ls -A $f &>/dev/null;echo $?)
}

backup() {
    local check="$SERVERCERTS/*.*"
    local BDIR="$SSL/backup"
    local BNAME="certs_$(date '+%Y-%m-%d_%H:%M:%S').tz"
    local BFILE="$BDIR/$BNAME"
    if $(exists $check;exit $?); then
        [[ ! -d "$BDIR" ]] && (mkdir -p "$BDIR" && chown e2guardian:e2guardian "$BDIR")
        tar czf "$BFILE" "$SERVERCERTS" "$GENERATEDCERTS" && \
            echo Successfully backed up pre-existing certs to "$BFILE".
    else
        echo No certs currently exist to backup.
    fi
}

deletecerts() {
    local check="$SERVERCERTS/*.*"
    $(exists $check;exit $?) && (rm -f $check && echo Successfully deleted certs.) || echo No certs to delete.
}

###
### Main
###

#Validate args
[[ $# -eq 0 ]] && usage
while getopts ':bdDeEgh' OPT; do
    case "$OPT" in
        b )
            BACKUP=1;;
        d )
            [[ "$MITM" = "on" ]] && echo "ERROR: You can't disable and enable MITM at the same time." && usage
            MITM=off;;
        D )
            [[ "$MITM" = "on" ]] && echo "ERROR: You can't disable and enable MITM at the same time." && usage
            [[ "$GENCERTS" ]] && echo "ERROR: Can't use the -D and -g flags at the same time." && usage
            MITM=off
            DELCERTS=1;;
        e )
            [[ "$MITM" = "off" ]] && echo "ERROR: You can't disable and enable MITM at the same time." && usage
            [[ "$DELCERTS" ]] && echo "ERROR: You can't enable MITM and delete the certs at the same time." && usage
            MITM=on
            if (! $(exists $CAPRIVKEY;exit $?)) || (! $(exists $CAPUBKEYCRT;exit $?)) || (! $(exists $CAPUBKEYDER;exit $?)) || (! $(exists $UPSTREAMPRIVKEY;exit $?)); then
                echo "Missing certs -- will generate new certs." && GENCERTS=1 && BACKUP=1
            fi;;
        E )
            [[ "$MITM" = "off" ]] && echo "ERROR: You can't disable and enable MITM at the same time." && usage
            [[ "$DELCERTS" ]] && echo "ERROR: You can't use the -E and -D flags the same time." && usage
            MITM=on
            GENCERTS=1;;
        g )
            [[ "$DELCERTS" ]] && echo "ERROR: Can'use the -D and -g flags at the same time." && usage
            GENCERTS=1;;
        h | ? )
            usage;;
    esac
done
shift "$(($OPTIND -1))"
[[ $# -gt 0 ]] && echo "ERROR: Too many arguments." && usage

#Set toggle
[[ "$MITM" = "on" ]] && TOGGLE="off" || TOGGLE="on"


#Backup/Delete/Generate SSL certs as specified
#---------------------------------------------
[[ "$BACKUP" ]] && backup
[[ "$DELCERTS" ]] && deletecerts
if [[ "$GENCERTS" ]]; then
    #Root CA Private Key
    openssl genrsa 4096 > $CAPRIVKEY
    #Root CA Public Key (.crt)
    openssl req -new -x509 -subj "/CN=e2guardian/O=e2guardian/C=US" -days 3650 -sha256 -key $CAPRIVKEY -out $CAPUBKEYCRT
    #Root CA Public Key (.der)
    openssl x509 -in $CAPUBKEYCRT -outform DER -out $CAPUBKEYDER
    #Private Key for upstream SSL certs
    openssl genrsa 4096 > $UPSTREAMPRIVKEY
    echo -e "Created the following certs: \n$(md5sum $SERVERCERTS/*.*)"
fi


#Modify cert/key paths
#---------------------
sed -i \
    -e "\|caprivatekeypath = '.*'$|s|'.*'|'$CAPRIVKEY'|" \
    -e "\|cacertificatepath = '.*'$|s|'.*'|'$CAPUBKEYCRT'|" \
    -e "\|generatedcertpath = '.*'$|s|'.*'|'$GENERATEDCERTS'|" \
    -e "\|certprivatekeypath = '.*'$|s|'.*'|'$UPSTREAMPRIVKEY'|" \
    $CONF/e2guardian.conf


#Toggle MITM & uncomment relevent lines
#--------------------------------------
if [[ "$MITM" ]]; then
    [[ "$MITM" = "on" ]] && \
        sed -i \
            -e "\|^[# ]*enablessl = off|s|off.*|on|g" \
            -e "\|^[# ]*enablessl = on[# ]*$|s|^[# ]*||" \
            -e "/^[# ]*\(caprivatekeypath\|cacertificatepath\|generatedcertpath\|certprivatekeypath\) = '.*' */s/^[# ]*//" \
            $CONF/e2guardian.conf
    sed -i \
        -e "\|^[# ]*sslmitm = $TOGGLE *$|s|$TOGGLE.*|$MITM|g" \
        -e "\|^[# ]*sslmitm = on[# ]*$|s|^[# ]*||" \
        $CONF/e2guardianf1.conf
    echo "SSL MITM is $MITM."
fi

