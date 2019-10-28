# Quick Info
An [E2Guardian](https://github.com/e2guardian/e2guardian) Docker container with SSL MITM enabled by default; a secondary proxy is not required.  This container is based on Alpine v3.8, which is how I keep the image so small.

My goal for this container is to provide a quick and easy way to set up content filtering without too much configuration from the user.  Therefore, SSL MITM is enabled by default and SSL certs are created automatically during building.  For the most part, all the user needs to do is to manage the lists to their liking.

**CURRENT VERSION:  v5.3.3**

### What Is E2Guardian?

> E2Guardian is an Open Source web content filter that can work in proxy, transparent, or ICAP server modes.  It filters the actual content of pages based on many methods including phrase matching, request header and URL filtering, etc.  It does not purely filter based on a banned list of sites.

I ripped that straight from their website: [http://www.e2guardian.org](http://www.e2guardian.org/).

### Why Did You Do This?

Mostly because I wanted a way to document my E2Guardian setup and installation process in case I ever need to re-accomplish this again.  But also, I wanted to share with the world in case anyone else wants an easy-to-setup content filter.

### Why Docker?

Because running services in containerized environments makes installation, management, and administration much easier.  Additionally, it sandboxes your services so that they don't interfere with or interrupt the host system and other services.  Don't like or need E2Guardian anymore?  Easy, just remove the container and it's as if it never existed.

  
&nbsp;


# Quick Start

For more thorough details, see [Installing and Running](https://github.com/beechfuzz/e2guardian-docker/wiki/Installing-and-Running).

Installing and running is quite simple.  Assuming you already have [Docker installed](https://docs.docker.com/v17.09/engine/installation/), just run the following 'bare-bones' Docker command to get it up and running:

    docker run -d --name="e2guardian" \
        -p 8080:8080 \
        --restart=unless-stopped \
        beechfuzz/e2guardian

This is enough to get it up and running immediately *without any persistence*.  

If you want persistent data, then run the following command instead:

    docker run -d --name="e2guardian" \
        -v /path/to/config:/app/e2guardian/config \
        -v /path/to/log:/app/e2guardian/log \
        -p 8080:8080 \
        -e PUID=#### \
        -e PGID=#### \
        --restart=unless-stopped \
        beechfuzz/e2guardian
        
For more advanced options, see the [Installing and Running](https://github.com/beechfuzz/e2guardian-docker/wiki/Installing-and-Running#arguments) section.

&nbsp;

# Wiki

Check the [wiki](https://github.com/beechfuzz/e2guardian-docker/wiki) for more detailed information on topics that include:

* Blanket Blocking
* Important Files and Directories
* Persistence and Volumes
* PUID & PGID
* SSL MITM
* Timezone information

&nbsp;

# Credits

I did not come up with this entirely on my own; I had to borrow some ideas from other projects because I'm not into reinventing the wheel:

* [E2Guardian](http://www.e2guardian.org)
* [linuxserver](https://hub.docker.com/u/linuxserver):  Specifically, the PUID/PGID variables came from them, as well as how I implement the volumes.

