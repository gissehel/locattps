locattps is a docker image that can quickly be used to provide https access on a website that is accessible threw http.

More and more JS API is only accessible threw https, and not http (mainly to force HTTTPS adoption).
But most developement practice consist to start the web site during developement phase on a http server, where not API are accessible.

Creating a web proxy is a task that requires a lot of small steps, that can be encapsulated in a docker image. That's what locattps is.

# Usage

Imagine you have a web application that you can start in dev mode on port 3000 on your local linux system (IP: 192.168.77.5).

You can also start the storybook of the application on the port 6000

Those applications are both started for the sake of this example

You want to browse the sites using https.

## Using locattps

```bash
$ docker pull ghcr.io/gissehel/locattps:master
```

create a directory to use with locattps for example `/opt/locattps`

```bash
$ docker run -ti -v /opt/locattps:/app ghcr.io/gissehel/locattps:master /config
```

It will create a default configuration file `/opt/locattps/locattps.yml`. Edit it

default version:

```
- listen:
    name: xdemo.locattps.local
  redirectTo:
    host:
    port:
```

Put:

```
- listen:
    name: app.locattps.local
  redirectTo:
    host: 192.168.77.5
    port: 3000
- listen:
    name: storybook.locattps.local
  redirectTo:
    host: 192.168.77.5
    port: 6000
```

Add into your /etc/hosts (as root) the values:

```
127.0.0.1 app.locattps.local
127.0.0.1 storybook.locattps.local
```

If for some reasons you don't want to edit /etc/hosts, you can use generic names on domains like nip.io that can generate names on any IP like this:

```
- listen:
    name: app.127-0-0-1.nip.io
  redirectTo:
    host: 192.168.77.5
    port: 3000
- listen:
    name: storybook.127-0-0-1.nip.io
  redirectTo:
    host: 192.168.77.5
    port: 6000
```

Then just start:

```bash
$ docker run -d -v /opt/locattps:/app -p 443:443 ghcr.io/gissehel/locattps:master
```

A file `/opt/locattps/root-*.crt` has been created. You can add this certificate as "trusted root certificate" (not as server certificate! It's important)

Go to your local brower and go to https://app.locattps.local or https://app.127-0-0-1.nip.io depending on your configuration.

Note that https://storybook.locattps.local or https://storybook.127-0-0-1.nip.io still works with another certificate.

Note that if for some reasons, you are not allowed to add a root certificate to you "trusted root certificates", you can still access the sites, but you'll need to "force" validation and ignore the fact that the certificate is not recognized. Still, javasccript API will works.

If you want to regenerate the root certificate, just remove the root certificate in `/opt/locattps/` and stop / start the container : a new one will be created.