### ssl-proxy-letsencrypt

Note: this fork was the inception of what is now maintained at https://github.com/Reposoft/docker-httpd-letsencrypt.

Based on https://github.com/GoogleCloudPlatform/nginx-ssl-proxy
and inspired by http://blog.ployst.com/development/2015/12/22/letsencrypt-on-kubernetes.html
but
the proxy container itself requests a cert from https://letsencrypt.org/ upon startup. No need to run kubectl from within the pod.

Schedule restart of the container/pod within 90 days to renew before cert expiry.

A service could look like this:
```
---
kind: Service
apiVersion: v1
metadata:
  name: ssl-proxy-service
  labels:
    role: ssl-proxy
spec:
  ports:
  - name: http
    port: 80
    targetPort: http
    protocol: TCP
  - name: https
    port: 443
    targetPort: https
    protocol: TCP
  selector:
    role: ssl-proxy
  type: LoadBalancer
```

And the proxy pod like this:
```
---
kind: ReplicationController
apiVersion: v1
metadata:
  name: ssl-proxy-letsencrypt
  labels:
    role: ssl-proxy
spec:
  replicas: 1
  selector:
    role: ssl-proxy
  template:
    metadata:
      name: ssl-proxy-letsencrypt
      labels:
        role: ssl-proxy
    spec:
      containers:
      - name: ssl-proxy-letsencrypt
        image: solsson/ssl-proxy-letsencrypt:latest
        env:
        - name: TARGET_SERVICE
          value: my-actual-service:80
        - name: ENABLE_SSL
          value: 'true'
        - name: cert_email
          value: webmaster@example.net
        - name: cert_domains
          value: my.example.net my2.example.net
        # remove this when it's time to get a real cert
        - name: LETSENCRYPT_ENDPOINT
          value: https://acme-staging.api.letsencrypt.org/directory
        ports:
        - name: http
          containerPort: 80
        - name: https
          containerPort: 443
```

Make sure to create the k8s service before the pod, so letsencrypt validation can get through on startup.

### nginx-ssl-proxy

#nginx-ssl-proxy
This repository is used to build a Docker image that acts as an HTTP [reverse proxy](http://en.wikipedia.org/wiki/Reverse_proxy) with optional (but strongly encouraged) support for acting as an [SSL termination proxy](http://en.wikipedia.org/wiki/SSL_termination_proxy). The proxy can also be configured to enforce [HTTP basic access authentication](http://en.wikipedia.org/wiki/Basic_access_authentication). Nginx is the HTTP server, and its SSL configuration is included (and may be modified to suit your needs) at `nginx/proxy_ssl.conf` in this repository.

## Building the Image
Build the image yourself by cloning this repository then running:

```shell
docker build -t nginx-ssl-proxy .
```

## Using with Kubernetes
This image is optimized for use in a Kubernetes cluster to provide SSL termination for other services in the cluster. It should be deployed as a [Kubernetes replication controller](https://github.com/GoogleCloudPlatform/kubernetes/blob/master/docs/replication-controller.md) with a [service and public load balancer](https://github.com/GoogleCloudPlatform/kubernetes/blob/master/docs/services.md) in front of it. SSL certificates, keys, and other secrets are managed via the [Kubernetes Secrets API](https://github.com/GoogleCloudPlatform/kubernetes/blob/master/docs/design/secrets.md).

Here's how the replication controller and service would function terminating SSL for Jenkins in a Kubernetes cluster:

![](img/architecture.png)

See [https://github.com/GoogleCloudPlatform/kube-jenkins-imager](https://github.com/GoogleCloudPlatform/kube-jenkins-imager) for a complete tutorial that uses the `nginx-ssl-proxy` in Kubernetes.

## Run an SSL Termination Proxy from the CLI
To run an SSL termination proxy you must have an existing SSL certificate and key. These instructions assume they are stored at /path/to/secrets/ and named `cert.crt` and `key.pem`. You'll need to change those values based on your actual file path and names.

1. **Create a DHE Param**

    The nginx SSL configuration for this image also requires that you generate your own DHE parameter. It's easy and takes just a few minutes to complete:

    ```shell
    openssl dhparam -out /path/to/secrets/dhparam.pem 2048
    ```

2. **Launch a Container**

    Modify the below command to include the actual address or host name you want to proxy to, as well as the correct /path/to/secrets for your certificate, key, and dhparam:

    ```shell
    docker run \
      -e ENABLE_SSL=true \
      -e TARGET_SERVICE=THE_ADDRESS_OR_HOST_YOU_ARE_PROXYING_TO \
      -v /path/to/secrets/cert.crt:/etc/secrets/proxycert \
      -v /path/to/secrets/key.pem:/etc/secrets/proxykey \
      -v /path/to/secrets/dhparam.pem:/etc/secrets/dhparam \
      nginx-ssl-proxy
    ```
    The really important thing here is that you map in your cert to `/etc/secrets/proxycert`, your key to `/etc/secrets/proxykey`, and your dhparam to `/etc/secrets/dhparam` as shown in the command above.

3. **Enable Basic Access Authentication**

    Create an htpaddwd file:

    ```shell
    htpasswd -nb YOUR_USERNAME SUPER_SECRET_PASSWORD > /path/to/secrets/htpasswd
    ```

    Launch the container, enabling the feature and mapping in the htpasswd file:

    ```shell
    docker run \
      -e ENABLE_SSL=true \
      -e ENABLE_BASIC_AUTH=true \
      -e TARGET_SERVICE=THE_ADDRESS_OR_HOST_YOU_ARE_PROXYING_TO \
      -v /path/to/secrets/cert.crt:/etc/secrets/proxycert \
      -v /path/to/secrets/key.pem:/etc/secrets/proxykey \
      -v /path/to/secrets/dhparam.pem:/etc/secrets/dhparam \
      -v /path/to/secrets/htpasswd:/etc/secrets/htpasswd \
      nginx-ssl-proxy
    ```

    If you are running in an environment where file based acces sin this regard
    is not possible. You can also specify a htpasswd content via the `HTPASSWD_CONTENT`
    environment variable (in base64). It will be pushed on build time to the correct location.

    As an alternative you are also able to set a `HTPASSWD_USERNAME` and `HTPASSWD_PASSWORD` variable.
    If both are set the HTPASSWD file gets generated automatically.

4. **Enabling frames**

    The container does by default not allow any frames to be opened due to
    security issues doing this. While this is a recommended default behavior,
    it might break certain applications.

    If you are encountering issues you can either turn of the frame denial
    completely by passing the `ENABLE_FRAMES` environment variable to it:

    ```shell
    docker run \
      -e ENABLE_SSL=true \
      -e ENABLE_FRAMES=true \
      -e TARGET_SERVICE=THE_ADDRESS_OR_HOST_YOU_ARE_PROXYING_TO \
      -v /path/to/secrets/cert.crt:/etc/secrets/proxycert \
      -v /path/to/secrets/key.pem:/etc/secrets/proxykey \
      -v /path/to/secrets/dhparam.pem:/etc/secrets/dhparam \
      -v /path/to/secrets/htpasswd:/etc/secrets/htpasswd \
      nginx-ssl-proxy
    ```

    Alternatively if you only need frames from your own domain you can also
    use the [SAMEORIGIN](https://developer.mozilla.org/en-US/docs/Web/HTTP/X-Frame-Options) policy
    through setting the `ENABLE_FRAMES_SAMEORIGIN` variable to true.

    ```shell
    docker run \
      -e ENABLE_SSL=true \
      -e ENABLE_FRAMES_SAMEORIGIN=true \
      -e TARGET_SERVICE=THE_ADDRESS_OR_HOST_YOU_ARE_PROXYING_TO \
      -v /path/to/secrets/cert.crt:/etc/secrets/proxycert \
      -v /path/to/secrets/key.pem:/etc/secrets/proxykey \
      -v /path/to/secrets/dhparam.pem:/etc/secrets/dhparam \
      -v /path/to/secrets/htpasswd:/etc/secrets/htpasswd \
      nginx-ssl-proxy
    ```

5. **Proxy to HTTPs endpoint**

    It might be necessary to forward an already SSL protected stream.
    To enable an upstream HTTPs endpoint the environment variable
    `ENABLE_UPSTREAM_SSL` has to be set to `true`.

    This will then configure the proxy to terminate an incoming SSL
    connection and rebuild a new one with the requested certificate.
    Of course, when the environment variable is set you also have
    to specify the port for the HTTPS connection (usually 443) in the
    `TARGET_SERVICE` configuration.

6. **Additional configuration**

    If you want to pass additional configuration to the docker container
    you can do so by passing a base64 encoded file content to the
    `ADDITIONAL_NGINX_CONFIG` variable. This will unpack and include
    it into the `location` proxy directive. This is especially useful
    if you want to change the underlying data via the `sub_filter`
    directive.

7. **NGINX reload**
    In some proxy environments it might be necessary to periodically reload
    and thus reset the TCP state of nginx. This can be done by setting the
    `ENABLE_PERIODIC_NGINX_RELOAD` to `true`.

8. **Certificate renewal**
    The certificates are checked for renewal on a daily basis. To not request
    renewal checks at the same time the cronjob is randomly executed somewhere
    between 1:00 to 5:59 local time. If no certificate renewal should be
    requested you can disable this behavior by setting the environment variable
    `NO_CERT_REFRESH` to `true`.

9. **GZIP compression**
    Due to the [BREACH](https://en.wikipedia.org/wiki/BREACH_(security_exploit))
    attack GZIP compression is disabled by default. This is however a huge performance
    penalty. If you use the SSL compression to only serve static files and can guarantee
    that you're not storing any cookies or use some other kind of mitigation described
    [here](https://blog.qualys.com/ssllabs/2013/08/07/defending-against-the-breach-attack),
    you can enable GZIP by setting the environment variable `ENABLE_GZIP` to `true`.

10. ***Body Size***
    To be able to upload large files and handle other large file contexts you can modify
    the maximum body size of client requests via the environment variable `CLIENT_MAX_BODY_SIZE`.
    The default of this is `20M` and thus fits 20 megabytes of data.

11. ***Enable Proxy Protocol***
    To enable the [proxy protocol](https://www.haproxy.org/download/1.8/doc/proxy-protocol.txt)
    on the receiving side you have to set the `ENABLE_PROXY_PROTOCOL` variable to `true`.
    This will enable the receiving of proxy protocol information for the server.
    To specify the IPs where the proxy protocol source information should be taken for further
    processing you can use the `PROXY_PROTOCOL_BASE_PROXY` environment variable.
