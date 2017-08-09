#!/bin/bash

# Renewal of letsencrypt data
/usr/local/bin/letsencrypt renew \
  --text --agree-tos --webroot \
  --webroot-path /usr/share/nginx/proxy-root

/etc/init.d/nginx reload
