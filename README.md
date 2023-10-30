[![pipeline status](https://gitlab.conarx.tech/containers/zabbix/badges/main/pipeline.svg)](https://gitlab.conarx.tech/containers/zabbix/-/commits/main)

# Container Information

[Container Source](https://gitlab.conarx.tech/containers/zabbix) - [GitHub Mirror](https://github.com/AllWorldIT/containers-zabbix)

This is the Conarx Containers Zabbix image, it provides the Zabbix server, proxy, agent and agent2 services.



# Mirrors

|  Provider  |  Repository                           |
|------------|---------------------------------------|
| DockerHub  | allworldit/zabbix                      |
| Conarx     | registry.conarx.tech/containers/zabbix |



# Conarx Containers

All our Docker images are part of our Conarx Containers product line. Images are generally based on Alpine Linux and track the
Alpine Linux major and minor version in the format of `vXX.YY`.

Images built from source track both the Alpine Linux major and minor versions in addition to the main software component being
built in the format of `vXX.YY-AA.BB`, where `AA.BB` is the main software component version.

Our images are built using our Flexible Docker Containers framework which includes the below features...

- Flexible container initialization and startup
- Integrated unit testing
- Advanced multi-service health checks
- Native IPv6 support for all containers
- Debugging options



# Community Support

Please use the project [Issue Tracker](https://gitlab.conarx.tech/containers/zabbix/-/issues).



# Commercial Support

Commercial support for all our Docker images is available from [Conarx](https://conarx.tech).

We also provide consulting services to create and maintain Docker images to meet your exact needs.



# Environment Variables

Additional environment variables are available from...
* [Conarx Containers Alpine image](https://gitlab.conarx.tech/containers/alpine)


## ZABBIX_MODE

Mode for Zabbix to operate in, either `server`, `proxy`, `agent` or `agent2`.


# Environment Variables - Server

## ZABBIX_ADMIN_USERNAME

Zabbix admin username to setup on first run. Defaults to 'Admin'.

## ZABBIX_ADMIN_PASSWORD

Zabbix admin password to use for the `ZABBIX_ADMIN_USERNAME` on first run.

If set, the username and password are changed when the database is created.

## ZABBIX_SERVER_AGENT_NAME

Zabbix server agent name. The Zabbix server runs its own internal agent, this is the name configured for that agent, both of which
must match. Defaults to 'Zabbix Server'.

## ZABBIX_SERVER_WEBSERVICE_URL

Zabbix web service URL, used for generating reports. eg. `http://localhost:10053/report`.

## ZABBIX_DATABASE_TYPE

Zabbix database type, either `mysql`, `postgresql` or `timescaledb`.

## MYSQL_HOST, MYSQL_DATABASE, MYSQL_USER, MYSQL_PASSWORD

Database credentials if `ZABBIX_DATABASE_TYPE` is set to `mysql`.

## POSTGRES_HOST, POSTGRES_DATABASE, POSTGRES_USER, POSTGRES_PASSWORD

Database credentials if `ZABBIX_DATABASE_TYPE` is set to `postgresql` or `timescaledb`.


# Environment Variables - Zabbix Web Service

## ZABBIX_WEBSERVICE_ALLOWEDIP

List of IPv4, IPv6 or hostnames allowed to access the web service.


# Environment Variables - Proxy

## ZABBIX_HOSTNAME

Proxy hostname configured in Zabbix.

## ZABBIX_SERVER

Zabbix server hostname.

## ZABBIX_TLS_PSKIDENTITY, ZABBIX_TLS_PSKKEY

When specified, traffic between the proxy and server is encrypted.

The identity can be generated using `pwmake 256`.

The presharked key can be generated using `openssl rand -hex 256`.

## ZABBIX_PROXY_MODE

Mode in which the proxy will operate, either 'active' or 'passive'.

## ZABBIX_DATABASE_TYPE

Zabbix database type, either `mysql`, `postgresql`. NB. Timescaledb is not supported for proxies.

## MYSQL_HOST, MYSQL_DATABASE, MYSQL_USER, MYSQL_PASSWORD

Database credentials if `ZABBIX_DATABASE_TYPE` is set to `mysql`.

## POSTGRES_HOST, POSTGRES_DATABASE, POSTGRES_USER, POSTGRES_PASSWORD

Database credentials if `ZABBIX_DATABASE_TYPE` is set to `postgresql` or `timescaledb`.


# Environment Variables - Frontend

## ZABBIX_SERVER_HOSTNAME
Zabbix server hostname, defaults to 'zabbix-server'.

## ZABBIX_SERVER_AGENT_NAME
Name of the agent running on the Zabbix server. Defaults to 'Zabbix server'.

## ZABBIX_DATABASE_TYPE

Zabbix database type, either `mysql`, `postgresql`. NB. Timescaledb is not supported for proxies.

## MYSQL_HOST, MYSQL_DATABASE, MYSQL_USER, MYSQL_PASSWORD

Database credentials if `ZABBIX_DATABASE_TYPE` is set to `mysql`.

## POSTGRES_HOST, POSTGRES_DATABASE, POSTGRES_USER, POSTGRES_PASSWORD

Database credentials if `ZABBIX_DATABASE_TYPE` is set to `postgresql` or `timescaledb`.

## ZABBIX_FRONTEND_SSO_USE_PROXY_HEADERS
Optional. Use Zabbix proxy headers for SSO. Set to `yes` to enable.


# Environment Variables - Agent

## ZABBIX_HOSTNAME

Zabbix agent name setup on the server.

## ZABBIX_AGENT_MODE
Zabbix agent mode, either 'active' or 'passive'.

## ZABBIX_TLS_PSKIDENTITY, ZABBIX_TLS_PSKKEY

When specified, traffic between the proxy and server is encrypted.

The identity can be generated using `pwmake 256`.

The presharked key can be generated using `openssl rand -hex 256`.


# Environment Variables - Agent 2

## ZABBIX_HOSTNAME

Zabbix agent name setup on the server.

## ZABBIX_AGENT_MODE
Zabbix agent mode, either 'active' or 'passive'.

## ZABBIX_TLS_PSKIDENTITY, ZABBIX_TLS_PSKKEY

When specified, traffic between the proxy and server is encrypted.

The identity can be generated using `pwmake 256`.

The presharked key can be generated using `openssl rand -hex 256`.


# Environment Variables - Server, Proxy, Agent, Agent 2

## ZABBIX_CONFIG_\<option>

Custom Zabbix config options, where `option=value` will be output.

For example `ZABBIX_CONFIG_Hostname=abc` becomes `Hostname=abc`.



# Directories - Server

## /etc/zabbix/zabbix_server.conf.d

Zabbix server configuration.

## /var/lib/zabbix/externalscripts

Zabbix server external scripts.

## /var/lib/zabbix/alertscripts

Zabbix server alert scripts.

## /var/lib/zabbix/sshkeys

SSH private keys should be named `id_*` and public keys should be named `id_*.pub` respectively. This ensures the correct
permissions will be set to prevent unauthorized access.


# Directories - Proxy

## /etc/zabbix/zabbix_proxy.conf.d

Zabbix proxy configuration.


# Directories - Frontend

## /etc/zabbix/zabbix.conf.php

Zabbix frontend configuration file.


# Directories - Agent

## /etc/zabbix/zabbix_agent.conf.d

Zabbix agent configuration.


## /etc/zabbix/zabbix_agent2.conf.d

Zabbix agent2 configuration.



# Configuration Exampmle


```yaml
version: '3.9'

services:

  zabbix-server:
    image: allworldit/zabbix:latest
    hostname: zabbix-server
    environment:
      - ZABBIX_MODE=server
      - ZABBIX_DATABASE_TYPE=timescaledb
      - ZABBIX_ADMIN_USERNAME=Admin
      - ZABBIX_ADMIN_PASSWORD=testtest
      - ZABBIX_SERVER_WEBSERVICE_URL=http://zabbix-webservice:10053/report
      - POSTGRES_HOST=postgresql
      - POSTGRES_DATABASE=zabbix
      - POSTGRES_USER=zabbix
      - POSTGRES_PASSWORD=dbpassword
    networks:
      internal:
      external:
        ipv4_address: 172.16.10.10
        ipv6_address: 64:ff9b:1::10:10

  zabbix-frontend:
    image: allworldit/zabbix:latest
    environment:
      ZABBIX_MODE: frontend
      ZABBIX_DATABASE_TYPE: postgresql
      POSTGRES_HOST: postgresql
      POSTGRES_DATABASE: zabbix
      POSTGRES_USER: zabbix
      POSTGRES_PASSWORD: dbpassword
      NGINX_SET_REAL_IP_FROM: |
        172.16.0.0/12
        64:ff9b:1::/96
    ports:
      - '8080:80'
    networks:
      internal:
      external:
        ipv4_address: 172.16.10.20
        ipv6_address: 64:ff9b:1::10:20

  zabbix-webservice:
    image: allworldit/zabbix:latest
    extra_hosts:
      - "zabbix.frontend.example.com:172.16.0.1"
    environment:
      - ZABBIX_MODE=webservice
      - ZABBIX_WEBSERVICE_ALLOWEDIP=zabbix-server
    networks:
      internal:
      external:
        ipv4_address: 172.16.10.30
        ipv6_address: 64:ff9b:1::10:30

  postgresql:
    image: registry.conarx.tech/containers/postgresql-timescaledb
    environment:
      - POSTGRES_USER=zabbix
      - POSTGRES_PASSWORD=dbpassword
      - POSTGRES_DATABASE=zabbix
    volumes:
      - './data/postgresql:/var/lib/postgresql/data'
    networks:
      - internal


networks:
  internal:
    driver: bridge
    enable_ipv6: true
    internal: true
  external:
    driver: bridge
    enable_ipv6: true
    driver_opts:
      com.docker.network.bridge.name: docker1
      com.docker.network.enable_ipv6: 'true'
    ipam:
      driver: default
      config:
        - subnet: 172.16.10.0/24
        - subnet: 64:ff9b:1::10:0/112
```
