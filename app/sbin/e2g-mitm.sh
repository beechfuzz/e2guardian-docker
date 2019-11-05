#!/bin/sh

###
### CONSTANTS
###

PATH="${PATH}:/app/sbin"
parent_proc="$(cat /proc/$PPID/cmdline)"
conf="/config"
ssl="$conf/ssl"
servercerts="$ssl/servercerts"
generatedcerts="$ssl/generatedcerts"
caprivkey="$servercerts/caprivatekey.pem"
capubkeycrt="$servercerts/cacertificate.crt"
capubkeyder="$servercerts/my_rootCA.der"
upstreamprivkey="$servercerts/certprivatekey.pem"


###
### FUNCTIONS
###

usage() {
    echo -e "
        Usage:  e2g-mitm.sh [options]

        -b         Backup any certs that are present before overwriting/deleting them
        -d         Disable SSL MITM; can't be used with -e, -E, or -g flags.
        -D         Disable SSL MITM and delete any certs that are present; can't be used with -e, -E, or -g flags.
        -e         Enable SSL MITM
        -E         Enable SSL MIT and generate new SSL certs (same as -eg)
        -g         Generate new SSL certs (overwrites previous ones); can't be used with -d or -D flags.
        -h         Display this help menu
        "
    exit 1
}

getopts_get_optarg() {
  eval next_token=\${$OPTIND}
  if [[ -n $next_token && $next_token != -* ]]; then
    OPTIND=$((OPTIND + 1))
    OPTARG=$next_token
  else
    OPTARG=""
  fi
}

file_exists() {
    local f="$1"
    stat $f &>/dev/null
}


backup_certs() {
    local check="$servercerts/*.*"
    local bdir="$ssl/backup"
    local bname="certs_$(date '+%Y-%m-%d_%H:%M:%S').tz"
    local bfile="$bdir/$bname"
    #if $(file_exists $check;exit $?); then
    if file_exists $check; then
        [[ ! -d "$bdir" ]] && (mkdir -p "$bdir" && chown e2guardian:e2guardian "$bdir")
        tar czf "$bfile" "$servercerts" "$generatedcerts" && \
            echo INFO: Successfully backed up pre-existing certs to "$bfile".
    else
        echo INFO: No certs currently exist to backup.
    fi
}

delete_certs() {
    local check="$servercerts/*.*"
    (file_exists $check) && (rm -f $check && echo INFO: Successfully deleted certs.) || echo INFO: No certs to delete.
}


###
### MAIN
###

# Validate and parse arguments
#-----------------------------
if (echo "'"$@"'" | grep -q "d\|D\|e\|E") \
&& !(echo "$parent_proc" | grep -q "entrypoint.sh"); then
    echo "ERROR: Only entrypoint.sh may invoke the -d, -D, -e, or -E flags."
    exit 1
fi
if (echo "$@" | grep -q "d\|D") \
&& (echo "$@" | grep -q "e\|E"); then
    echo "ERROR: You can't use the -d or -D flag in combination with the -e or -E flag."
    usage
fi
if (echo "$@" | grep -q "d\|D") \
&& (echo "$@" | grep -q "g"); then
    echo "ERROR: Can't use the -d or -D flag in combination with the -g flag."
    usage
fi

#Parse args
[[ $# -eq 0 ]] && usage
while getopts ':bdDeEgh' OPT; do
    case "$OPT" in
        b )
            backupcerts=1;;
        d )
            NWEB=off
            set_mitm=1;;
        D )
            NWEB=off
            set_mitm=1
            deletecerts=1;;
        e )
            if (! file_exists $caprivkey) \
            || (! file_exists $capubkeycrt) \
            || (! file_exists $capubkeyder) \
            || (! file_exists $upstreamprivkey); then
                echo "WARNING: Missing certs -- will generate new certs."
                generatecerts=1
                backupcerts=1
            fi
            set_mitm=1;;
        E )
            set_mitm=1
            generatecerts=1;;
        g )
            generatecerts=1;;
        h | ? )
            usage;;
    esac
done
shift "$(($OPTIND -1))"
[[ $# -gt 0 ]] && echo "ERROR: Too many arguments." && usage


# Backup/Delete/Generate SSL certs as specified
#----------------------------------------------
[[ "$backupcerts" ]] && backup_certs
[[ "$deletecerts" ]] && delete_certs
if [[ "$generatecerts" ]]; then
    #Root CA Private Key
    openssl genrsa 4096 > $caprivkey
    #Root CA Public Key (.crt)
    openssl req -new -x509 -subj "/CN=e2guardian/O=e2guardian/C=US" -days 3650 -sha256 -key $caprivkey -out $capubkeycrt
    #Root CA Public Key (.der)
    openssl x509 -in $capubkeycrt -outform DER -out $capubkeyder
    #Private Key for upstream SSL certs
    openssl genrsa 4096 > $upstreamprivkey
    echo -e "INFO: Created the following certs: \n$(md5sum $servercerts/*.*)"
fi


# Modify cert/key paths
#----------------------
sed -i \
    -e "\|caprivatekeypath = '.*'$|s|'.*'|'$caprivkey'|" \
    -e "\|cacertificatepath = '.*'$|s|'.*'|'$capubkeycrt'|" \
    -e "\|generatedcertpath = '.*'$|s|'.*'|'$generatedcerts'|" \
    -e "\|certprivatekeypath = '.*'$|s|'.*'|'$upstreamprivkey'|" \
    $conf/e2guardian.conf


# Toggle MITM & uncomment relevent lines
#---------------------------------------
if [[ "$set_mitm" ]]; then
    [[ "$E2G_MITM" = "on" ]] && TOGGLE="off" || TOGGLE="on"
    sed -i \
        -e "\|^[# ]*sslmitm = $TOGGLE *$|s|$TOGGLE.*|$E2G_MITM|g" \
        -e "\|^[# ]*sslmitm = on[# ]*$|s|^[# ]*||" \
        $conf/e2guardianf1.conf
    if [[ "$E2G_MITM" = "on" ]]; then
        sed -i \
            -e "\|^[# ]*enablessl = off|s|off.*|on|g" \
            -e "\|^[# ]*enablessl = on[# ]*$|s|^[# ]*||" \
            -e "/^[# ]*\(caprivatekeypath\|cacertificatepath\|generatedcertpath\|certprivatekeypath\) = '.*' */s/^[# ]*//" \
            $conf/e2guardian.conf
    fi
    echo "INFO: SSL MITM is $E2G_MITM."
fi

