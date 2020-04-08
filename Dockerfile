####
### BUILD STAGE
### -----------
###

FROM lsiobase/alpine:amd64-3.8 as builder
SHELL ["/bin/bash", "-c"]

# e2guardian prep and configuration
COPY sources/e2guardian_5.3.3/e2g_post-makeinstall.tar.gz \
     sources/nweb/nweb.c \
     /tmp/
COPY app/sbin/* /app/sbin/
RUN \
    echo '######## Extract e2g_post-makeinstall files  ########' && \
    tar xzf /tmp/e2g_post-makeinstall.tar.gz -C / && \
    \
    echo '######## Enable dockermode ########' && \
    sed -i "s|^.\{0,1\}dockermode = off$|dockermode = on|g" /config/e2guardian.conf

# Filebrowser and Nweb
RUN \
    echo '######## Install build packages ########' && \
    apk add --update --no-cache curl gcc libc-dev argp-standalone linux-headers && \
    \
    echo '######## Install Filebrowser ########' && \
    mkdir -p /config/filebrowser && \
    curl -fsSL https://filebrowser.xyz/get.sh | bash && \
    mv $(which filebrowser) /app/sbin && \
    chmod +x /app/sbin/filebrowser && \
    \
    echo '######## Install Nweb ########' && \
    gcc -O2 /tmp/nweb.c -o /app/sbin/nweb --static -largp && \
    mkdir -p /app/nweb && \
    echo -e \
        '<a href="cacertificate.crt">CA Certificate (crt)</a><p>' \
        '<a href="my_rootCA.der">CA Certificate (der)</a>' \
        > /app/nweb/index.html

# Set permissions and backup /config directory
RUN \
    echo '######## Set permissions for /app/sbin scripts ########' && \
    chmod u+x /app/sbin/e2g-mitm.sh /app/sbin/entrypoint.sh && \
    tar czf /app/config.gz /config


###
### RUNTIME STAGE
### -------------
###

FROM alpine:3.8

ENV PATH="${PATH}:/app/sbin" \
    PUID="1000" \
    PGID="1000" \
    E2G_MITM=${E2G_MITM:-"on"} \
    FILEBROWSER=${FILEBROWSER:-"off"} \
    FILEBROWSER_ADDR=${FILEBROWSER_ADDR:-"0.0.0.0"} \
    FILEBROWSER_PORT=${FILEBROWSER_PORT:-"80"} \
    FILEBROWSER_ROOT=${FILEBROWSER_ROOT:-"/config"} \
    FILEBROWSER_DB=${FILEBROWSER_DB:-"/config/filebrowser/database.db"} \
    FILEBROWSER_LOG=${FILEBROWSER_LOG:-"/app/log/filebrowser.log"} \
    NWEB=${NWEB:-"off"} \
    NWEB_PORT=${NWEB_PORT:-"81"}


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
