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
#
# nginx-ssl-proxy
#
# VERSION   0.0.1

FROM nginx:1.13

MAINTAINER Christoph Brand

RUN rm /etc/nginx/conf.d/*.conf
RUN apt-get update && apt-get install -y apache2-utils && rm -rf /var/lib/apt/lists/*

WORKDIR /usr/src

# https://letsencrypt.org/howitworks/#installing-lets-encrypt
#ADD https://github.com/letsencrypt/letsencrypt/archive/master.zip /opt/letsencrypt

ADD letsencrypt /opt/letsencrypt

# Does a lot of package installations that we don't want at runtime.
# Prints a "No installers" error but that's normal.
RUN cd /opt/letsencrypt \
  && ./letsencrypt-auto; exit 0

ADD start.sh /usr/src/
ADD nginx/nginx.conf /etc/nginx/
ADD nginx/nginx_request_ssl.conf /usr/src/
ADD nginx/proxy*.conf /usr/src/

ENTRYPOINT ./start.sh

RUN ln -s /root/.local/share/letsencrypt/bin/letsencrypt /usr/local/bin/letsencrypt

RUN apt-get update && apt-get install -y cron

RUN mkdir -p /usr/share/nginx/proxy-root

ADD start-cert.sh /usr/src/
ADD renew-cert.sh /usr/src/
RUN rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*

ADD go-dnsmasq /usr/bin/go-dnsmasq
RUN chmod +x /usr/bin/go-dnsmasq
