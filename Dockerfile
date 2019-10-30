####
### BUILD STAGE
### -----------
###

FROM lsiobase/alpine:amd64-3.8 as builder
SHELL ["/bin/bash", "-c"]
ARG INSTALL_FILEBROWSER=no
ARG INSTALL_NWEBSVR=no

# Store ARGs
RUN \
    mkdir -p /tmp/args && \
    echo $INSTALL_FILEBROWSER > /tmp/args/INSTALL_FILEBROWSER && \
	echo $INSTALL_NWEBSVR > /tmp/args/INSTALL_NWEBSVR

# Install build packages
#RUN \
#    echo '######## Update and install build packages ########' && \
#    apk add --update --no-cache --virtual build-depends \
#        autoconf automake cmake g++ build-base gcc gcc-doc \
#        abuild git libpcrecpp pcre-dev pcre2 pcre2-dev \
#        openssl-dev zlib-dev binutils-doc binutils tar
RUN apk add --update --no-cache openssl 

# Download and install e2guardian from source
#WORKDIR /tmp/e2g
#ADD https://github.com/e2guardian/e2guardian/archive/5.3.3.tar.gz /tmp/e2g/
#RUN \
#    echo '######## Extract e2guardian source ########' && \
#    tar xzf 5.3.3.tar.gz --strip 1 && \
#    \
#    echo '######## Fix bug in e2guardian Makefile ########' && \
#    sed -i '/^ipnobypass \\$/a domainsnobypass \\\nurlnobypass \\' configs/lists/Makefile.am && \
#    \
#    echo '######## Compile and install e2guardian ########' && \
#    ./autogen.sh && \
#    ./configure \
#        --with-proxyuser="e2guardian" \
#        --with-proxygroup="e2guardian" \
#        --prefix="/app" \
#        --sysconfdir="/config" \
#        --sbindir='${prefix}/sbin' \
#        --with-logdir='${prefix}/log' \
#	--with-piddir='${prefix}/pid' \
#        --with-sysconfsubdir= \
#        --enable-sslmitm="yes" \
#        --enable-icap="yes" \
#        --enable-clamd="yes" \
#        --enable-commandline="yes" \
#        --enable-email="yes" \
#        --enable-ntlm="yes" \
#        -enable-pcre="yes" \
#        'CPPFLAGS=-mno-sse2 -g -O2' && \
#    make -j 16 && make install && \
#    mkdir -p \
#        /config/ssl/generatedcerts \
#        /config/ssl/servercerts

# e2guardian prep and configuration
COPY sources/e2guardian_5.3.3/e2g_post-makeinstall.tar.gz \
	 sources/nweb/nweb23.c \
	 /tmp/
RUN tar xzf /tmp/e2g_post-makeinstall.tar.gz -C /
COPY app/sbin/* /app/sbin/
RUN \
    echo '######## Set permissions for /app/sbin scripts ########' && \
    chmod u+x /app/sbin/e2g-mitm.sh /app/sbin/entrypoint.sh && \
    \
    echo '######## Enable MITM ########' && \
    /app/sbin/e2g-mitm.sh -Eb && \
    \
    echo '######## Enable dockermode ########' && \
    sed -i "s|^.\{0,1\}dockermode = off$|dockermode = on|g" /config/e2guardian.conf

# Filebrowser
RUN \
    echo '######## Install Filebrowser if specified ########' && \
    if [[ $(cat /tmp/args/INSTALL_FILEBROWSER) = "yes" ]]; then \
		echo 'INSTALLING FILEBROWSER...' && \
        apk add --update --no-cache curl && \
		mkdir -p /config/filebrowser && \
        curl -fsSL https://filebrowser.xyz/get.sh | bash && \
        mv $(which filebrowser) /app/sbin && \
        chmod +x /app/sbin/filebrowser; \
    fi

# nweb server
RUN \
    echo '######## Install nweb if specified ########' && \
#    if [[ $(cat /tmp/args/INSTALL_NWEBSVR) = "yes" ]]; then \
#		mkdir /tmp/nweb /app/nweb && \
#		cd /tmp/nweb && \
#		curl -fsSL https://raw.githubusercontent.com/ankushagarwal/nweb/master/nweb23.c -o nweb23.c && \
#		cat nweb23.c | tr '\n' '\r' | \
#			sed -e 's/\
#				{"gif", "image\/gif" },.*\r.*{"htm", "text\/html" },/\
#				{"crt","application\/x-x509-ca-cert"},\n {"der","application\/x-x509-ca-cert"},/' | \
#			tr '\r' '\n' > nweb23.c && \
#		gcc -O2 /tmp/nweb23.c -o /app/sbin/nweb; \
#		echo -e \
#			'<a href="cacertificate.crt">CA Certificate (crt)</a><p>\' \
#			'<a href="cacertificate.der">CA Certificate (der)</a>' \
#			> /config/ssl/servercerts/index.html; \
#	fi
	[[ $(cat /tmp/args/INSTALL_NWEBSVR) = "yes" ]] && \
		echo "INSTALLING NWEB SERVER" && \
		apk add --update --no-cache gcc libc-dev && \
		gcc -O2 /tmp/nweb23.c -o /app/sbin/nweb --static && \
		mkdir -p /app/nweb && \
		echo -e \
			'<a href="cacertificate.crt">CA Certificate (crt)</a><p>' \
			'<a href="cacertificate.der">CA Certificate (der)</a>' \
			> /app/nweb/index.html && \
		ln -s /config/ssl/servercerts/cacertificate.crt /app/nweb/cacertificate.crt && \
		ln -s /config/ssl/servercerts/cacertificate.der /app/nweb/cacertificate.der

RUN \
    tar czf /app/config.gz /config 

###
### RUNTIME STAGE
### -------------
###

FROM alpine:3.8

ENV PATH="${PATH}:/app/sbin" \
    PUID="1000" \
    PGID="1000" 

VOLUME /config /app/log

COPY --from=builder /app /app

RUN \
    echo '######## Install required packages ########' && \
    apk add --update --no-cache libgcc libstdc++ pcre openssl shadow tini tzdata && \
    \
    echo '######## Modify openssl.cnf ########' && \
    echo -e \
        '[ ca ] \n'\
        'basicConstraints=critical,CA:TRUE \n' \
        >> /etc/ssl/openssl.cnf && \
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
