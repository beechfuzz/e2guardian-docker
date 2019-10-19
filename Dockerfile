###
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
	\
	echo '######## Fix bug in e2guardian Makefile ########' && \
		sed -i '/^ipnobypass \\$/a domainsnobypass \\\nurlnobypass \\' configs/lists/Makefile.am && \
	\
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

# Create SSL certs for MITM
WORKDIR /app/config/ssl/servercerts
RUN \
	echo '######## Create SSL certs for MITM ########' && \
		echo -e '[ ca ] \n'\
        	'basicConstraints=critical,CA:TRUE \n' \
        	>> /etc/ssl/openssl.cnf && \
		if [[ $SSLMITM = "on" ]]; then \
            openssl genrsa 4096 > caprivatekey.pem && \																		
            openssl req -new -x509 -subj "$SSLSUBJ" -days 3650 -sha256 -key caprivatekey.pem -out cacertificate.crt && \
            openssl x509 -in cacertificate.crt -outform DER -out my_rootCA.der && \
            openssl genrsa 4096 > certprivatekey.pem; \
        fi && \
        mkdir ../generatedcerts

# e2guardian modifications and adduser.sh creation
WORKDIR /app/config
RUN \
	echo '######## Enable MITM ########' && \
        if [[ $SSLMITM = "on" ]]; then \
            sed -i \
				-e "s|^.\{0,1\}enablessl = off|enablessl = on|g" \
            	-e "\|^.\{0,1\}enablessl = on$|s|^#||" \
                -e "\|^.\{0,1\}caprivatekeypath = '.*'$|s|'.*'|'/app/config/ssl/servercerts/caprivatekey.pem'|" \
            	-e "\|^.\{0,1\}cacertificatepath = '.*'$|s|'.*'|'/app/config/ssl/servercerts/cacertificate.crt'|" \
            	-e "\|^.\{0,1\}generatedcertpath = '.*'$|s|'.*'|'/app/config/ssl/generatedcerts'|" \
				-e "\|^.\{0,1\}certprivatekeypath = '.*'$|s|'.*'|'/app/config/ssl/servercerts/certprivatekey.pem'|" \
				-e "/^.\{0,1\}\(caprivatekeypath\|cacertificatepath\|generatedcertpath\|certprivatekeypath\) = '.*'$/s/^#//" \
				e2guardian.conf && \
            sed -i \
				-e "/^.\{0,1\}\(sslmitm\|mitmcheckcert\) = off$/s/off$/on/" \
            	-e "/^.\{0,1\}\(sslmitm\|mitmcheckcert\) = on$/s/^#//" \
				e2guardianf1.conf; \
        fi && \
	\
	\
	echo '######## Enable dockermode and update log location ########' && \
		sed -i \
			-e "s|^.\{0,1\}dockermode = off$|dockermode = on|g" \ 
			-e "\|^.\{0,1\}loglocation = '.*'$|s|'.*'|'/app/log/access.log'|" \
			-e "\|^.\{0,1\}loglocation = '.*'$|s|^#||" \
			e2guardian.conf

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
	\
    echo '######## Create e2guardian account ########' && \
    	groupmod -g 1000 users && \
        useradd -u 1000 -U -d /config -s /bin/false e2guardian && \
        usermod -G users e2guardian && \
	\
	\
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
            > /entrypoint.sh && \
        chmod +x /entrypoint.sh && \
	\
	\
	echo '######## Clean-up ########' && \
        rm -rf /tmp/* /var/cache/apk/*

EXPOSE 8080

ENTRYPOINT ["/sbin/tini","-vv","-g","--","/entrypoint.sh"]

