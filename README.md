# acme-tiny-cron-renew

This script supplements the
[diafygi/acme-tiny](https://github.com/diafygi/acme-tiny) and
[knightjoel/acme-tiny-dns](https://github.com/knightjoel/acme-tiny-dns)
scripts by providing an automated, reduced privilege way of renewing [Let's
Encrypt](https://letsencrypt.org/) certificates.

- Runs automatically via a cron job
- Drops privileges to a non-root user for doing the actual renewal operation
- Uses root privileges only for installing the renewed, validated certificate
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
responsible for running acme-tiny.

In my environment, I created a user named `le`.

```
# id le
uid=1005(le) gid=1005(le) groups=1005(le)
```

Alternatively, you could just use your regular, non-root account.

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

- `-p | --python <path>`  
	The fully qualified path to the Python interpreter on your
	system. By default, the correct path will be searched for
	by looking for common Python versions in common locations.

- `-u | --user <username>`
	The name of the unprivileged user to run external commands as.
	le_renew_certs.sh will drop privileges to <username> when running
	external scripts but will use root privileges for installing
	the certificate bundle.
	Default: le

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
	Default: `/home/le`

- `-z | --zone <domain.com>`  
	The name of the DNS zone to update when using the "dns"
	validation method.

Finally, edit root's crontab and add an entry to run
`le_renew_certs.sh` once a month.

```
# Renew certs at 00:15 on the 15th of each month
15      0       15       *       *       /home/le/le_renew_certs.sh -a /home/le/acme_tiny.py -k /home/le/le.key -d /etc/ssl/lets_encrypt_domains.txt -w /home/le -v http -c /var/www/htdocs/.well-known/acme-challenge/
```

### Step 3: Understand the Certificate Bundle

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

### Step 5: Test

Everything should be ready now. As root, execute the
`le_renew_certs.sh` script.

```
root@server# cat /etc/ssl/lets_encrypt_domains.txt
packetmischief.ca

root@server# ls -l /etc/ssl/packetmischief.ca.bundle.crt
-rw-rw-r--  1 root  le  0 Mar  8 08:51 /etc/ssl/packetmischief.ca.bundle.crt

root@server# ./le_renew_certs.sh -a /home/le/acme_tiny.py \
  -c /var/www/htdocs/.well-known/acme-challenge/
  -k /home/le/le.key \
  -d /etc/ssl/lets_encrypt_domains.txt \
  -u le \
  -v http \
  -w /home/le \

+++ Renewing packetmischief.ca
Parsing account key...
Parsing CSR...
Found domains: packetmischief.ca, www.packetmischief.ca
Getting directory...
Directory found!
Registering account...
Already registered!
Creating new order...
Order created!
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
certificate.
