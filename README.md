## Quick Info
### What Is This?
An [E2Guardian](https://github.com/e2guardian/e2guardian) Docker container with SSL MITM enabled by default; a secondary proxy is not required.  This container is based on Alpine v3.8, which is how I keep the image so small.

My goal for this container is to provide a quick and easy way to set up conte

**CURRENT VERSION:  v5.3.3**

### What Is E2Guardian?

> E2Guardian is an Open Source web content filter that can work in proxy, transparent, or ICAP server modes.  It filters the actual content of pages based on many methods including phrase matching, request header and URL filtering, etc.  It does not purely filter based on a banned list of sites.

I ripped that straight from their website: [http://www.e2guardian.org](http://www.e2guardian.org/).

### Why Did You Do This?

Mostly because I wanted a way to document my E2Guardian setup and installation process in case I ever need to re-accomplish this again.  But also, I wanted to share with the world in case anyone else wants an easy-to-setup content filter.

### Why Docker?

Because running services in containerized environments makes installation, management, and administration much easier.  Additionally, it sandboxes your services so that they don't interfere with or interrupt the host system and other services.  Don't like or need E2Guardian anymore?  Easy, just remove the container and it's as if it never existed.

  
&nbsp;


## Quick Start
Installing and running is quite simple.  Assuming you already have [Docker installed](https://docs.docker.com/v17.09/engine/installation/), just run the following 'bare-bones' Docker command to get it up and running:

    docker run -d --name="e2guardian" \
        -p 8080:8080 \
        --restart=unless-stopped \
        beechfuzz/e2guardian

This is enough to get it up and running immediately *without any persistence*.  

If you want persistent data, then run the following command instead:

    docker run -d --name="e2guardian" \
        -v /path/to/config:/app/config \
        -v /path/to/log:/app/log \
        -p 8080:8080 \
        -e PUID=#### \
        -e PGID=#### \
        --restart=unless-stopped \
        beechfuzz/e2guardian
You can read more about the `-v` parameter, and the `PUID` and `PGID` variables in the [Optional Arguments](#optional-arguments) section below.

### Optional Arguments
You can add the following arguments to the `docker run` command for better control over the container:

|Argument |Meaning |
|-|-|
|`-v /path/to/config:/app/config`|Make config files and lists persistent|
|`-v /path/to/log:/app/log`| Make logs persistent|
|`-e PUID=####`| Specify UID to use inside the container.  [More info](#puidpgid) below.|
|`-e PGID=####`| Specify GID to use inside the container.  [More info](#puidpgid) below.|

#### Persistence and Volumes
The data on a container does not persist when that container no longer exists.   Therefore, we use volumes to enable persistent data within our containers.  You add a volume to a container via the `-v` parameter.  The syntax for the parameter is:
    
    -v /host/path:/container/path

`/host/path` is the path on the local host machine where you want the Docker volume to reside, and can be anywhere you want, as long as the user account that is running the Docker daemon can read/write to it (more info in _'PUID/PGID'_ section below).  

`/container/path` is the path inside of the container that will be made available to the local host.  

In this container, you really only need the `/app/config` volume.  This is the location for all of the E2Guardian configuration files and lists.  Enabling this volume will allow you to make configuration changes without having to create a shell directly into the container.   

This container also has an `/app/log` volume where the `access.log` file resides.  This volume is not necessary, but it is convenient to be able to access the log from within the host machine without having to shell directly into the container.

Let's say you want the `/app/config` volume in the container to be available at `/docker/volumes/e2g/config` on the host.  You would add the following `-v` parameter to your `docker run` command:

    -v /docker/volumes/e2g/config:/app/config

#### PUID/PGID
From [linuxserver.io](https://github.com/linuxserver/docker-nzbget#user--group-identifiers):

> When using volumes (`-v` flags) permissions issues can arise between
> the host OS and the container.  We avoid this issue by allowing you to
> specify the user  `PUID`  and group  `PGID`.
> 
> Ensure any volume directories on the host are owned by the same user
> you specify and any permissions issues will vanish like magic.

Basically, if the UID/GID of the account that runs the E2Guardian daemon inside the container doesn't match the UID/GID of the account on the host that owns the volumes, then you may run into permissions issues.  The  `PUID` and `PGID` environment variables fix that by changing the UID and GID of the e2guardian user account inside the container.  Therefore, it's advisable to set the `PUID` and `PGID` variables to the UID and GID of the user on the host that will be owning the volume.  The default in this container is  `PUID=1000`  and  `PGID=1000`.  

To find yours, run the  `id <user>`  command in your host.  Example:

    $ ls -al /docker/volumes/
    drwxr-xr-x 14 root          root          4096 Oct 16 21:01 .
    drwxr-xr-x  3 root          root          4096 Aug 26 19:59 ..
    drwxr-xr-x  4 dockeruser    dockeruser    4096 Oct 18 15:52 e2g

    $ id dockeruser
     uid=1011(dockeruser) gid=1011(dockeruser) groups=1011(dockeruser)

In the output of the first command, you can see that the `dockeruser` account owns the `e2g` folder (which will be used for the volume) on the host.    Running `id dockeruser` outputs the UID and GID.  Therefore, I would add `-e PUID=1011` and `-e PGID=1011` to my `docker run` command, like so:

    docker run -d --name="e2guardian" \
        -v /docker/volumes/e2g/config:/app/config \
        -p 8080:8080 \
        -e PUID=1011 \
        -e PGID=1011 \
        beechfuzz/e2guardian


<!--stackedit_data:
eyJoaXN0b3J5IjpbMjA1MTcxNzYyMCwtNTY4NjgwMzA4LDcyND
U1NjgxMyw3MTgwNTc4NjBdfQ==
-->