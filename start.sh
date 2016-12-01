#!/bin/bash
# Copyright 2015 Google Inc. All rights reserved.
#
# Licensed under the Apache License, Version 2.0 (the "License");
#you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#    http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and

mkdir -p /etc/secrets

echo "Requesting certificate..."
./start-cert.sh || exit 1

# Env says we're using SSL
if [ -n "${ENABLE_SSL+1}" ] && [ "${ENABLE_SSL,,}" = "true" ]; then
  echo "Enabling SSL..."
  cp /usr/src/proxy_ssl.conf /etc/nginx/conf.d/proxy.conf
else
  # No SSL
  cp /usr/src/proxy_nossl.conf /etc/nginx/conf.d/proxy.conf
fi

# If an htpasswd file is provided, download and configure nginx
if [ -n "${ENABLE_BASIC_AUTH+1}" ] && [ "${ENABLE_BASIC_AUTH,,}" = "true" ]; then
  echo "Enabling basic auth..."
  sed -i "s/#auth_basic/auth_basic/g;" /etc/nginx/conf.d/proxy.conf
fi

# If a htpasswd content is provided, put the content of the files to /etc/secrets/htpasswd
if [ -n "${HTPASSWD_CONTENT+1}" ]; then
  echo "Adding htpasswd file"
  echo $HTPASSWD_CONTENT | base64 --decode > /etc/secrets/htpasswd
fi

# If frames should be allowed
if [ -n "${ENABLE_FRAMES+1}" ] && [ "${ENABLE_FRAMES,,}" = "true" ]; then
  echo "Enabling frames..."
  sed -i "s/add_header X-Frame-Options DENY;//g;" /etc/nginx/conf.d/proxy.conf
fi

# If frames should be allowed
if [ -n "${ENABLE_FRAMES_SAMEORIGIN+1}" ] && [ "${ENABLE_FRAMES_SAMEORIGIN,,}" = "true" ]; then
  echo "Enabling frames from the same origin..."
  sed -i "s/add_header X-Frame-Options DENY;/add_header X-Frame-Options SAMEORIGIN;/g;" /etc/nginx/conf.d/proxy.conf
fi

# If hosts should be faked
if [ -n "${DISABLE_HOST_PROXY+1}" ] && [ "${DISABLE_HOST_PROXY,,}" = "true" ]; then
  echo "Disabling the indication of the host to the upstream backend."
  sed -i "s/proxy_set_header.*Host $host;/#proxy_set_header        Host $host;/g;" /etc/nginx/conf.d/proxy.conf
  sed -i "s/proxy_set_header        X-Forwarded-Host $http_host;/#proxy_set_header        X-Forwarded-Host $http_host;/g" /etc/nginx/conf.d/proxy.conf
fi

# If the upstream is ssl secured
if [ -n "${ENABLE_UPSTREAM_SSL+1}" ] && [ "${ENABLE_UPSTREAM_SSL,,}" = "true" ]; then
  echo "Accessing the upstream server via (https)"
  sed -i "s/http:\/\/{{TARGET_SERVICE}};/https:\/\/{{TARGET_SERVICE}};/g;" /etc/nginx/conf.d/proxy.conf
fi

# If a periodic reload should be implemented
if [ -n "${ENABLE_PERIODIC_NGINX_RELOAD+1}" ] && [ "${ENABLE_PERIODIC_NGINX_RELOAD,,}" = "true" ]; then
  echo "Enabling periodic reloads of nginx"
  cron -f &
  echo "0 */2 * * * /etc/init.d/nginx reload" > /root/nginx-reload
  chmod +x /root/nginx-reload
  cp /root/nginx-reload /etc/cron.d/nginx-reload
fi

# If certificate renewals are not excluded
if [ -z "${NO_CERT_REFRESH+x}" ]; then
  echo "Enabling certificate renewal checks every day"
  cron -f &
  echo "`shuf -i 0-59 -n 1` `shuf -i 1-5 -n 1` * * * /usr/src/renew-cert.sh" > /root/renew-cert
  chmod +x /root/renew-cert
  cp /root/renew-cert /etc/cron.d/renew-cert
fi

# If the SERVICE_HOST_ENV_NAME and SERVICE_PORT_ENV_NAME vars are provided,
# there are two options:
#  - Option 1:
# they point to the env vars set by Kubernetes that contain the actual
# target address and port. Override the default with them.
#  - Option 2:
# they point to a host and port accessible from the container, respectively,
# as in a multi-container pod scenario in Kubernetes.
# E.g.
#    - SERVICE_HOST_ENV_NAME=localhost
#    - SERVICE_PORT_ENV_NAME=8080
if [ -n "${SERVICE_HOST_ENV_NAME+1}" ]; then
  # get value of the env variable in SERVICE_HOST_ENV_NAME as host, if that's not set,
  # SERVICE_HOST_ENV_NAME has the host value
  TARGET_SERVICE=${!SERVICE_HOST_ENV_NAME:=$SERVICE_HOST_ENV_NAME}
fi
if [ -n "${SERVICE_PORT_ENV_NAME+1}" ]; then
  # get value of the env variable in SERVICE_PORT_ENV_NAME as port, if that's not set,
  # SERVICE_PORT_ENV_NAME has the port value
  TARGET_SERVICE="$TARGET_SERVICE:${!SERVICE_PORT_ENV_NAME:=$SERVICE_PORT_ENV_NAME}"
fi
if [ -n "${ADDITIONAL_NGINX_CONFIG+1}" ]; then
  echo $ADDITIONAL_NGINX_CONFIG | base64 --decode > /etc/nginx/conf.d/additional.conf
  sed -i "s/\#additional_config_marker/include \/etc\/nginx\/conf.d\/additional.conf;/g;" /etc/nginx/conf.d/proxy.conf
fi
if [ -n "${OVERWRITE_PROXY_HOST+1}" ]; then
  echo "Statically setting the proxy host to \"$OVERWRITE_PROXY_HOST\""
  sed -i "s/proxy_set_header.*Host.*;/proxy_set_header Host \"${OVERWRITE_PROXY_HOST}\";/g;" /etc/nginx/conf.d/proxy.conf
fi
if [ -n "${ENABLE_GZIP+1}" ]; then
  sed -i "s/\#gzip on;/gzip on; \\n   gzip_proxied any; \\n   gzip_types text\/css text\/javascript text\/xml text\/plain application\/javascript application\/x-javascript application\/json;/g;" /etc/nginx/nginx.conf
fi

# Tell nginx the address and port of the service to proxy to
sed -i "s/{{TARGET_SERVICE}}/${TARGET_SERVICE}/g;" /etc/nginx/conf.d/proxy.conf

# Place cert where this image expects it
cert_first=$(echo $cert_domains | awk '{print $1}')
CERT_FILE=/etc/letsencrypt/live/${cert_first}/fullchain.pem
CERT_KEYFILE=/etc/letsencrypt/live/${cert_first}/privkey.pem

if [ -f ${CERT_FILE} ]; then
    ln -s ${CERT_FILE} /etc/secrets/proxycert
    ln -s ${CERT_KEYFILE} /etc/secrets/proxykey

    # Generate dhparams, this image expects it as part of secret
    /usr/bin/openssl dhparam -out /etc/secrets/dhparam 2048

    echo "Starting dnsmasq in the background"
    nohup /usr/bin/go-dnsmasq --listen "127.0.0.1:53" --default-resolver --enable-search --hostsfile=/etc/hosts &

    echo "Starting nginx..."
    nginx -g 'daemon off;'
else
    exit 1;
fi
