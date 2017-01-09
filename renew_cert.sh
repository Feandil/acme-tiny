#!/bin/sh
# Renew every generated certificates.
# Run this script and then reload the web server.

ACMETINY_DIR="$(dirname -- "$0")"
CERT_DIR="$ACMETINY_DIR/certs"
ACME_DIR=/var/www/acme-challenges/

# Give at least 7 days between each renewal
RENEW_DAYS=7

if [ "$(id -u)" = 0 ]
then
    echo >&2 "Error: please run $0 as a non-root user"
    exit 1
fi

# Download intermediate cert
INTCERT="$CERT_DIR/intermediate.pem"
if ! [ -e "$INTCERT" ]
then
    wget -O "$INTCERT" https://letsencrypt.org/certs/lets-encrypt-x3-cross-signed.pem || exit $?
fi
if ! [ -r "$INTCERT" ]
then
    echo >&2 "Error: unable to read $INTCERT"
    exit 1
fi

for CSRFILE in "$CERT_DIR/"*.csr
do
    FILENAME="${CSRFILE##*/}"
    DOMAIN="${FILENAME%.csr}"

    # Get the delivery timestamp of the currently active certificate
    CRT_FILE="$CERT_DIR/$DOMAIN.crt"
    LAST_DATE="$(openssl x509 -noout -startdate -in "$CRT_FILE" 2>/dev/null | \
        sed -n 's/^notBefore=//p')"
    if [ -n "$LAST_DATE" ]
    then
        LAST_TS="$(date '+%s' --date "$LAST_DATE")"
        NOW_TS="$(date '+%s')"
        if [ -n "$LAST_TS" ] && [ $(($NOW_TS - $LAST_TS)) -lt $(($RENEW_DAYS * 86400)) ]
        then
            echo "[+] Certificate for $DOMAIN is recent ($LAST_DATE)"
            continue
        fi
    fi

    # Use timestamp to create unique files
    TS="$(date '+%Y-%m-%d_%H-%M-%S')"

    echo "[ ] Renewing $DOMAIN"
    if ! python "$ACMETINY_DIR/acme_tiny.py" \
        --account-key "$ACMETINY_DIR/account.key" \
        --csr "$CSRFILE" \
        --acme-dir "$ACME_DIR" > "$CERT_DIR/${TS}_$DOMAIN.crt"
    then
        echo "[-] Error with $DOMAIN"
        continue
    fi

    if ! cat "$CERT_DIR/${TS}_$DOMAIN.crt" "$INTCERT" > "$CERT_DIR/${TS}_$DOMAIN.chained.pem"
    then
        echo "[-] Unable to chain $DOMAIN"
        continue
    fi

    # Symlink new certificates
    ln -sf "${TS}_$DOMAIN.crt" "$CERT_DIR/$DOMAIN.crt"
    ln -sf "${TS}_$DOMAIN.chained.pem" "$CERT_DIR/$DOMAIN.chained.pem"
done
