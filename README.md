# What This Is
 An [E2Guardian](https://github.com/e2guardian/e2guardian) Docker container with SSL MITM enabled by default; a secondary proxy is not required.

CURRENT VERSION:  v5.3.3

# What E2Guardian Is

> E2Guardian is an Open Source web content filter that can work in proxy, transparent, or ICAP server modes.  It filters the actual content of pages based on many methods including phrase matching, request header and URL filtering, etc.  It does not purely filter based on a banned list of sites.

I ripped that straight from their website: [http://www.e2guardian.org](http://www.e2guardian.org/).

# Why?
Because running services in containerized environments makes installation, management, and administration much easier.  Additionally, it sandboxes your services so that they don't interfere with or interrupt the host system and other services.
 
 I specifically made this for E2Guardian because I need a way
<!--stackedit_data:
eyJoaXN0b3J5IjpbMTcxNjc4NTY4NF19
-->