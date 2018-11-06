#!/bin/bash

# Configuration block

# Sensitive certificate data, unlocked with password

ANDROID_SUBJECT="U2FsdGVkX1+xQm5axxJR1CUX6hCwHR885mdSNEv2PCajZSsM"\
"TD8MQBOuQdK7T0cbHXNWYI+phX/EAa9kae27gHNmEuKwR/X07GXsp4jGFTwfs26g"\
"qc8OVuGEQ8eLrZtaPtKOvIt2sve0x6mds7qyaFTBqw4D6jhGiyGUoFAZgZQ="

ROOTCA_SUBJECT="U2FsdGVkX1/4tmHGHD2Tw7DwWq2QXgOUhjBwvxJFU+spCe3u+"\
"AanBUlbiaQeNoBHGOPb6NENegw8W7CgwfcdBsxXsHt/UXQVlcPzjL3zsWKvFKCsv"\
"TnenOtHLxS63ts0doswLIRAS8KV7XkCwq508hq74GjLBc0z3lgBcISmWI5wqUYRj"\
"n08TkvnPovnjEo3W0SCa62yrUHkwPIMwEKo7g=="

SSLCERT_SUBJECT="U2FsdGVkX1+htpfjJ2yCv3Q64ZrMZZTvVFypGs3tME8GcUSc"\
"RxOpXo8K0rYoK5sbhf6UgefL2cHcVAmcxhd1PKpP9BnYR9Ms/BZaDQ3q9K613V2Y"\
"IikWHNpBtrAvp9gNQc2oNKXtP7GRg7rw+nvAIUshBBNGd9OrWsno/VZDJsg="

# End of configuration block

# Get script directory

SCRIPTDIR="$(readlink -f "$0")"
SCRIPTDIR="$(dirname "$SCRIPTDIR")"

# check hostname and domain of computer

SERVER_HOSTNAME=$(cat /etc/hostname)
SERVER_DNSDOMAIN=$(grep "^search " /etc/resolv.conf | sed 's|^search ||')
SERVER_PORT=8080

if [ -z "$SERVER_HOSTNAME" ]
then
    echo "Cannot determine server hostname! Exiting..."
    exit 1
fi

if [ ! -z "$SERVER_DNSDOMAIN" ]
then
    SERVER_URL="$SERVER_HOSTNAME.$SERVER_DNSDOMAIN"
else
    SERVER_URL="$SERVER_HOSTNAME"
fi

# Check if certificates were already generated

if [ -d "$SCRIPTDIR/certs" ]
then
    echo "There are some certificates already generated!"
    echo "Please remove $SCRIPTDIR/certs and re-run this script"
    echo "if you wish to re-create them."
    echo
    echo "Exiting..."
    exit 1
fi

# Make directory storing certificates

mkdir "$SCRIPTDIR/certs"

# Unlock the certificate subject encoded line

echo -n "Enter password to unlock subject lines: "
read -s password
echo

SUBJECT=$(echo "$ANDROID_SUBJECT" | openssl enc -aes256 -base64 -d -pass env:password 2>/dev/null)
ROOTCA=$(echo "$ROOTCA_SUBJECT" | openssl enc -aes256 -base64 -d -pass env:password 2>/dev/null)
SSLCERT_TEMPLATE=$(echo "$SSLCERT_SUBJECT" | openssl enc -aes256 -base64 -d -pass env:password 2>/dev/null)
SSLCERT=$(printf "$SSLCERT_TEMPLATE" "$SERVER_URL")

if [ $? -ne 0 ]
then
    echo "Could not unlock subject line! Exiting..."
    exit 1
fi

# Ask for passpharase and verify it

echo
echo -n "Enter passphrase for keys: "
read -s password
echo

echo -n "Verify passphrase for keys: "
read -s password2
echo

if [ "$password" != "$password2" ]
then
    echo "Passphrase does not match! Exiting..."
    exit 1
fi

export password

# Generate keys with public exponent 3, keysize 2048 and
# PBE-SHA1-3DES encoding scheme to make signapk happy

for x in releasekey platform shared media
do
    openssl genrsa -3 -out "$SCRIPTDIR/certs/temp.pem" 2048
    openssl req -new -x509 -key "$SCRIPTDIR/certs/temp.pem" \
        -out "$SCRIPTDIR/certs/$x.x509.pem" -days 3650 -subj "$SUBJECT"
    openssl pkcs8 -in "$SCRIPTDIR/certs/temp.pem" -topk8 \
        -outform DER -v1 PBE-SHA1-3DES -out "$SCRIPTDIR/certs/$x.pk8" \
        -passout env:password
    shred --remove "$SCRIPTDIR/certs/temp.pem"
done

# Generate root CA and server SSL cert to be trusted by updater

openssl genrsa -3 -aes256 -passout env:password \
    -out "$SCRIPTDIR/certs/rootCA.key" 4096
openssl req -x509 -new \
    -key "$SCRIPTDIR/certs/rootCA.key" \
    -subj "$ROOTCA" -out "$SCRIPTDIR/certs/rootCA.pem" \
    -sha256 \
    -days 3650 \
    -passin env:password

openssl genrsa -3 -out "$SCRIPTDIR/certs/$SERVER_URL.key" 4096
openssl req -new \
    -key "$SCRIPTDIR/certs/$SERVER_URL.key" \
    -subj "$SSLCERT" \
    -out "$SCRIPTDIR/certs/$SERVER_URL.csr"
openssl x509 -req \
    -in "$SCRIPTDIR/certs/$SERVER_URL.csr" \
    -passin env:password \
    -CA "$SCRIPTDIR/certs/rootCA.pem" \
    -CAkey "$SCRIPTDIR/certs/rootCA.key" \
    -CAcreateserial \
    -days 730 \
    -sha256 \
    -out "$SCRIPTDIR/certs/$SERVER_URL.crt"

cat "$SCRIPTDIR/certs/$SERVER_URL.key" \
    "$SCRIPTDIR/certs/$SERVER_URL.crt" > "$SCRIPTDIR/certs/$SERVER_URL.pem"

shred --remove "$SCRIPTDIR/certs/$SERVER_URL.csr"
shred --remove "$SCRIPTDIR/certs/$SERVER_URL.key"
shred --remove "$SCRIPTDIR/certs/$SERVER_URL.crt"

echo "All done! Enjoy!"
