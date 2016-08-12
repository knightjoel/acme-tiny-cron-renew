#!/bin/sh
#
# le_renew_certs.sh
#
#
# Joel Knight
# www.packetmischief.ca
# github.com/knightjoel/acme-tiny-cron-renew
# [2016.08.08]


ACME_CHALLENGES_DIR="$HOME/acme-challenges"
ACME_TINY="$HOME/acme-tiny/acme_tiny.py"
DOMAINS_TXT="/etc/ssl/lets_encrypt_domains.txt"
INTERMEDIATE_CERTS="/etc/ssl/lets-encrypt-x3-cross-signed.pem /etc/ssl/isrgrootx1.pem"
LE_KEY="$HOME/keys/account.key"
WORK_DIR="$HOME"
# if your python installation doesn't have a 'python' binary or symlink,
# uncomment the line below
alias python=/usr/local/bin/python2.7


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

