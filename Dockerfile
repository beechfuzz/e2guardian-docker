####
### BUILD STAGE
### -----------
###
 
FROM lsiobase/alpine:amd64-3.8 as builder
SHELL ["/bin/bash", "-c"]
ARG SSLMITM=on
ARG SSLSUBJ='/CN=e2guardian/O=e2guardian/C=US'
ENV enable_sslmitm=yes

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
        if [[ $SSLMITM = "off" ]]; then enable_sslmitm="no"; fi && \
        ./autogen.sh && \
        ./configure \
            '--with-proxyuser=e2guardian' \
            '--with-proxygroup=e2guardian' \
            '--prefix=/app' \
            '--sysconfdir=${prefix}/config' \
            '--with-sysconfsubdir=' \
            "--enable-sslmitm=$enable_sslmitm" \
            '--enable-icap=yes' \
            '--enable-clamd=yes' \
            '--enable-commandline=yes' \
            '--enable-email=yes' \
            '--enable-ntlm=yes' \
            '--enable-pcre=yes' \
            'CPPFLAGS=-mno-sse2 -g -O2' && \
        make -j 16 && make install

# SSL MITM modifications
WORKDIR /app/config/ssl/servercerts
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
			'ENABLE_SSLMITM=${1:-"on"} \n'\
			'SERVERCERTS="/app/config/ssl/servercerts" \n'\
			'[ $ENABLE_SSLMITM = "on" ] && TOGGLE="off" || TOGGLE="on" \n'\
			'\n'\
            '\n'\
			'#Toggle SSL and modify paths of SSL certs/keys \n'\
            '#--------------------------------------------- \n'\
            'sed -i \\\n'\
                '\t-e "s|enablessl = $TOGGLE|enablessl = $ENABLE_SSLMITM|g" \\\n'\
                '\t-e "\|caprivatekeypath = '"'"'.*'"'"'$|s|'"'"'.*'"'"'|'"'"'/app/config/ssl/servercerts/caprivatekey.pem'"'"'|" \\\n'\
                '\t-e "\|cacertificatepath = '"'"'.*'"'"'$|s|'"'"'.*'"'"'|'"'"'/app/config/ssl/servercerts/cacertificate.crt'"'"'|" \\\n'\
                '\t-e "\|generatedcertpath = '"'"'.*'"'"'$|s|'"'"'.*'"'"'|'"'"'/app/config/ssl/generatedcerts'"'"'|" \\\n'\
                '\t-e "\|certprivatekeypath = '"'"'.*'"'"'$|s|'"'"'.*'"'"'|'"'"'/app/config/ssl/servercerts/certprivatekey.pem'"'"'|" \\\n'\
                '\t/app/config/e2guardian.conf \n'\
			'sed -i \\\n'\
                '\t-e "/\(sslmitm\|mitmcheckcert\) = $TOGGLE$/s/$TOGGLE$/$ENABLE_SSLMITM/" \\\n'\
                '\t/app/config/e2guardianf1.conf \n'\
            '\n'\
			'\n'\
			'#Generate required SSL certs and uncomment required lines\n'\
            '#--------------------------- \n'\
			'if [[ $ENABLE_SSLMITM = "on" ]]; then \n'\
				'\t#Root CA Private Key \n'\
				'\topenssl genrsa 4096 > $SERVERCERTS/caprivatekey.pem \n'\
                '\t#Root CA Public Key (.crt) \n'\
				'\topenssl req -new -x509 -subj "/CN=e2guardian/O=e2guardian/C=US" -days 3650 -sha256 -key $SERVERCERTS/caprivatekey.pem -out $SERVERCERTS/cacertificate.crt \n'\
                '\t#Root CA Public Key (.der)\n'\
				'\topenssl x509 -in ${SERVERCERTS}/cacertificate.crt -outform DER -out $SERVERCERTS/my_rootCA.der \n'\
                '\t#Private Key for upstream SSL certs\n'\
				'\topenssl genrsa 4096 > $SERVERCERTS/certprivatekey.pem \n'\
				'\tsed -i \\\n'\
                	'\t\t-e "\|^#*enablessl = on$|s|^#*||" \\\n'\
					'\t\t-e "/^#*\(caprivatekeypath\|cacertificatepath\|generatedcertpath\|certprivatekeypath\) = '"'"'.*'"'"'$/s/^#*//" \\\n'\
                	'\t\t/app/config/e2guardian.conf \n'\
            	'\tsed -i \\\n'\
                	'\t\t-e "/^#*\(sslmitm\|mitmcheckcert\) = on$/s/^#*//" \\\n'\
                	'\t\t/app/config/e2guardianf1.conf \n'\
			'fi \n'\
			> /app/sbin/enablesslmitm.sh && \
		chmod +750 /app/sbin/enablesslmitm.sh

# e2guardian modifications
WORKDIR /app/config
RUN \
    echo '######## Enable/Disable MITM ########' && \
		/app/sbin/enablesslmitm.sh "$SSLMITM" && \
    \
    echo '######## Enable dockermode and update log location ########' && \
        sed -i \
            -e "s|^.\{0,1\}dockermode = off$|dockermode = on|g" \ 
            -e "\|^.\{0,1\}loglocation = '.*'$|s|'.*'|'/app/log/access.log'|" \
            -e "\|^.\{0,1\}loglocation = '.*'$|s|^#||" \
            e2guardian.conf

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
        apk add --update --no-cache libgcc libstdc++ pcre openssl shadow tini && \
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
