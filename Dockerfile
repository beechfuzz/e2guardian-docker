####
### BUILD STAGE
### -----------
###

FROM lsiobase/alpine:amd64-3.8 as builder
SHELL ["/bin/bash", "-c"]
ARG FILEBROWSER=no

# Store ARGs
RUN \
    mkdir -p /tmp/args && \
    echo $FILEBROWSER > /tmp/args/FILEBROWSER

# Install build packages
RUN \
    echo '######## Update and install build packages ########' && \
    apk add --update --no-cache --virtual build-depends \
        autoconf automake cmake g++ build-base gcc gcc-doc \
        abuild git libpcrecpp pcre-dev pcre2 pcre2-dev \
        openssl-dev zlib-dev binutils-doc binutils tar

# Download and install e2guardian from source
WORKDIR /tmp/e2g
ADD https://github.com/e2guardian/e2guardian/archive/5.3.3.tar.gz /tmp/e2g/
RUN \
    echo '######## Extract e2guardian source ########' && \
    tar xzf 5.3.3.tar.gz --strip 1 && \
    \
    echo '######## Fix bug in e2guardian Makefile ########' && \
    sed -i '/^ipnobypass \\$/a domainsnobypass \\\nurlnobypass \\' configs/lists/Makefile.am && \
    \
    echo '######## Compile and install e2guardian ########' && \
    ./autogen.sh && \
    ./configure \
        --with-proxyuser="e2guardian" \
        --with-proxygroup="e2guardian" \
        --prefix="/app/e2guardian" \
        --sysconfdir='${prefix}/config' \
        --sbindir="/app/sbin" \
        --with-sysconfsubdir= \
        --enable-sslmitm="yes" \
        --enable-icap="yes" \
        --enable-clamd="yes" \
        --enable-commandline="yes" \
        --enable-email="yes" \
        --enable-ntlm="yes" \
        -enable-pcre="yes" \
        'CPPFLAGS=-mno-sse2 -g -O2' && \
    make -j 16 && make install

# SSL MITM modifications
RUN \
    mkdir -p \
        /app/e2guardian/config/ssl/generatedcerts \
        /app/e2guardian/config/ssl/servercerts && \
    \
    echo '######## Modify openssl.cnf ########' && \
    echo -e \
        '[ ca ] \n'\
        'basicConstraints=critical,CA:TRUE \n' \
        >> /etc/ssl/openssl.cnf && \
    \
    echo '######## Create e2g-mitm.sh script ########' && \
    echo -e \
        '#!/bin/sh \n'\
        'CONF="/app/e2guardian/config" \n'\
        'SSL="$CONF/ssl" \n'\
        'SERVERCERTS="$SSL/servercerts" \n'\
        'GENERATEDCERTS="$SSL/generatedcerts" \n'\
        'CAPRIVKEY="$SERVERCERTS/caprivatekey.pem" \n'\
        'CAPUBKEYCRT="$SERVERCERTS/cacertificate.crt" \n'\
        'CAPUBKEYDER="$SERVERCERTS/my_rootCA.der" \n'\
        'UPSTREAMPRIVKEY="$SERVERCERTS/certprivatekey.pem" \n'\
        '\n'\
        '\n'\
        'usage() {\n'\
            '\t echo -e "Usage:  e2g-mitm.sh [options] \\n" \\\n'\
            '\t "\\n" \\\n'\
            '\t " -b  Backup any certs that are present before overwriting/deleting them \\n" \\\n'\
            '\t " -d  Disable SSL MITM; can'"'"'t be used with -g. \\n" \\\n'\
            '\t " -D  Disable SSL MITM and delete any certs that are present; can'"'"'t be used with -g. \\n" \\\n'\
            '\t " -e  Enable SSL MITM\\n" \\\n'\
            '\t " -E  Enable SSL MIT and generate new SSL certs (same as -eg)\\n" \\\n'\
            '\t " -g  Generate new SSL certs (overwrites previous ones); can'"'"'t be used with -d or -D. \\n" \\\n'\
            '\t " -h  Display this help menu\\n" \n'\
            '\t exit 1 \n'\
        '}\n'\
        '\n'\
        'exists() {\n'\
            '\t local f="$1" \n'\
            '\t return $(ls -A $f &>/dev/null;echo $?) \n'\
        '}\n'\
        '\n'\
        'backup() {\n'\
            '\t local check="$SERVERCERTS/*.*" \n'\
            '\t local BDIR="$SSL/backup" \n'\
            '\t local BNAME="certs_$(date '"'"'+%Y-%m-%d_%H:%M:%S'"'"').tz" \n'\
            '\t local BFILE="$BDIR/$BNAME" \n'\
            '\t if $(exists $check;exit $?); then \n'\
                '\t\t [[ ! -d "$BDIR" ]] && (mkdir -p "$BDIR" && chown e2guardian:e2guardian "$BDIR") \n'\
                '\t\t tar czf "$BFILE" "$SERVERCERTS" "$GENERATEDCERTS" && \\\n'\
                    '\t\t\t echo Successfully backed up pre-existing certs to "$BFILE". \n'\
            '\t else \n'\
                '\t\t echo No certs currently exist to backup. \n'\
            '\t fi \n'\
        '}\n'\
        '\n'\
        'deletecerts() {\n'\
            '\t local check="$SERVERCERTS/*.*" \n'\
            '\t $(exists $check;exit $?) && (rm -f $check && echo Successfully deleted certs.) || echo No certs to delete. \n'\
        '}\n'\
        '\n'\
        '\n'\
        '[[ $# -eq 0 ]] && usage \n'\
        'while getopts '"'"':bdDeEgh'"'"' OPT; do \n'\
            '\t case "$OPT" in \n'\
                '\t\t b ) \n'\
                    '\t\t\t BACKUP=1;;\n'\
                '\t\t d ) \n'\
                    '\t\t\t [[ "$MITM" = "on" ]] && echo "ERROR: You can'"'"'t disable and enable MITM at the same time." && usage \n'\
                    '\t\t\t MITM=off;;\n'\
                '\t\t D ) \n'\
                    '\t\t\t [[ "$MITM" = "on" ]] && echo "ERROR: You can'"'"'t disable and enable MITM at the same time." && usage \n'\
                    '\t\t\t [[ "$GENCERTS" ]] && echo "ERROR: Can'"'"'t use the -D and -g flags at the same time." && usage \n'\
                    '\t\t\t MITM=off\n'\
                    '\t\t\t DELCERTS=1;;\n'\
                '\t\t e ) \n'\
                    '\t\t\t [[ "$MITM" = "off" ]] && echo "ERROR: You can'"'"'t disable and enable MITM at the same time." && usage \n'\
                    '\t\t\t [[ "$DELCERTS" ]] && echo "ERROR: You can'"'"'t enable MITM and delete the certs at the same time." && usage \n'\
                    '\t\t\t MITM=on \n'\
					'\t\t\t if (! $(exists $CAPRIVKEY;exit $?)) || (! $(exists $CAPUBKEYCRT;exit $?)) || (! $(exists $CAPUBKEYDER;exit $?)) || (! $(exists $UPSTREAMPRIVKEY;exit $?)); then  \n'\
                    	'\t\t\t\t echo "Missing certs -- will generate new certs." && GENCERTS=1 && BACKUP=1 \n'\
					'\t\t\t fi;;\n'\
                '\t\t E ) \n'\
                    '\t\t\t [[ "$MITM" = "off" ]] && echo "ERROR: You can'"'"'t disable and enable MITM at the same time." && usage \n'\
                    '\t\t\t [[ "$DELCERTS" ]] && echo "ERROR: You can'"'"'t use the -E and -D flags the same time." && usage \n'\
                    '\t\t\t MITM=on \n'\
                    '\t\t\t GENCERTS=1;;\n'\
                '\t\t g ) \n'\
                    '\t\t\t [[ "$DELCERTS" ]] && echo "ERROR: Can'"'"'use the -D and -g flags at the same time." && usage \n'\
                    '\t\t\t GENCERTS=1;;\n'\
                '\t\t h | ? ) \n'\
                    '\t\t\t usage;;\n'\
            '\t esac \n'\
        'done \n'\
        'shift "$(($OPTIND -1))" \n'\
        '[[ $# -gt 0 ]] && echo "ERROR: Too many arguments." && usage \n'\
        '[[ "$MITM" = "on" ]] && TOGGLE="off" || TOGGLE="on" \n'\
        '\n'\
        '\n'\
        '#Backup/Delete/Generate SSL certs as specified \n'\
        '#--------------------------------------------- \n'\
        '[[ "$BACKUP" ]] && backup \n'\
        '[[ "$DELCERTS" ]] && deletecerts \n'\
        'if [[ "$GENCERTS" ]]; then \n'\
            '\t #Root CA Private Key \n'\
            '\t openssl genrsa 4096 > $CAPRIVKEY \n'\
            '\t #Root CA Public Key (.crt) \n'\
            '\t openssl req -new -x509 -subj "/CN=e2guardian/O=e2guardian/C=US" -days 3650 -sha256 -key $CAPRIVKEY -out $CAPUBKEYCRT \n'\
            '\t #Root CA Public Key (.der)\n'\
            '\t openssl x509 -in $CAPUBKEYCRT -outform DER -out $CAPUBKEYDER \n'\
            '\t #Private Key for upstream SSL certs\n'\
            '\t openssl genrsa 4096 > $UPSTREAMPRIVKEY \n'\
            '\t echo -e "Created the following certs: \\n$(md5sum $SERVERCERTS/*.*)" \n'\
        'fi \n'\
        '\n'\
        '\n'\
        '#Modify cert/key paths \n'\
        '#--------------------- \n'\
        'sed -i \\\n'\
            '\t -e "\|caprivatekeypath = '"'"'.*'"'"'$|s|'"'"'.*'"'"'|'"'"'$CAPRIVKEY'"'"'|" \\\n'\
            '\t -e "\|cacertificatepath = '"'"'.*'"'"'$|s|'"'"'.*'"'"'|'"'"'$CAPUBKEYCRT'"'"'|" \\\n'\
            '\t -e "\|generatedcertpath = '"'"'.*'"'"'$|s|'"'"'.*'"'"'|'"'"'$GENERATEDCERTS'"'"'|" \\\n'\
            '\t -e "\|certprivatekeypath = '"'"'.*'"'"'$|s|'"'"'.*'"'"'|'"'"'$UPSTREAMPRIVKEY'"'"'|" \\\n'\
            '\t $CONF/e2guardian.conf \n'\
        '\n'\
        '\n'\
        '#Toggle MITM & uncomment relevent lines \n'\
        '#-------------------------------------- \n'\
        'if [[ "$MITM" ]]; then \n'\
            '\t [[ "$MITM" = "on" ]] && \\\n'\
                '\t\t sed -i \\\n'\
                    '\t\t\t -e "\|^[# ]*enablessl = off|s|off.*|on|g" \\\n'\
                    '\t\t\t -e "\|^[# ]*enablessl = on[# ]*$|s|^[# ]*||" \\\n'\
                    '\t\t\t -e "/^[# ]*\(caprivatekeypath\|cacertificatepath\|generatedcertpath\|certprivatekeypath\) = '"'"'.*'"'"' */s/^[# ]*//" \\\n'\
                    '\t\t\t $CONF/e2guardian.conf \n'\
            '\t sed -i \\\n'\
                '\t\t -e "\|^[# ]*sslmitm = $TOGGLE *$|s|$TOGGLE.*|$MITM|g" \\\n'\
                '\t\t -e "\|^[# ]*sslmitm = on[# ]*$|s|^[# ]*||" \\\n'\
                '\t\t $CONF/e2guardianf1.conf \n'\
            '\t echo "SSL MITM is $MITM." \n'\
        'fi \n'\
        > /app/sbin/e2g-mitm.sh && \
    chmod +x /app/sbin/e2g-mitm.sh

# e2guardian modifications
RUN \
    echo '######## Enable MITM ########' && \
    /app/sbin/e2g-mitm.sh -Eb && \
    \
    echo '######## Enable dockermode and update log location ########' && \
    sed -i \
        -e "s|^.\{0,1\}dockermode = off$|dockermode = on|g" \
        -e "\|^.\{0,1\}loglocation = '.*'$|s|'.*'|'/app/e2guardian/log/access.log'|" \
        -e "\|^.\{0,1\}loglocation = '.*'$|s|^#||" \
        /app/e2guardian/config/e2guardian.conf

# Filebrowser
WORKDIR /app/filebrowser/config
RUN \
    echo '######## Install Filebrowser if specified ########' && \
    if [[ $(cat /tmp/args/FILEBROWSER) = "yes" ]]; then \
        curl -fsSL https://filebrowser.xyz/get.sh | bash && \
        mv $(which filebrowser) /app/sbin && \
        chmod +x /app/sbin/filebrowser; \
    fi

#Create entrypoint script
RUN \
    echo '######## Create entrypoint script ########' && \
    echo -e \
        '#!/bin/sh \n'\
        'E2G="/app/e2guardian" \n'\
        'E2G_CONF="$E2G/config" \n'\
        'E2G_SSL="$E2G_CONF/ssl" \n'\
        'E2G_SERVERCERTS="$E2G_SSL/servercerts" \n'\
        'E2G_GENCERTS="$E2G_SSL/generatedcerts" \n'\
        'E2G_MITM=${E2G_MITM:="on"} \n'\
        '\n\n'\
        '#Set UID and GID of e2guardian account \n'\
        '#------------------------------------- \n'\
        'groupmod -o -g $PGID e2guardian \n'\
        'usermod -o -u $PUID e2guardian \n'\
        '\n\n'\
        '#Verify important files in Docker volumes exist \n'\
        '#---------------------------------------------- \n'\
        '[[ -z "$(ls -A $E2G_CONF 2>/dev/null)" ]] && tar xzf $E2G_CONF.gz -C /app --strip 1 \n'\
        '[[ ! -f $E2G/log/access.log ]] && touch $E2G/log/access.log \n'\
        '\n\n'\
        '#Remove any existing .pid file that could prevent e2guardian from starting \n'\
        '#------------------------------------------------------------------------- \n'\
        'rm -rf $E2G/var/run/e2guardian.pid \n'\
        '\n\n'\
        '#Ensure correct ownership and permissions \n'\
        '#---------------------------------------- \n'\
        'chown -R e2guardian:e2guardian /app \n'\
        'chmod -R 755 $E2G_SERVERCERTS \n'\
        'chmod -R 700 $E2G_SERVERCERTS/*.pem $E2G_GENCERTS \n'\
        '\n\n'\
        '#Enable/Disable MITM \n'\
        '#------------------- \n'\
        'e2g-mitm.sh -$([[ "$E2G_MITM" = "on" ]] && echo "e" || echo "d") \n'\
        '\n\n'\
        '#Start Filebrowser \n'\
        '#-----------------\n'\
        '[[ -x $(which filebrowser) ]] && \n'\
            '\t filebrowser \\\n'\
                '\t\t -a $FILEBROWSER_ADDR \\\n'\
                '\t\t -p $FILEBROWSER_PORT \\\n'\
                '\t\t -r $FILEBROWSER_ROOT \\\n'\
                '\t\t -d $FILEBROWSER_DB \\\n'\
                '\t\t -l $FILEBROWSER_LOG & \n'\
        '\n\n'\
        '#Start e2guardian \n'\
        '#-----------------\n'\
        'e2guardian -N -c $E2G_CONF/e2guardian.conf '\
        > /app/sbin/entrypoint.sh && \
    chmod +x /app/sbin/entrypoint.sh

RUN \
    tar czf /app/e2guardian/config.gz /app/e2guardian/config $([[ -x /app/sbin/filebrowser ]] && echo "/app/filebrowser/config")

###
### RUNTIME STAGE
### -------------
###

FROM alpine:3.8

ENV PATH="${PATH}:/app/sbin" \
    PUID="1000" \
    PGID="1000" \
    E2G_MITM="on" \
    FILEBROWSER_ADDR="0.0.0.0" \
    FILEBROWSER_PORT="80" \
    FILEBROWSER_ROOT="/app/e2guardian/config" \
    FILEBROWSER_DB="/app/filebrowser/config/database.db" \
    FILEBROWSER_LOG="/app/filebrowser/log/filebrowser.log"

VOLUME /app/e2guardian/config /app/e2guardian/log

COPY --from=builder /app /app

RUN \
    echo '######## Install required packages ########' && \
    apk add --update --no-cache libgcc libstdc++ pcre openssl shadow tini tzdata && \
    \
    echo '######## Create e2guardian account ########' && \
    groupmod -g 1000 users && \
    useradd -u 1000 -U -d /app/e2guardian/config -s /bin/false e2guardian && \
    usermod -G users e2guardian && \
    \
    echo '######## Clean-up ########' && \
    rm -rf /tmp/* /var/cache/apk/*

EXPOSE 8080

ENTRYPOINT ["/sbin/tini","-vv","-g","--","/app/sbin/entrypoint.sh"]
