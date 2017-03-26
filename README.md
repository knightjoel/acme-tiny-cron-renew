# acme-tiny-cron-renew

This script supplements the
[diafygi/acme-tiny](https://github.com/diafygi/acme-tiny) and
[knightjoel/acme-tiny-dns](https://github.com/knightjoel/acme-tiny-dns)
scripts by providing an automated, reduced privilege way of renewing [Let's
Encrypt](https://letsencrypt.org/) certificates.

- Runs automatically via a cron job
- Runs as a non-root user
- Installs a complete certificate bundle which includes the domain's
  certificate, the Let's Encrypt intermediate certificate and the ISRG
  cross-signing root certificate
- Does not try to or need to access the domain's private key file (nor should
  you grant access to that file)

## Prerequisites

- [diafygi/acme-tiny](https://github.com/diafygi/acme-tiny) installed
- OpenSSL installed
- The steps in [diafygi/acme-tiny](https://github.com/diafygi/acme-tiny)
  README.md are followed: a Let's Encrypt account has been created and a
  private key and CSR have been created for each domain

## Assumptions

The script makes the following assumptions:

- CSR files are stored in the `/etc/ssl` directory and are named `<domain>.csr`
  (eg `/etc/ssl/packetmischief.ca.csr`)
- Once a certificate is renewed, you will be taking steps to restart your web
  server (or whatever service/daemon is using the cert) out of band of what the
  script is doing
- The python binary is in the unprivileged user's `$PATH` as either `python` or
  `python2.7`

## Installation

### Step 1: Create an unprivileged user account

If you haven't already done so when installing acme-tiny, create an unprivilved
(non-root) user account that will own the Let's Encrypt account key and be
responsible for running acme-tiny and `le_renew_certs.sh`. This is recommended
in order to avoid running any software used in this process as the root user.

The user should be a member of a unique group, and not a shared group, such as
`staff`.

In my environment, I created a user named `le` and added the user to a new
group also called `le`.

```
# id le
uid=1005(le) gid=1005(le) groups=1005(le)
```

### Step 2: Install le\_renew\_certs.sh

Copy `le_renew_certs.sh` to the unprivileged user's home directory and make it
executable.

```
# cp le_renew_certs.sh ~le
# chmod 755 ~le/le_renew_certs.sh
```

Review this list of command line options so you know how to properly execute
the script:

- `-a | --acmetiny <acme_tiny.py>`  
	The fully qualified path to the acme_tiny.py (for http
	validation) or acme_tiny_dns.py (for dns validation) script.

- `-c | --challengedir </path/to/.well-known/acme-challenge/>`  
	The fully qualified path to the `/.well-known/acme-challenge`
	directory. Must match what's configured in the web server. Must
	be writable by the user running the script.

- `-d | --domainlist <domains.txt>|domain.com`  
	Either of:  
	1) The path to a text file containing a list of domain names,
	one per line, which should have their certificate renewed.  
	2) The name of a single domain which will be renewed.

- `-k | --key <account.key>`  
	The path to the file containing the Let's Encrypt account key.  
	Default: `$workdir/le.key`

- `-v | --validation dns|http`  
	The validation method to use to prove ownership of the
	domain(s) being renewed.  
	"`dns`" - Create DNS records using acme_tiny_dns.py  
	"`http`" - Use the `/.well-known/acme-challenge/` directory via
	acme_tiny.py

- `-w | --workdir <directory>`  
	The fully qualified path to a directory to use as the working
	directory. The work directory is used to store certificates
	before pairing them with their signing certs and installing
	the bundle in `/etc/ssl`.  
	Default: `$HOME`

- `-z | --zone <domain.com>`  
	The name of the DNS zone to update when using the "dns"
	validation method.

Finally, edit the unprivileged user's crontab and add an entry to run
`le_renew_certs.sh` once a month.

```
# Renew certs at 00:15 on the 15th of each month
15      0       15       *       *       $HOME/le_renew_certs.sh -a $HOME/acme_tiny.py -k $HOME/le.key -d /etc/ssl/lets_encrypt_domains.txt -w $HOME -v http -c /var/www/htdocs/.well-known/acme-challenge/
```

### Step 3: Install Let's Encrypt certificates

The Let's Encrypt intermediate cert
is copied into a file named `<domain>.bundle.crt` along with the actual
domain's cert when a cert is renewed. This is done so that when a web browser,
for example, receives the cert from the web server, it has the entire chain of
trust from your domain's cert, all the way up to the trusted root cert.
`le_renew_certs.sh` will create `/etc/ssl/<domain>.bundle.crt` for each domain
that is renewed. This is the file that your web server should be using as your
domain's public certificate. Eg, in nginx:

```
ssl_certificate /etc/ssl/packetmiscief.ca.bundle.crt;
ssl_trusted_certificate /etc/ssl/packetmischief.ca.bundle.crt;
```

Download the following certificates from the [Let's
Encrypt](https://letsencrypt.org/certificates/) site and save them at the
specified location so `le_renew_certs.sh` knows where to find them:
- Let's Encrypt Authority X3 (pem format) ->
  `/etc/ssl/lets-encrypt-x3-cross-signed.pem`
- Let's Encrypt Authority X4 (pem format) ->
  `/etc/ssl/lets-encrypt-x4-cross-signed.pem`

The X4 cert is optional since Let's Encrypt states they use the X3 cert as
their main issuing certificate and will only revert to the X4 in the case of a
disaster. However, having the X4 in your certificate bundle prepares you for
such an event and requires minimal overhead.

### Step 4: Create `/etc/ssl/lets_encrypt_domains.txt`

The `lets_encrypt_domains.txt` file is a text file that contains a list of
domain names, one per line, that will be renewed. For each domain name in this
file, `le_renew_certs.sh` will:
- Look for a CSR at `/etc/ssl/<domain>.csr` and request a cert based on this
  CSR
- Install a certificate bundle at `/etc/ssl/<domain>.bundle.crt`

**_Do not_** include SubjAltNames in `lets_encrypt_domains.txt`; just list the
domain names that you use to name your `.csr` files. The SANs will be picked up
from the CSR.

Ensure that the unprivileged user has read access to the
`lets_encrypt_domains.txt` file.

### Step 5: Modify permissions on bundle files

Grant the unprivileged user write permissions to each `.bundle.crt` file. If
the files don't exist yet (because you haven't run the script yet or you stored
your certs in a different file), just `touch` the file and then change
permissions.

```
# touch /etc/ssl/packetmischief.ca.bundle.crt
# chgrp le /etc/ssl/packetmischief.ca.bundle.crt
# chmod 664 /etc/ssl/packetmischief.ca.bundle.crt
```

### Step 6: Test

Everything should be ready now. As the unprivileged user, execute the
`le_renew_certs.sh` script.

```
le@server% cat /etc/ssl/lets_encrypt_domains.txt
packetmischief.ca

le@server% ls -l /etc/ssl/packetmischief.ca.bundle.crt
-rw-rw-r--  1 root  le  0 Mar  8 08:51 /etc/ssl/packetmischief.ca.bundle.crt

le@server% ./le_renew_certs.sh -a $HOME/acme_tiny.py -k $HOME/le.key -d /etc/ssl/lets_encrypt_domains.txt -w $HOME -v http -c /var/www/htdocs/.well-known/acme-challenge/
+++ Renewing packetmischief.ca
Parsing account key...
Parsing CSR...
Registering account...
Already registered!
Verifying packetmischief.ca...
packetmischief.ca verified!
Verifying www.packetmischief.ca...
www.packetmischief.ca verified!
Signing certificate...
Certificate signed!

+++ Installing certificate for packetmischief.ca
Checking validity... Valid certificate file.
Installed updated certificate bundle as /etc/ssl/packetmischief.ca.bundle.crt
```

At this point the web server can be reloaded to have it pick up the new
certificate. For example, in the unprivileged user's crontab:

```
# Renew certs at 00:15 on the 15th of each month
15      0       15       *       *       $HOME/le_renew_certs.sh -a $HOME/acme_tiny.py -k $HOME/le.key -d /etc/ssl/lets_encrypt_domains.txt -w $HOME -v http -c /var/www/htdocs/.well-known/acme-challenge/ && nginx -s reload
```

