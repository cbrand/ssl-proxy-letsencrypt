#!/bin/bash

filename="/etc/secrets/proxycert"
origmd5sum=$(md5sum "$filename")

# Renewal of letsencrypt data
/usr/local/bin/letsencrypt renew \
  --text --agree-tos --webroot \
  --webroot-path /usr/share/nginx/proxy-root

newmd5sum=$(md5sum "$filename")

if [ "$origmd5sum" != "$newmd5sum" ] ; then
  echo "Reloading nginx"
  /etc/init.d/nginx reload
else
  echo "Nginx is not being reloaded"
fi
