#!/bin/sh
#
# le_renew_certs.sh
#
#
# Copyright (c) 2016 Joel Knight
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


ACME_CHALLENGES_DIR="$HOME/acme-challenges"
ACME_TINY="$HOME/acme-tiny/acme_tiny.py"
DOMAINS_TXT="/etc/ssl/lets_encrypt_domains.txt"
INTERMEDIATE_CERTS="/etc/ssl/lets-encrypt-x{3,4}-cross-signed.pem"
LE_KEY="$HOME/keys/account.key"
WORK_DIR="$HOME"

python -V >/dev/null 2>&1 || {
	alias python=python2.7
	python2.7 -V >/dev/null 2>&1 || {
		echo "Python is required but couldn't be found. Exiting."
		exit 1
	}
}

install_cert() {
	local dom=$1
	local crt="$WORK_DIR/$dom.crt"

	echo
	echo "+++ Installing certificate for $dom"
	if [ ! -f "$crt" ]; then
		echo "Cert file $crt does not exist."
		echo "Skipping."
		return
	fi

	echo -n "Checking certificate validity... "
	openssl x509 -noout -in $crt 2>/dev/null
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
		cat $crt $INTERMEDIATE_CERTS > $bundle
		echo "Installed updated certificate bundle as $bundle"
	else
		echo "Skipping installation ($bundle not writable)."
	fi
}

renew_cert() {
	local dom=$1
	local crt="$WORK_DIR/$dom.crt"

	echo
	if [ -f $crt ]; then
		echo "+++ Renewing $dom"
	else
		echo "+++ Creating a certificate for $dom"
	fi
	python $ACME_TINY \
		--account-key $LE_KEY \
		--csr /etc/ssl/${dom}.csr \
		--acme-dir $ACME_CHALLENGES_DIR \
		> $crt
}

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
done < $DOMAINS_TXT

