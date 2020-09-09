#!/usr/bin/with-contenv bash

# From https://github.com/docker-library/mariadb/blob/master/docker-entrypoint.sh#L21-L41
# usage: file_env VAR [DEFAULT]
#    ie: file_env 'XYZ_DB_PASSWORD' 'example'
# (will allow for "$XYZ_DB_PASSWORD_FILE" to fill in the value of
#  "$XYZ_DB_PASSWORD" from a file, especially for Docker's secrets feature)
file_env() {
  local var="$1"
  local fileVar="${var}_FILE"
  local def="${2:-}"
  if [ "${!var:-}" ] && [ "${!fileVar:-}" ]; then
    echo >&2 "error: both $var and $fileVar are set (but are exclusive)"
    exit 1
  fi
  local val="$def"
  if [ "${!var:-}" ]; then
    val="${!var}"
  elif [ "${!fileVar:-}" ]; then
    val="$(< "${!fileVar}")"
  fi
  export "$var"="$val"
  unset "$fileVar"
}

TZ=${TZ:-UTC}
MEMORY_LIMIT=${MEMORY_LIMIT:-256M}
UPLOAD_MAX_SIZE=${UPLOAD_MAX_SIZE:-16M}
OPCACHE_MEM_SIZE=${OPCACHE_MEM_SIZE:-128}
LISTEN_IPV6=${LISTEN_IPV6:-true}
REAL_IP_FROM=${REAL_IP_FROM:-0.0.0.0/32}
REAL_IP_HEADER=${REAL_IP_HEADER:-X-Forwarded-For}
LOG_IP_VAR=${LOG_IP_VAR:-remote_addr}

APP_NAME=${APP_NAME:-AnonAddy}
#APP_KEY=${APP_KEY:-base64:Gh8/RWtNfXTmB09pj6iEflt/L6oqDf9ZxXIh4I9MS7A=}
APP_DEBUG=${APP_DEBUG:-false}
APP_URL=${APP_URL:-http://localhost}

#DB_HOST=${DB_HOST:-localhost}
DB_PORT=${DB_PORT:-3306}
DB_DATABASE=${DB_DATABASE:-anonaddy}
DB_USERNAME=${DB_USERNAME:-anonaddy}
#DB_PASSWORD=${DB_PASSWORD:-asupersecretpassword}
DB_TIMEOUT=${DB_TIMEOUT:-60}

REDIS_HOST=${REDIS_HOST:-null}
REDIS_PASSWORD=${REDIS_PASSWORD:-null}
REDIS_PORT=${REDIS_PORT:-6379}

#PUSHER_APP_ID=${PUSHER_APP_ID}
#PUSHER_APP_KEY=${PUSHER_APP_KEY}
#PUSHER_APP_SECRET=${PUSHER_APP_SECRET}
PUSHER_APP_CLUSTER=${PUSHER_APP_CLUSTER:-mt1}

ANONADDY_RETURN_PATH=${ANONADDY_RETURN_PATH:-null}
ANONADDY_ADMIN_USERNAME=${ANONADDY_ADMIN_USERNAME:-null}
ANONADDY_ENABLE_REGISTRATION=${ANONADDY_ENABLE_REGISTRATION:-true}
#ANONADDY_DOMAIN=${ANONADDY_DOMAIN:-null}
ANONADDY_HOSTNAME=${ANONADDY_HOSTNAME:-null}
ANONADDY_DNS_RESOLVER=${ANONADDY_DNS_RESOLVER:-127.0.0.1}
ANONADDY_ALL_DOMAINS=${ANONADDY_ALL_DOMAINS:-null}
#ANONADDY_SECRET=${ANONADDY_SECRET:-long-random-string}
ANONADDY_LIMIT=${ANONADDY_LIMIT:-200}
ANONADDY_BANDWIDTH_LIMIT=${ANONADDY_BANDWIDTH_LIMIT:-104857600}
ANONADDY_NEW_ALIAS_LIMIT=${ANONADDY_NEW_ALIAS_LIMIT:-10}
ANONADDY_ADDITIONAL_USERNAME_LIMIT=${ANONADDY_ADDITIONAL_USERNAME_LIMIT:-3}
#ANONADDY_SIGNING_KEY_FINGERPRINT=${ANONADDY_SIGNING_KEY_FINGERPRINT:-your-signing-key-fingerprint}

MAIL_FROM_NAME=${MAIL_FROM_NAME:-AnonAddy}
MAIL_FROM_ADDRESS=${MAIL_FROM_ADDRESS:-anonaddy@${ANONADDY_DOMAIN}}

POSTFIX_DEBUG=${POSTFIX_DEBUG:-false}
POSTFIX_SMTPD_TLS=${POSTFIX_SMTPD_TLS:-false}
POSTFIX_SMTP_TLS=${POSTFIX_SMTP_TLS:-false}

# Timezone
echo "Setting timezone to ${TZ}..."
ln -snf /usr/share/zoneinfo/${TZ} /etc/localtime
echo ${TZ} > /etc/timezone

# PHP
echo "Setting PHP-FPM configuration"
sed -e "s/@MEMORY_LIMIT@/$MEMORY_LIMIT/g" \
  -e "s/@UPLOAD_MAX_SIZE@/$UPLOAD_MAX_SIZE/g" \
  /tpls/etc/php7/php-fpm.d/www.conf > /etc/php7/php-fpm.d/www.conf

echo "Setting PHP INI configuration"
sed -i "s|memory_limit.*|memory_limit = ${MEMORY_LIMIT}|g" /etc/php7/php.ini
sed -i "s|;date\.timezone.*|date\.timezone = ${TZ}|g" /etc/php7/php.ini

# OpCache
echo "Setting OpCache configuration"
sed -e "s/@OPCACHE_MEM_SIZE@/$OPCACHE_MEM_SIZE/g" \
  /tpls/etc/php7/conf.d/opcache.ini > /etc/php7/conf.d/opcache.ini

# Nginx
echo "Setting Nginx configuration"
sed -e "s#@UPLOAD_MAX_SIZE@#$UPLOAD_MAX_SIZE#g" \
  -e "s#@REAL_IP_FROM@#$REAL_IP_FROM#g" \
  -e "s#@REAL_IP_HEADER@#$REAL_IP_HEADER#g" \
  -e "s#@LOG_IP_VAR@#$LOG_IP_VAR#g" \
  /tpls/etc/nginx/nginx.conf > /etc/nginx/nginx.conf

if [ "$LISTEN_IPV6" != "true" ]; then
  sed -e '/listen \[::\]:/d' -i /etc/nginx/nginx.conf
fi

echo "Initializing files and folders"
mkdir -p /data/storage
cp -Rf /var/www/anonaddy/storage /data
rm -rf /var/www/anonaddy/storage
ln -sf /data/storage /var/www/anonaddy/storage
chown -h anonaddy. /var/www/anonaddy/storage
chown -R anonaddy. /data/storage

echo "Checking database connection..."
if [ -z "$DB_HOST" ]; then
  >&2 echo "ERROR: DB_HOST must be defined"
  exit 1
fi
file_env 'DB_USERNAME'
file_env 'DB_PASSWORD'
if [ -z "$DB_PASSWORD" ]; then
  >&2 echo "ERROR: Either DB_PASSWORD or DB_PASSWORD_FILE must be defined"
  exit 1
fi
dbcmd="mysql -h ${DB_HOST} -P ${DB_PORT} -u "${DB_USERNAME}" "-p${DB_PASSWORD}""

echo "Waiting ${DB_TIMEOUT}s for database to be ready..."
counter=1
while ! ${dbcmd} -e "show databases;" > /dev/null 2>&1; do
  sleep 1
  counter=$((counter + 1))
  if [ ${counter} -gt ${DB_TIMEOUT} ]; then
    >&2 echo "ERROR: Failed to connect to database on $DB_HOST"
    exit 1
  fi;
done
echo "Database ready!"

file_env 'APP_KEY'
if [ -z "$APP_KEY" ]; then
  >&2 echo "ERROR: Either APP_KEY or APP_KEY_FILE must be defined"
  exit 1
fi
if [ -z "$ANONADDY_DOMAIN" ]; then
  >&2 echo "ERROR: ANONADDY_DOMAIN must be defined"
  exit 1
fi
file_env 'ANONADDY_SECRET'
if [ -z "$ANONADDY_SECRET" ]; then
  >&2 echo "ERROR: Either ANONADDY_SECRET or ANONADDY_SECRET_FILE must be defined"
  exit 1
fi
file_env 'PUSHER_APP_SECRET'

echo "Creating AnonAddy env file"
cat > /var/www/anonaddy/.env <<EOL
APP_NAME=${APP_NAME}
APP_ENV=production
APP_KEY=${APP_KEY}
APP_DEBUG=${APP_DEBUG}
APP_URL=${APP_URL}

LOG_CHANNEL=stack

DB_CONNECTION=mysql
DB_HOST=${DB_HOST}
DB_PORT=${DB_PORT}
DB_DATABASE=${DB_DATABASE}
DB_USERNAME=${DB_USERNAME}
DB_PASSWORD=${DB_PASSWORD}

BROADCAST_DRIVER=log
CACHE_DRIVER=file
QUEUE_CONNECTION=sync
SESSION_DRIVER=file
SESSION_LIFETIME=120

REDIS_HOST=${REDIS_HOST}
REDIS_PASSWORD=${REDIS_PASSWORD}
REDIS_PORT=${REDIS_PORT}

MAIL_DRIVER=sendmail
MAIL_FROM_NAME=${MAIL_FROM_NAME}
MAIL_FROM_ADDRESS=${MAIL_FROM_ADDRESS}

PUSHER_APP_ID=${PUSHER_APP_ID}
PUSHER_APP_KEY=${PUSHER_APP_KEY}
PUSHER_APP_SECRET=${PUSHER_APP_SECRET}
PUSHER_APP_CLUSTER=${PUSHER_APP_CLUSTER}

MIX_PUSHER_APP_KEY="\${PUSHER_APP_KEY}"
MIX_PUSHER_APP_CLUSTER="\${PUSHER_APP_CLUSTER}"

ANONADDY_RETURN_PATH=${ANONADDY_RETURN_PATH}
ANONADDY_ADMIN_USERNAME=${ANONADDY_ADMIN_USERNAME}
ANONADDY_ENABLE_REGISTRATION=${ANONADDY_ENABLE_REGISTRATION}
ANONADDY_DOMAIN=${ANONADDY_DOMAIN}
ANONADDY_HOSTNAME=${ANONADDY_HOSTNAME}
ANONADDY_DNS_RESOLVER=${ANONADDY_DNS_RESOLVER}
ANONADDY_ALL_DOMAINS=${ANONADDY_ALL_DOMAINS}
ANONADDY_SECRET=${ANONADDY_SECRET}
ANONADDY_LIMIT=${ANONADDY_LIMIT}
ANONADDY_BANDWIDTH_LIMIT=${ANONADDY_BANDWIDTH_LIMIT}
ANONADDY_NEW_ALIAS_LIMIT=${ANONADDY_NEW_ALIAS_LIMIT}
ANONADDY_ADDITIONAL_USERNAME_LIMIT=${ANONADDY_ADDITIONAL_USERNAME_LIMIT}
ANONADDY_SIGNING_KEY_FINGERPRINT=${ANONADDY_SIGNING_KEY_FINGERPRINT}
EOL
chown anonaddy. /var/www/anonaddy/.env

echo "Trust all proxies"
anonaddy vendor:publish --no-interaction --provider="Fideloper\Proxy\TrustedProxyServiceProvider"
sed -i "s|^    'proxies'.*|    'proxies' => '\*',|g" /var/www/anonaddy/config/trustedproxy.php

POSTFIX_DEBUG_ARG=""
if [ "$POSTFIX_DEBUG" = "true" ]; then
  POSTFIX_DEBUG_ARG=" -v"
fi

echo "Setting Postfix master configuration"
sed -i "s|^smtp.*inet.*|25 inet n - - - - smtpd${POSTFIX_DEBUG_ARG} -o content_filter=anonaddy:dummy|g" /etc/postfix/master.cf
cat >> /etc/postfix/master.cf <<EOL
anonaddy unix - n n - - pipe
  flags=F user=anonaddy argv=php /var/www/anonaddy/artisan anonaddy:receive-email --sender=\${sender} --recipient=\${recipient} --local_part=\${user} --extension=\${extension} --domain=\${domain} --size=\${size}
EOL

echo "Setting Postfix main configuration"
sed -i 's/inet_interfaces = localhost/inet_interfaces = all/g' /etc/postfix/main.cf
sed -i 's/readme_directory.*/readme_directory = no/g' /etc/postfix/main.cf
cat >> /etc/postfix/main.cf <<EOL
myhostname = mail.${ANONADDY_DOMAIN}
mydomain = ${ANONADDY_DOMAIN}
alias_maps = hash:/etc/aliases
alias_database = hash:/etc/aliases
myorigin = /etc/mailname
mydestination = localhost.\$mydomain, localhost

smtpd_banner = \$myhostname ESMTP
biff = no
readme_directory = no
compatibility_level = 2
append_dot_mydomain = no

virtual_transport = anonaddy:
virtual_mailbox_domains = \$mydomain, unsubscribe.\$mydomain, mysql:/etc/postfix/mysql-virtual-alias-domains-and-subdomains.cf

relayhost =
mynetworks = 127.0.0.0/8 [::ffff:127.0.0.0]/104 [::1]/128 10.0.0.0/8 172.16.0.0/12 192.168.0.0/16
mailbox_size_limit = 0
recipient_delimiter = +

local_recipient_maps =

smtpd_helo_required = yes
smtpd_helo_restrictions =
    permit_mynetworks,
    permit_sasl_authenticated,
    reject_invalid_helo_hostname,
    reject_non_fqdn_helo_hostname,
    reject_unknown_helo_hostname

smtpd_sender_restrictions =
   permit_mynetworks,
   permit_sasl_authenticated,
   reject_non_fqdn_sender,
   reject_unknown_sender_domain,
   reject_unknown_reverse_client_hostname

smtpd_recipient_restrictions =
   reject_unauth_destination,
   check_recipient_access mysql:/etc/postfix/mysql-recipient-access.cf, mysql:/etc/postfix/mysql-recipient-access-domains-and-additional-usernames.cf,
   #check_policy_service unix:private/policyd-spf
   reject_rhsbl_helo dbl.spamhaus.org,
   reject_rhsbl_reverse_client dbl.spamhaus.org,
   reject_rhsbl_sender dbl.spamhaus.org,
   reject_rbl_client zen.spamhaus.org
   reject_rbl_client dul.dnsbl.sorbs.net

# Block clients that speak too early.
smtpd_data_restrictions = reject_unauth_pipelining

disable_vrfy_command = yes
strict_rfc821_envelopes = yes
maillog_file = /dev/stdout
EOL

if [ "$POSTFIX_SMTPD_TLS" = "true" ]; then
  cat >> /etc/postfix/main.cf <<EOL

# SMTPD
smtpd_use_tls=yes
smtpd_tls_session_cache_database = btree:\${data_directory}/smtpd_scache
smtpd_tls_CApath = /etc/ssl/certs
smtpd_tls_security_level = may
smtpd_tls_protocols = !SSLv2, !SSLv3, !TLSv1
smtpd_tls_loglevel = 1
smtpd_tls_session_cache_database = btree:\${data_directory}/smtpd_scache
smtpd_tls_mandatory_exclude_ciphers = MD5, DES, ADH, RC4, PSD, SRP, 3DES, eNULL, aNULL
smtpd_tls_exclude_ciphers = MD5, DES, ADH, RC4, PSD, SRP, 3DES, eNULL, aNULL
smtpd_tls_mandatory_protocols = !SSLv2, !SSLv3, !TLSv1
smtpd_tls_mandatory_ciphers = high
smtpd_tls_ciphers = high
smtpd_tls_eecdh_grade = ultra
tls_high_cipherlist=EECDH+ECDSA+AESGCM:EECDH+aRSA+AESGCM:EECDH+ECDSA+SHA384:EECDH+ECDSA+SHA256:EECDH+aRSA+SHA384:EECDH+aRSA+SHA256:EECDH+aRSA+RC4:EECDH:EDH+aRSA:RC4:!aNULL:!eNULL:!LOW:!3DES:!MD5:!EXP:!PSK:!SRP:!DSS
tls_preempt_cipherlist = yes
tls_ssl_options = NO_COMPRESSION
EOL
  if [ -n "$POSTFIX_SMTPD_TLS_CERT_FILE" ]; then
    echo "smtpd_tls_cert_file=${POSTFIX_SMTPD_TLS_CERT_FILE}" >> /etc/postfix/main.cf
  fi
  if [ -n "$POSTFIX_SMTPD_TLS_KEY_FILE" ]; then
    echo "smtpd_tls_key_file=${POSTFIX_SMTPD_TLS_KEY_FILE}" >> /etc/postfix/main.cf
  fi
fi

if [ "$POSTFIX_SMTP_TLS" = "true" ]; then
  cat >> /etc/postfix/main.cf <<EOL

# SMTP
smtp_tls_CApath = /etc/ssl/certs
smtp_use_tls=yes
smtp_tls_loglevel = 1
smtp_tls_session_cache_database = btree:\${data_directory}/smtp_scache
smtp_tls_mandatory_protocols = !SSLv2, !SSLv3, !TLSv1
smtp_tls_protocols = !SSLv2, !SSLv3, !TLSv1
smtp_tls_mandatory_ciphers = high
smtp_tls_ciphers = high
smtp_tls_mandatory_exclude_ciphers = MD5, DES, ADH, RC4, PSD, SRP, 3DES, eNULL, aNULL
smtp_tls_exclude_ciphers = MD5, DES, ADH, RC4, PSD, SRP, 3DES, eNULL, aNULL
smtp_tls_security_level = may
EOL
fi

echo "Creating Postfix virtual alias domains and subdomains configuration"
cat > /etc/postfix/mysql-virtual-alias-domains-and-subdomains.cf <<EOL
user = ${DB_USERNAME}
password = ${DB_PASSWORD}
hosts = ${DB_HOST}:${DB_PORT}
dbname = ${DB_DATABASE}
query = SELECT (SELECT 1 FROM users WHERE CONCAT(username, '.${ANONADDY_DOMAIN}') = '%s') AS users, (SELECT 1 FROM additional_usernames WHERE CONCAT(additional_usernames.username, '.${ANONADDY_DOMAIN}') = '%s') AS usernames, (SELECT 1 FROM domains WHERE domains.domain = '%s' AND domains.domain_verified_at IS NOT NULL) AS domains LIMIT 1;
EOL
chmod o= /etc/postfix/mysql-virtual-alias-domains-and-subdomains.cf
chgrp postfix /etc/postfix/mysql-virtual-alias-domains-and-subdomains.cf

echo "Creating Postfix recipient access configuration"
cat > /etc/postfix/mysql-recipient-access.cf <<EOL
user = ${DB_USERNAME}
password = ${DB_PASSWORD}
hosts = ${DB_HOST}:${DB_PORT}
dbname = ${DB_DATABASE}
query = CALL block_alias('%s')
EOL
chmod o= /etc/postfix/mysql-recipient-access.cf
chgrp postfix /etc/postfix/mysql-recipient-access.cf

echo "Creating Postfix recipient access domains and additional usernames configuration"
cat > /etc/postfix/mysql-recipient-access-domains-and-additional-usernames.cf <<EOL
user = ${DB_USERNAME}
password = ${DB_PASSWORD}
hosts = ${DB_HOST}:${DB_PORT}
dbname = ${DB_DATABASE}
query = SELECT (SELECT 'DISCARD' FROM additional_usernames WHERE (CONCAT(username, '.${ANONADDY_DOMAIN}') = SUBSTRING_INDEX('%s','@',-1)) AND active = 0) AS usernames, (SELECT 'DISCARD' FROM domains WHERE domain = SUBSTRING_INDEX('%s','@',-1) AND active = 0) AS domains LIMIT 1;
EOL
chmod o= /etc/postfix/mysql-recipient-access-domains-and-additional-usernames.cf
chgrp postfix /etc/postfix/mysql-recipient-access-domains-and-additional-usernames.cf

echo "Checking Postfix hostname"
postconf myhostname

echo "Creating stored procedure"
mysql -h ${DB_HOST} -P ${DB_PORT} -u "${DB_USERNAME}" "-p${DB_PASSWORD}" ${DB_DATABASE} <<EOL
DELIMITER //

DROP PROCEDURE IF EXISTS \`block_alias\`//

CREATE PROCEDURE \`block_alias\`(alias_email VARCHAR(254))
BEGIN
  UPDATE aliases SET
    emails_blocked = emails_blocked + 1
  WHERE email = alias_email AND active = 0 LIMIT 1;
  SELECT IF(deleted_at IS NULL,'DISCARD','REJECT') AS alias_action
  FROM aliases WHERE email = alias_email AND (active = 0 OR deleted_at IS NOT NULL) LIMIT 1;
END//

DELIMITER ;
EOL
