|Page Contents|
------|
[Quick Info](#quick-info) |
[Quick Start](#quick-start) |
[About This Project](#about-this-project) |
[About Me](#about-me) |


# Quick Info
An [E2Guardian](https://github.com/e2guardian/e2guardian) Docker container with **[SSL MITM](https://github.com/beechfuzz/e2guardian-docker/wiki/SSL-MITM) enabled by default**; a secondary proxy is not required.  This container is based on Alpine v3.8, which is how I keep the image so small.

My goal for this container is to provide a quick and easy way to set up content filtering without too much configuration from the user.  Therefore, SSL MITM is enabled by default and SSL certs are created automatically during building.  For the most part, all the user needs to do is to manage the lists to their liking.

**CURRENT VERSION:  v5.3.3**

### What Is E2Guardian?

> E2Guardian is an Open Source web content filter that can work in proxy, transparent, or ICAP server modes.  It filters the actual content of pages based on many methods including phrase matching, request header and URL filtering, etc.  It does not purely filter based on a banned list of sites.

I ripped that straight from their website: [http://www.e2guardian.org](http://www.e2guardian.org/).

### Docker Features
* [SSL MITM](https://github.com/beechfuzz/e2guardian-docker/wiki/SSL-MITM) enabled and configured by default
* Automatic enabling/disabling of [SSL MITM](https://github.com/beechfuzz/e2guardian-docker/wiki/SSL-MITM); not necessary to manually edit any files
* Included web-GUI ([Filebrowser](https://github.com/beechfuzz/e2guardian-docker/wiki/Filebrowser)) for easy editing of config files & lists
* Included web server ([Nweb](https://github.com/beechfuzz/e2guardian-docker/wiki/Nweb)) for painless distributing of SSL MITM CA certs for client browsers
* Included [tool](https://github.com/beechfuzz/e2guardian-docker/wiki/Important-Files-and-Directories#appsbine2g-mitmsh) for backing up and generating SSL MITM CA certs

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
        -v /path/to/config:/config \
        -v /path/to/log:/app/log \
        -p 8080:8080 \
        -e PUID=#### \
        -e PGID=#### \
        --restart=unless-stopped \
        beechfuzz/e2guardian
        
For more advanced options, see the [Installing and Running](https://github.com/beechfuzz/e2guardian-docker/wiki/Installing-and-Running#arguments) section.

&nbsp;

# About This Project

### Overall Goals

To create a well-documented and easy-to-install E2Guardian environment.  I will try to abide by these standards while maintaining this Docker image:

* **Document all the things.** One of my biggest annoyances with E2Guardian is how scattered the information is.  This makes it difficult to research and can turn people away.  I will do my best to document the most important parts and document the things that are complicated or just plain hard to find any information on.
* **Keep it intuitive.**  Any self-made features that I add will be intuitive and hopefully easy to figure out or discover in case they're not documented.

### Why Docker?

Because running services in containerized environments makes installation, management, and administration much easier.  Additionally, it sandboxes your services so that they don't interfere with or interrupt the host system and other services.  Don't like or need E2Guardian anymore?  Easy, just remove the container and it's as if it never existed.

### Why I Did This

Mostly, I wanted a way to document my E2Guardian setup and installation process in case I ever need to re-accomplish this again.  But also, I wanted to share with the world in case anyone else wants an easy-to-setup content filter.

&nbsp;

# About Me

### My Docker experience
September 2019 is when I really started playing with Docker and getting familiar with it.  In October 2019, I started creating this E2Guardian Docker project -- my first Docker image.  So, I'm still very much learning.

### My Github experience
This project is my first github project, started 18 Oct 2019.  No prior experience -- I'm still learning here, too.

&nbsp;

# Credits

I did not come up with this entirely on my own; I had to borrow some ideas from other projects because I'm not into reinventing the wheel:

* [E2Guardian](http://www.e2guardian.org)
* [linuxserver](https://hub.docker.com/u/linuxserver):  Specifically, the PUID/PGID variables came from them, as well as how I implement the volumes.
* [Filebrowser](https://filebrowser.xyz)
* [Nweb](https://github.com/ankushagarwal/nweb)
