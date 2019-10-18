# Quick Info
## What Is This?
An [E2Guardian](https://github.com/e2guardian/e2guardian) Docker container with SSL MITM enabled by default; a secondary proxy is not required.  This container is based on Alpine v3.8, which is how I keep the image so small.

**CURRENT VERSION:  v5.3.3**

## What Is E2Guardian?

> E2Guardian is an Open Source web content filter that can work in proxy, transparent, or ICAP server modes.  It filters the actual content of pages based on many methods including phrase matching, request header and URL filtering, etc.  It does not purely filter based on a banned list of sites.

I ripped that straight from their website: [http://www.e2guardian.org](http://www.e2guardian.org/).

## Why Did You Do This?

Mostly because I wanted a way to document my E2Guardian setup and installation process in case I ever need to re-accomplish this again.  But also, I wanted to share with the world in case anyone else wants an easy-to-setup content filter.

## Why Docker?

Because running services in containerized environments makes installation, management, and administration much easier.  Additionally, it sandboxes your services so that they don't interfere with or interrupt the host system and other services.  Don't like or need E2Guardian anymore?  Easy, just remove the container and it's as if it never existed.

# Quick Start
Installing and running is quite simple.  Assuming you already have [Docker installed](https://docs.docker.com/v17.09/engine/installation/), just run the following Docker command to get it up and running:

    docker run -d --name="e2guardian" \
        --volume /opt/docker/volumes/e2g/config:/app/config \
        --volume /opt/docker/volumes/e2g/log:/app/log \
        --publish 8080:8080 \
        --env PUID=1011 \
        --env PGID=1011 \
        beechfuzz/e2guardian

That alone is sufficient to get it up and running immediately *without any persistence*.

## Optional Arguments
You can add the following arguments to the `docker run` command for better control over the container:


| | |
|-|-|
|--volume /opt/docker/volumes/e2g/log:/app/log | |
| | |

<!--stackedit_data:
eyJoaXN0b3J5IjpbLTE5MjEwNTg1NjYsNzE4MDU3ODYwXX0=
-->