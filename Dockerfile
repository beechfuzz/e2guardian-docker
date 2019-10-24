####
### BUILD STAGE
### -----------
###
 
FROM lsiobase/alpine:amd64-3.8 as builder
SHELL ["/bin/bash", "-c"]
ARG SSLMITM=on
ARG SSLSUBJ='/CN=e2guardian/O=e2guardian/C=US'

# Install build packages
RUN \
    echo $SSLMITM > /tmp/SSLMITM && \
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
            '--with-proxyuser=e2guardian' \
            '--with-proxygroup=e2guardian' \
            '--prefix=/app' \
            '--sysconfdir=${prefix}/config' \
            '--with-sysconfsubdir=' \
            "--enable-sslmitm=$([[ $SSLMITM = "on" ]] && echo "yes" || echo "no")" \
            '--enable-icap=yes' \
            '--enable-clamd=yes' \
            '--enable-commandline=yes' \
            '--enable-email=yes' \
            '--enable-ntlm=yes' \
            '--enable-pcre=yes' \
            'CPPFLAGS=-mno-sse2 -g -O2' && \
        make -j 16 && make install

# SSL MITM modifications
RUN \
    mkdir -p \
        /app/config/ssl/generatedcerts \
        /app/config/ssl/servercerts && \
    \
    echo '######## Modify openssl.cnf ########' && \
        echo -e \
            '[ ca ] \n'\
            'basicConstraints=critical,CA:TRUE \n' \
            >> /etc/ssl/openssl.cnf && \
    \
    echo '######## Create enablesslmitm.sh script ########' && \
        echo -e \
            '#!/bin/sh \n'\
            'ENABLE_SSLMITM=on\n'\
            'SERVERCERTS="/app/config/ssl/servercerts" \n'\
            'GENERATEDCERTS="/app/config/ssl/generatedcerts" \n'\
            '\n'\
            '\n'\
            'usage() {\n'\
                '\t echo -e "Usage: enablesslmitm.sh \\n"\\\n'\
                '\t         "       enablesslmitm.sh -g [-b] \\n"\\\n'\
                '\t         "       enablesslmitm.sh -d \\n"\\\n'\
                '\t         "       enablesslmitm.sh -D [-b]  \\n"\\\n'\
                '\t         "       enablesslmitm.sh -h \\n"\\\n'\
                '\t "\\n"\\\n'\
                '\t " -b, --backup           Backup any certs that are present before overwriting/deleting them\\n"\\\n'\
                '\t " -d, --disable          Disable SSL MITM\\n"\\\n'\
                '\t " -D, --disable-delete   Disable SSL MITM and delete any certs that are present\\n"\\\n'\
                '\t " -g, --generate         Generate new SSL certs \(overwrites previous ones\)\\n"\\\n'\
                '\t " -h, --help             Display this help menu\\n"\n'\
            '}\n'\
            '\n'\
            'exists() {\n'\
                '\t local f="$1" \n'\
                '\t return $(ls -A $f &>/dev/null;echo $?) \n'\
            '}\n'\
            '\n'\
            'backup() {\n'\
                '\t local check="$SERVERCERTS/*.*" \n'\
                '\t local BDIR="/app/config/ssl/backup" \n'\
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
            'while [ "$1" != "" ]; do \n'\
                '\t case $1 in \n'\
                    '\t\t -d | --disable ) \n'\
                        '\t\t\t ENABLE_SSLMITM=off;;\n'\
                    '\t\t -D | --disable-delete ) \n'\
                        '\t\t\t ENABLE_SSLMITM=off\n'\
                        '\t\t\t DELCERTS=1;;\n'\
                    '\t\t -g | --generate ) \n'\
                        '\t\t\t GENCERTS=1;;\n'\
                    '\t\t -b | --backup ) \n'\
                        '\t\t\t BACKUP=1;;\n'\
                    '\t\t -h | --help ) \n'\
                         '\t\t\t usage;;\n'\
                    '\t\t * ) \n'\
                        '\t\t\t usage\n'\
                        '\t\t\t exit 1;;\n'\
                '\t esac \n'\
                '\t shift \n'\
            'done \n'\
            '[[ $ENABLE_SSLMITM = "on" ]] && TOGGLE="off" || TOGGLE="on" \n'\
            '\n'\
            '\n'\
            '#Toggle SSL and modify paths of SSL certs/keys \n'\
            '#--------------------------------------------- \n'\
            'sed -i \\\n'\
                '\t -e "s|enablessl = $TOGGLE|enablessl = $ENABLE_SSLMITM|g" \\\n'\
                '\t -e "\|caprivatekeypath = '"'"'.*'"'"'$|s|'"'"'.*'"'"'|'"'"'/app/config/ssl/servercerts/caprivatekey.pem'"'"'|" \\\n'\
                '\t -e "\|cacertificatepath = '"'"'.*'"'"'$|s|'"'"'.*'"'"'|'"'"'/app/config/ssl/servercerts/cacertificate.crt'"'"'|" \\\n'\
                '\t -e "\|generatedcertpath = '"'"'.*'"'"'$|s|'"'"'.*'"'"'|'"'"'/app/config/ssl/generatedcerts'"'"'|" \\\n'\
                '\t -e "\|certprivatekeypath = '"'"'.*'"'"'$|s|'"'"'.*'"'"'|'"'"'/app/config/ssl/servercerts/certprivatekey.pem'"'"'|" \\\n'\
                '\t /app/config/e2guardian.conf \n'\
            'sed -i \\\n'\
                '\t -e "/\(sslmitm\|mitmcheckcert\) = $TOGGLE$/s/$TOGGLE$/$ENABLE_SSLMITM/" \\\n'\
                '\t /app/config/e2guardianf1.conf \n'\
            '\n'\
            '\n'\
            '#Generate required SSL certs and uncomment required lines \n'\
            '#-------------------------------------------------------- \n'\
            'if [[ $ENABLE_SSLMITM = "on" ]]; then \n'\
                '\t if [[ "$GENCERTS" ]]; then \n'\
                    '\t\t [[ "$BACKUP" ]] && backup \n'\
                    '\t\t #Root CA Private Key \n'\
                    '\t\t openssl genrsa 4096 > $SERVERCERTS/caprivatekey.pem \n'\
                    '\t\t #Root CA Public Key (.crt) \n'\
                    '\t\t openssl req -new -x509 -subj "/CN=e2guardian/O=e2guardian/C=US" -days 3650 -sha256 -key $SERVERCERTS/caprivatekey.pem -out $SERVERCERTS/cacertificate.crt \n'\
                    '\t\t #Root CA Public Key (.der)\n'\
                    '\t\t openssl x509 -in ${SERVERCERTS}/cacertificate.crt -outform DER -out $SERVERCERTS/my_rootCA.der \n'\
                    '\t\t #Private Key for upstream SSL certs\n'\
                    '\t\t openssl genrsa 4096 > $SERVERCERTS/certprivatekey.pem \n'\
                    '\t\t echo -e "Created the following certs: \\n$(md5sum $SERVERCERTS/*.*)" \n'\
                '\t fi \n'\
                '\t sed -i \\\n'\
                    '\t\t -e "\|^#*enablessl = on$|s|^#*||" \\\n'\
                    '\t\t -e "/^#*\(caprivatekeypath\|cacertificatepath\|generatedcertpath\|certprivatekeypath\) = '"'"'.*'"'"'$/s/^#*//" \\\n'\
                    '\t\t /app/config/e2guardian.conf \n'\
                '\tsed -i \\\n'\
                    '\t\t -e "/^#*\(sslmitm\|mitmcheckcert\) = on$/s/^#*//" \\\n'\
                    '\t\t /app/config/e2guardianf1.conf \n'\
            'else \n'\
                '\t if [[ "$DELCERTS" ]]; then \n'\
                    '\t\t [[ "$BACKUP" ]] && backup \n'\
                    '\t\t deletecerts \n'\
                '\t fi \n'\
            'fi \n'\
            > /app/sbin/enablesslmitm.sh && \
        chmod +750 /app/sbin/enablesslmitm.sh && \
    \
    echo '######## Enable/Disable MITM ########' && \
        args='-g -b' && \
        [[ ! $(cat /tmp/SSLMITM) = "on" ]] && args='-d'; \
        /app/sbin/enablesslmitm.sh $args


# e2guardian modifications
RUN \
    echo '######## Enable dockermode and update log location ########' && \
        sed -i \
            -e "s|^.\{0,1\}dockermode = off$|dockermode = on|g" \
            -e "\|^.\{0,1\}loglocation = '.*'$|s|'.*'|'/app/log/access.log'|" \
            -e "\|^.\{0,1\}loglocation = '.*'$|s|^#||" \
            /app/config/e2guardian.conf

#Create entrypoint script
RUN \
    echo '######## Create entrypoint script ########' && \
        echo -e '#!/bin/sh \n'\
            'PUID=${PUID:-1000} \n'\
            'PGID=${PUID:-1000} \n'\
            '\n'\
            '#Set UID and GID of e2guardian account \n'\
            '#------------------------------------- \n'\
            'groupmod -o -g $PGID e2guardian \n'\
            'usermod -o -u $PUID e2guardian \n'\
            '\n'\
            '#Verify important files in Docker volumes exist \n'\
            '#---------------------------------------------- \n'\
            '[[ -z "$(ls -A /app/config 2>/dev/null)" ]] && tar xzf /app/config.gz -C /app --strip 1 \n'\
            '[[ ! -f /app/log/access.log ]] && touch /app/log/access.log \n'\
            '\n'\
            '#Remove any existing .pid file that could prevent e2guardian from starting \n'\
            '#------------------------------------------------------------------------- \n'\
            'rm -rf /app/var/run/e2guardian.pid \n'\
            '\n'\
            '#Ensure correct ownership and permissions \n'\
            '#---------------------------------------- \n'\
            'chown -R e2guardian:e2guardian /app \n'\
            'chmod -R 700 /app/config/ssl/servercerts/*.pem /app/config/ssl/generatedcerts \n'\
            'chmod 755 /app/config/ssl/servercerts /app/config/ssl/servercerts/*.crt /app/config/ssl/servercerts/*.der \n'\
            '\n'\
            '#Start e2guardian \n'\
            '#-----------------\n'\
            '/app/sbin/e2guardian -N -c /app/config/e2guardian.conf '\
            > /app/sbin/entrypoint.sh && \
        chmod +x /app/sbin/entrypoint.sh 

RUN tar czf /app/config.gz /app/config

###
### RUNTIME STAGE
### -------------
###

FROM alpine:3.8

ENV PUID="1000" \
    PGID="1000"


VOLUME /app/config /app/log

COPY --from=builder /app /app

RUN \
    echo '######## Install required packages ########' && \
        apk add --update --no-cache libgcc libstdc++ pcre openssl shadow tini tzdata && \
    \
    echo '######## Create e2guardian account ########' && \
        groupmod -g 1000 users && \
        useradd -u 1000 -U -d /config -s /bin/false e2guardian && \
        usermod -G users e2guardian && \
    \
    echo '######## Clean-up ########' && \
        rm -rf /tmp/* /var/cache/apk/*

EXPOSE 8080

ENTRYPOINT ["/sbin/tini","-vv","-g","--","/app/sbin/entrypoint.sh"]
