Installation steps
==================

Install this project in a new directory in ``/opt`` and clone acme-tiny into it:

.. code-block:: sh

    useradd --base-dir /opt --create-home --user-group --system --shell /bin/false acme-tiny
    cd /opt/acme-tiny
    sudo -u acme-tiny git clone https://github.com/fishilico/acme-tiny
    mv acme-tiny/* acme-tiny/.[a-z]* .
    sudo -u acme-tiny mkdir certs
    sudo -u acme-tiny wget -O certs/intermediate.pem https://letsencrypt.org/certs/lets-encrypt-x3-cross-signed.pem

Create an account key:

.. code-block:: sh

    (umask 77 && openssl genrsa 4096 > /opt/acme-tiny/account.key)
    chown acme-tiny: /opt/acme-tiny/account.key
    chmod 0400 /opt/acme-tiny/account.key

Configure a directory were ACME challenge files will be created:

.. code-block:: sh

    mkdir -p /var/www/acme-challenges/
    chown www-data:acme-tiny /var/www/acme-challenges/
    chmod 170 /var/www/acme-challenges/

Configure the web server to serve this directory for the domains handled by the server. For example on NGINX:

.. code-block:: nginx

    server {
        listen 80;
        server_name example.org www.example.org;

        location /.well-known/acme-challenge/ {
            alias /var/www/acme-challenges/;
            try_files $uri =404;
        }
        location / {
            return 301 https://$server_name$request_uri;
        }
    }

For Apache:

.. code-block:: apache

    <VirtualHost *:80>
        ServerName www.example.org;
        ServerAlias example.org;

        Alias /.well-known/acme-challenge/ "/var/www/acme-challenges/"
        <Directory "/var/www/acme-challenges">
            Options -Indexes
            AllowOverride None
            # Disable PHP if it is used as an Apache module
            php_flag engine off
            <IfVersion >= 2.4>
                Require all granted
            </IfVersion>
            <IfVersion < 2.4>
                Order allow,deny
                Allow from all
            </IfVersion>
        </Directory>

        RedirectMatch permanent ^/((?!.well-known/acme-challenge/).*)$ https://www.example.org/$1

        # Add a <Location> block when the access to / is filtered
        <Location "/.well-known/acme-challenge/">
            Options -Indexes
            AllowOverride None
            php_flag engine off
            <IfVersion >= 2.4>
                Require all granted
            </IfVersion>
            <IfVersion < 2.4>
                Order allow,deny
                Allow from all
            </IfVersion>
        </Location>
    </VirtualHost>

On a systemd system, install the timer:

.. code-block:: sh

    install -m644 systemd/acme-tiny.service /etc/systemd/system/
    install -m644 systemd/acme-tiny.timer /etc/systemd/system/
    systemctl daemon-reload
    systemctl enable --run acme-tiny.timer

On a system without systemd and with cron, configure a cron task which runs on the 7 of 21 of each month in ``/etc/cron.d/acme-tiny``:

.. code-block:: sh

    # Install a log directory with: install -d -o acme-tiny -g acme-tiny -m 700 /var/log/acme-tiny
    0 0 7,21 * * acme-tiny /opt/acme-tiny/renew_cert.sh >> /var/log/acme-tiny/acme-tiny.log 2>&1

Add a new domain certificate:

.. code-block:: sh

    DOMAIN=my.domain.example.org
    KEYPATH="/etc/ssl/nginx/$DOMAIN.key" # or "/etc/apache2/ssl/$DOMAIN.key"
    # Create an RSA key (as root) and its associated certificate signing request
    (umask 77 && openssl genrsa 4096 > "$KEYPATH")
    openssl req -new -sha256 -key "$KEYPATH" -subj "/CN=$DOMAIN" > "/opt/acme-tiny/certs/$DOMAIN.csr"

    # For multiple domains, like www.example.org and example.org
    openssl req -new -sha256 -key "$KEYPATH" -subj "/" -reqexts SAN -config <(cat /etc/ssl/openssl.cnf <(printf "[SAN]\nsubjectAltName=DNS:example.org,DNS:www.example.org")) > "/opt/acme-tiny/certs/$DOMAIN.csr"


    # Run acme-tiny.py
    sudo -u acme-tiny python /opt/acme-tiny/acme_tiny.py --account-key /opt/acme-tiny/account.key --csr "/opt/acme-tiny/certs/$DOMAIN.csr" --acme-dir /var/www/acme-challenges/ > "/opt/acme-tiny/certs/$DOMAIN.crt"
    cat "certs/$DOMAIN.crt" certs/intermediate.pem > "certs/$DOMAIN.chained.pem"

Renew all the certificates in ``/opt/acme-tiny/certs``:

.. code-block:: sh

    sudo -u acme-tiny /opt/acme-tiny/renew_cert.sh

In order to use the certicates, the server configuration need to be configured for example like this on NGINX:

.. code-block:: nginx

    server {
        listen 443;
        server_name example.org www.example.org;

        ssl on;
        ssl_certificate /opt/acme-tiny/certs/www.example.org.chained.pem;
        ssl_certificate_key /etc/ssl/nginx/www.example.org.key;
        ssl_dhparam /etc/ssl/dhparam.pem;
        ssl_session_timeout 5m;
        ssl_session_cache shared:SSL:10m;

        # ...
    }

And for Apache:

.. code-block:: apache

    <VirtualHost 127.0.0.1:443>
        ServerName www.example.org
        ServerAlias example.org

        SSLEngine on
        SSLCertificateFile /opt/acme-tiny/certs/example.org.crt
        SSLCertificateChainFile /opt/acme-tiny/certs/intermediate.pem
        SSLCertificateKeyFile /etc/apache2/ssl/example.org.key

        # ...
    </VirtualHost>
