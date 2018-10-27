#!/bin/bash

# Configuration block

# Sensitive certificate data, unlocked with password

ENCODED_SUBJECT="U2FsdGVkX1+xQm5axxJR1CUX6hCwHR885mdSNEv2PCajZSsM"\
"TD8MQBOuQdK7T0cbHXNWYI+phX/EAa9kae27gHNmEuKwR/X07GXsp4jGFTwfs26g"\
"qc8OVuGEQ8eLrZtaPtKOvIt2sve0x6mds7qyaFTBqw4D6jhGiyGUoFAZgZQ="

# End of configuration block

# Get script directory

SCRIPTDIR="$(readlink -f "$0")"
SCRIPTDIR="$(dirname "$SCRIPTDIR")"

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

SUBJECT=$(echo "$ENCODED_SUBJECT" | openssl enc -aes256 -base64 -d 2>/dev/null)

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
    openssl req -new -x509 -key "$SCRIPTDIR/certs/temp.pem" -out "$SCRIPTDIR/certs/releasekey.x509.pem" -days 3650 -subj "$SUBJECT"
    openssl pkcs8 -in "$SCRIPTDIR/certs/temp.pem" -topk8 -outform DER -v1 PBE-SHA1-3DES -out "$SCRIPTDIR/certs/releasekey.pk8" -passout env:password
    shred --remove "$SCRIPTDIR/certs/temp.pem"
done

echo "All done! Enjoy!"
