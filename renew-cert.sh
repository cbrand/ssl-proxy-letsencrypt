#!/bin/bash

EMAIL=${cert_email}
DOMAINS=(${cert_domains})

if [ -z "$DOMAINS" ]; then
  echo "ERROR: Domain list is empty or unset"
  exit 1
fi

if [ -z "$EMAIL" ]; then
  echo "ERROR: Email is empty string or unset"
  exit 1
fi

domain_args=""
for i in "${DOMAINS[@]}"
do
  domain_args="$domain_args -d $i"
done

if [ -n "${LETSENCRYPT_ENDPOINT+1}" ]; then
  echo "server = $LETSENCRYPT_ENDPOINT" >> /etc/letsencrypt/cli.ini
fi

# Renewal of letsencrypt data
/usr/local/bin/letsencrypt renew \
  --text --renew-by-default --agree-tos --webroot \
  --webroot-path /usr/share/nginx/proxy-root \
  $domain_args \
  --email=$EMAIL
