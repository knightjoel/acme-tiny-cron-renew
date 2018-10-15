#!/bin/sh
#
# le_renew_certs.sh
#
#
# Copyright (c) 2016-2018 Joel Knight
#
# Permission is hereby granted, free of charge, to any person obtaining a copy
# of this software and associated documentation files (the "Software"), to deal
# in the Software without restriction, including without limitation the rights
# to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
# copies of the Software, and to permit persons to whom the Software is
# furnished to do so, subject to the following conditions:
#
# The above copyright notice and this permission notice shall be included in
# all copies or substantial portions of the Software.
#
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
# AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
# LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
# OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
# SOFTWARE.
#
#
# Joel Knight
# www.packetmischief.ca
# github.com/knightjoel/acme-tiny-cron-renew


unpriv_user=le
le_key="$workdir/le.key"

INTERMEDIATE_CERTS="/etc/ssl/lets-encrypt-x3-cross-signed.pem /etc/ssl/lets-encrypt-x4-cross-signed.pem /etc/ssl/lets-encrypt-x1-root.pem"


install_cert() {
	local dom=$1
	local crt="$workdir/$dom.crt"

	echo
	echo "+++ Installing certificate for $dom"
	if [ ! -f "$crt" ]; then
		echo "Cert file $crt does not exist."
		echo "Skipping."
		return
	fi

	echo -n "Checking certificate validity... "
	unpriv openssl x509 -noout -in $crt 2>/dev/null
	if [ $? -ne 0 ]; then
		echo "Invalid certificate file."
		echo "Skipping."
		return
	fi
	echo "Valid certificate file."

	name=`basename $crt`
	name=${name%%.crt}
	bundle="/etc/ssl/${name}.bundle.crt"
	if [ -w $bundle ]; then
		# as root...
		cat $crt $INTERMEDIATE_CERTS > $bundle
		echo "Installed updated certificate bundle as $bundle"
	else
		echo "Skipping installation ($bundle not writable)."
	fi
}

renew_cert() {
	local dom=$1
	local crt="$workdir/$dom.crt"

	echo
	if [ -f $crt ]; then
		echo "+++ Renewing $dom"
	else
		echo "+++ Creating a certificate for $dom"
	fi
	if [ "$validation" = "dns" ]; then
		unpriv "$_python $acmetiny \
			--account-key $key \
			--csr /etc/ssl/${dom}.csr \
			--dns-zone $zone \
			> $crt"
	elif [ "$validation" = "http" ]; then
		unpriv "$_python $acmetiny \
			--account-key $key \
			--csr /etc/ssl/${dom}.csr \
			--acme-dir $challengedir \
			> $crt"
	else
		echo "Invalid validation method. Unable to fetch certificate."
	fi
}

usage() {
	cat <<EOT
`basename $0`
	-a | --acmetiny <acme_tiny.py>
		The fully qualified path to the acme_tiny.py (for http
		validation) or acme_tiny_dns.py (for dns validation) script.

	-c | --challengedir </path/to/.well-known/acme-challenge/>
		The fully qualified path to the /.well-known/acme-challenge
		directory. Must match what's configured in the web server. Must
		be writable by the user running the script.

	-d | --domainlist <domains.txt>|domain.com
		Either of:
		1. The path to a text file containing a list of domain names,
		one per line, which should have their certificate renewed.
		2. The name of a single domain which will be renewed.

	-k | --key <account.key>
		The path to the file containing the Let's Encrypt account key.
		Default: $workdir/le.key

	-p | --python <path>
		The fully qualified path to the Python interpreter on your
		system. By default, the correct path will be searched for
		by looking for common Python versions in common locations.

	-u | --user <username>
		The name of the unprivileged user to run external commands as.
		`basename $0` will drop privileges to <username> when running
		external scripts but will use root privileges for installing
		the certificate bundle.
		Default: $unpriv_user

	-v | --validation dns|http
		The validation method to use to prove ownership of the
		domain(s) being renewed.
		"dns" - Create DNS records using acme_tiny_dns.py
		"http" - Use the /.well-known/acme-challenge/ directory via
		acme_tiny.py

	-w | --workdir <directory>
		The fully qualified path to a directory to use as the working
		directory. The work directory is used to store certificates
		before pairing them with their signing certs and installing
		the bundle in /etc/ssl.
		Default: /home/${unpriv_user}

	-z | --zone <domain.com>
		The name of the DNS zone to update when using the "dns"
		validation method.
EOT
}

unpriv() {
	eval su ${unpriv_user} -c "'$@'"
}

if [ -z "$workdir" ]; then
	workdir=/home/${unpriv_user}
fi

if [ -z "$1" ]; then
	usage
	exit 1
fi

if [ `id -u` -ne 0 ]; then
	echo "Requires root privileges."
	exit 1
fi

while [ -n "$1" ];
do
	case $1 in
		-a | --acmetiny )
			shift
			acmetiny=$1
			;;
		-c | --challengedir )
			shift
			challengedir=$1
			;;
		-d | --domainlist )
			shift
			domainlist=$1
			;;
		-k | --key )
			shift
			key=$1
			;;
		-p | --python )
			shift
			python=$1
			;;
		-u | --user )
			shift
			unpriv_user=$1
			;;
		-v | --validation )
			shift
			validation=$1
			;;
		-w | --workdir )
			shift
			workdir=$1
			;;
		-z | --zone )
			shift
			zone=$1
			;;
		* )
			usage
			exit 1
	esac
	shift
done

# validate command line and runtime options are sane
if [ -z "$acmetiny" ]; then
	echo "You must specify the path to acme_tiny.py with --acmetiny."
	exit 1
fi
if [ ! -f "$acmetiny" -a ! -h "$acmetiny" ]; then
	echo "$acmetiny doesn't appear to be a Python script."
	echo "Specify path to acme-tiny.py with --acmetiny."
	exit 1
fi

if [ -z "$domainlist" ]; then
	echo "You must specify the domain(s) to renew with --domainlist."
	exit 1
fi

if [ ! -d "$workdir" ]; then
	echo "You must specify the location of the working directory with --workdir."
	exit 1
fi

if [ -z "$key" ]; then
	key="$workdir/le.key"
fi
if [ ! -f "$key" ]; then
	echo "You must specify the location of the Let's Encrypt account key with --key."
	exit 1
fi

if [ -z "$validation" ]; then
	echo "You must specify a validation method with --validation."
	exit 1
fi
if [ "$validation" != "dns" -a "$validation" != "http" ]; then
	echo "The supported validation methods are 'dns' and 'http'."
	exit 1
fi
if [ "$validation" = "http" -a ! -d "$challengedir" ]; then
	echo "You must specify a valid challenge directory with --challengedir."
	exit 1
fi
if [ "$validation" = "dns" -a -z "$zone" ]; then
	echo "You must specify a DNS zone with --zone."
	exit 1
fi

# find the python binary
if [ -n "$python" -a -x $python ]; then
	_python=$python
elif which python >/dev/null 2>&1; then
	_python="python"
elif which python2.7 >/dev/null 2>&1; then
	_python="python2.7"
elif which python3.6 >/dev/null 2>&1; then
	_python="python3.6"
else
	echo "$0: Python is required but couldn't be found. Exiting."
	exit 1
fi

# begin
if [ -f "$domainlist" ]; then
	while :; do
		read dom || break
		case "$dom" in
		"#"*|"")
			continue
			;;
		*)
			renew_cert $dom
			install_cert $dom
			;;
		esac
	done < $domainlist
else
	renew_cert $domainlist
	install_cert $domainlist
fi

