# Copyright (c) 2022-2025, AllWorldIT.
#
# Permission is hereby granted, free of charge, to any person obtaining a copy
# of this software and associated documentation files (the "Software"), to
# deal in the Software without restriction, including without limitation the
# rights to use, copy, modify, merge, publish, distribute, sublicense, and/or
# sell copies of the Software, and to permit persons to whom the Software is
# furnished to do so, subject to the following conditions:
#
# The above copyright notice and this permission notice shall be included in
# all copies or substantial portions of the Software.
#
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
# AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
# LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING
# FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS
# IN THE SOFTWARE.


FROM registry.conarx.tech/containers/nginx-php/edge as builder


# UPDATE timescaledb version in tests/docker-compose.yml.timescaledb.tmpl to the max supported version
# ref https://hub.docker.com/repository/docker/allworldit/postgresql-timescaledb/tags?page=1&ordering=last_updated
# ref https://git.zabbix.com/projects/ZBX/repos/zabbix/browse/include/zbx_dbversion_constants.h?at=refs%2Ftags%2F7.2.1
ENV ZABBIX_VER=7.2.6


COPY patches /build/patches

# Install libs we need
RUN set -eux; \
	true "Installing build dependencies"; \
# from https://git.alpinelinux.org/aports/tree/community/zabbix/APKBUILD
	apk add --no-cache \
		build-base \
		wget \
		autoconf \
		automake \
		ccache \
		curl-dev \
		go \
		libevent-dev \
		linux-headers \
		libpq-dev \
		libssh2-dev \
		libxml2-dev \
		mariadb-connector-c-dev \
		net-snmp-dev \
		openipmi-dev \
		openldap-dev \
		openssl-dev \
		pcre2-dev \
		sqlite-dev \
		unixodbc-dev

# Download packages
RUN set -eux; \
	mkdir -p build; \
	cd build; \
	wget "https://cdn.zabbix.com/zabbix/sources/stable/${ZABBIX_VER%.*}/zabbix-${ZABBIX_VER}.tar.gz" -O "zabbix-server-${ZABBIX_VER}.tar.gz"; \
	tar -zxvf "zabbix-server-${ZABBIX_VER}.tar.gz"

# Download and build
RUN set -eux; \
	cd build; \
	cd "zabbix-${ZABBIX_VER}"; \
	true "Patching"; \
	patch -p1 < ../patches/zabbix-disable-chrome-sandboxing.patch; \
	patch -p1 < ../patches/zabbix-6.4.4_cgoflags-append-fix.patch; \
	# Alpine patches
	patch -p1 < ../patches/ui-services-fix-php-80.patch; \
	true "Configuring"; \
	autoreconf -fvi; \
	# Compiler flags
	. /etc/buildflags; \
	export PATH="/usr/lib/ccache/bin:$PATH"; \
	export LDFLAGS="${LDFLAGS} -Wl,--export-dynamic"; \
	export GOPATH=/build/go; \
	# Temporary workaround for https://github.com/mattn/go-sqlite3/issues/1164
	export CGO_CFLAGS="-D_LARGEFILE64_SOURCE"; \
	export AGENT_LDFLAGS="${LDFLAGS}"; \
	\
	_configure_flags="--disable-static"; \
	_configure_flags="$_configure_flags --prefix=/opt/zabbix"; \
	_configure_flags="$_configure_flags --sysconfdir=/etc/zabbix"; \
	_configure_flags="$_configure_flags --datadir=/var/lib/zabbix"; \
	_configure_flags="$_configure_flags --mandir=/opt/zabbix/share/man"; \
	_configure_flags="$_configure_flags --infodir=/opt/zabbix/share/info"; \
	_configure_flags="$_configure_flags --enable-agent"; \
	_configure_flags="$_configure_flags --enable-agent2"; \
	_configure_flags="$_configure_flags --enable-ipv6"; \
	_configure_flags="$_configure_flags --enable-webservice"; \
	_configure_flags="$_configure_flags --with-ldap"; \
	_configure_flags="$_configure_flags --with-libcurl"; \
	_configure_flags="$_configure_flags --with-libpcre2"; \
	_configure_flags="$_configure_flags --with-libxml2"; \
	_configure_flags="$_configure_flags --with-net-snmp"; \
	_configure_flags="$_configure_flags --with-openipmi"; \
	_configure_flags="$_configure_flags --with-openssl"; \
	_configure_flags="$_configure_flags --with-ssh2"; \
	_configure_flags="$_configure_flags --with-unixodbc"; \
	\
	# Build zabbix-server for each database
	for db in postgresql mysql; do \
		./configure $_configure_flags --enable-server "--with-$db"; \
		make clean; \
		make $MAKEFLAGS; \
		mv src/zabbix_server/zabbix_server "src/zabbix_server/zabbix_server_$db"; \
		mkdir -p "../schema/zabbix-server"; \
		cp -r "database/$db" "../schema/zabbix-server/$db"; \
		rm -f "../schema/zabbix-server/$db/Makefile"*; \
	done; \
	# Build zabbix-proxy for each database
	for db in postgresql mysql sqlite3; do \
		./configure $_configure_flags --enable-proxy "--with-$db"; \
		make clean; \
		make $MAKEFLAGS; \
		mv src/zabbix_proxy/zabbix_proxy "src/zabbix_proxy/zabbix_proxy_$db"; \
		mkdir -p "../schema/zabbix-proxy"; \
		cp -r "database/$db" "../schema/zabbix-proxy/$db"; \
		rm -f "../schema/zabbix-proxy/$db/Makefile"*; \
	done; \
	ccache -s

# Build and install Zabbix
RUN set -eux; \
	cd build; \
	cd "zabbix-${ZABBIX_VER}"; \
	pkgdir=/build/zabbix-root; \
	\
	\
	true "Install Zabbix server"; \
	for db in postgresql mysql; do \
		install -Dm755 "src/zabbix_server/zabbix_server_$db" "$pkgdir/opt/zabbix/bin/zabbix_server_$db"; \
		mkdir -p "$pkgdir/opt/zabbix/share/zabbix-server"; \
		cp -vr "../schema/zabbix-server/$db" "$pkgdir/opt/zabbix/share/zabbix-server/$db"; \
	done; \
	install -Dm755 src/zabbix_get/zabbix_get "$pkgdir/opt/zabbix/bin/zabbix_get"; \
	install -Dm644 conf/zabbix_server.conf "$pkgdir/etc/zabbix/zabbix_server.conf"; \
	install -dm755 "$pkgdir/etc/zabbix/zabbix_server.conf.d"; \
	install -dm755 "$pkgdir/var/tmp/zabbix-server"; \
	install -dm755 "$pkgdir/var/lib/zabbix/alertscripts"; \
	install -dm755 "$pkgdir/var/lib/zabbix/externalscripts"; \
	install -dm755 "$pkgdir/var/lib/zabbix/sshkeys"; \
	\
	\
	true "Install Zabbix proxy"; \
	for db in postgresql mysql sqlite3; do \
		install -Dm755 "src/zabbix_proxy/zabbix_proxy_$db" "$pkgdir/opt/zabbix/bin/zabbix_proxy_$db"; \
		mkdir -p "$pkgdir/opt/zabbix/share/zabbix-proxy"; \
		cp -vr "../schema/zabbix-proxy/$db" "$pkgdir/opt/zabbix/share/zabbix-proxy/$db"; \
	done; \
	install -Dm644 conf/zabbix_proxy.conf "$pkgdir/etc/zabbix/zabbix_proxy.conf"; \
	install -dm755 "$pkgdir/etc/zabbix/zabbix_proxy.conf.d"; \
	\
	\
	true "Install Zabbix agent"; \
	install -Dm755 src/zabbix_agent/zabbix_agentd "$pkgdir/opt/zabbix/bin/zabbix_agentd"; \
	install -Dm755 src/zabbix_sender/zabbix_sender "$pkgdir/opt/zabbix/bin/zabbix_sender"; \
	install -Dm644 conf/zabbix_agentd.conf "$pkgdir/etc/zabbix/zabbix_agentd.conf"; \
	install -dm755 "$pkgdir/etc/zabbix/zabbix_agentd.conf.d"; \
	\
	\
	true "Install Zabbix agent2"; \
	install -Dm755 src/go/bin/zabbix_agent2 "$pkgdir/opt/zabbix/bin/zabbix_agent2"; \
	install -Dm644 src/go/conf/zabbix_agent2.conf "$pkgdir/etc/zabbix/zabbix_agent2.conf"; \
	install -dm755 "$pkgdir/etc/zabbix/zabbix_agent2.conf.d/plugins.d"; \
	\
	\
	true "Install Zabbix web service"; \
	install -Dm755 src/go/bin/zabbix_web_service "$pkgdir/opt/zabbix/bin/zabbix_web_service"; \
	install -Dm644 src/go/conf/zabbix_web_service.conf "$pkgdir/etc/zabbix/zabbix_web_service.conf"; \
	\
	\
	true "Install Zabbix frontend"; \
	install -dm755 "$pkgdir/var/www/html"; \
	cp -r ui/* "$pkgdir/var/www/html/"; \
	rm -f "$pkgdir/var/www/html/composer.json"; \
	rm -f "$pkgdir/var/www/html/composer.lock"; \
	rm -f "$pkgdir/var/www/html/setup.php"; \
	rm -rf "$pkgdir/var/www/html/tests"; \
	# Remove documentation from robots.txt by overwriting it
	echo -e "User-agent: *\nDisallow: /" > "$pkgdir/var/www/html/robots.txt"; \
	\
	true

# Adjust configuration
RUN set -eux; \
	pkgdir=/build/zabbix-root; \
	cd "$pkgdir"; \
	\
	\
	# Zabbix server
	\
	sed -i -e 's|^# Include=$|Include=/etc/zabbix/zabbix_server.conf.d/*.conf|' etc/zabbix/zabbix_server.conf; \
	grep -F 'Include=/etc/zabbix/zabbix_server.conf.d/*.conf' etc/zabbix/zabbix_server.conf; \
	\
	sed -i -e "/^DBUser=zabbix/d" etc/zabbix/zabbix_server.conf; \
	\
	sed -i -e "s|^StatsAllowedIP=127.0.0.1|StatsAllowedIP=127.0.0.1,::1|" etc/zabbix/zabbix_server.conf; \
	grep -F "StatsAllowedIP=127.0.0.1,::1" etc/zabbix/zabbix_server.conf; \
	\
	echo "# Socket directory" > etc/zabbix/zabbix_server.conf.d/10-defaults.conf; \
	echo "SocketDir=/run/zabbix-server" > etc/zabbix/zabbix_server.conf.d/10-defaults.conf; \
	\
	echo "# Temporary directory" > etc/zabbix/zabbix_server.conf.d/10-defaults.conf; \
	echo "TmpDir=/var/tmp/zabbix-server" > etc/zabbix/zabbix_server.conf.d/10-defaults.conf; \
	\
	echo "# SSH key location" > etc/zabbix/zabbix_server.conf.d/10-defaults.conf; \
	echo "SSHKeyLocation=/var/lib/zabbix/sshkeys" > etc/zabbix/zabbix_server.conf.d/10-defaults.conf; \
	\
	echo "# External scripts" > etc/zabbix/zabbix_server.conf.d/10-defaults.conf; \
	echo "ExternalScripts=/var/lib/zabbix/externalscripts" > etc/zabbix/zabbix_server.conf.d/10-defaults.conf; \
	\
	echo "# Alert scripts" > etc/zabbix/zabbix_server.conf.d/10-defaults.conf; \
	echo "AlertScriptsPath=/var/lib/zabbix/alertscripts" > etc/zabbix/zabbix_server.conf.d/10-defaults.conf; \
	\
	echo "# PID file" > etc/zabbix/zabbix_server.conf.d/10-defaults.conf; \
	echo "PidFile=/run/zabbix-server/zabbix_server.pid" > etc/zabbix/zabbix_server.conf.d/10-defaults.conf; \
	\
	echo "# Console log type" > etc/zabbix/zabbix_server.conf.d/10-defaults.conf; \
	echo "LogType=console" > etc/zabbix/zabbix_server.conf.d/10-defaults.conf; \
	\
	\
	# Zabbix frontend
	ln -s ../../../../etc/zabbix/zabbix.conf.php var/www/html/conf/zabbix.conf.php; \
	\
	\
	# Zabbix web service
	\
	# This is our tag for replacement in the init script
    grep '^AllowedIP=127\.0\.0\.1,::1' etc/zabbix/zabbix_web_service.conf; \
	\
	sed -i -e 's|^# LogType=file$|LogType=console|' etc/zabbix/zabbix_web_service.conf; \
	grep '^LogType=console' etc/zabbix/zabbix_web_service.conf; \
	\
	\
	# Zabbix proxy
	\
	sed -i -e 's|^# Include=$|Include=/etc/zabbix/zabbix_proxy.conf.d/*.conf|' etc/zabbix/zabbix_proxy.conf; \
	grep -F "Include=/etc/zabbix/zabbix_proxy.conf.d/*.conf" etc/zabbix/zabbix_proxy.conf; \
	\
	sed -i -e "/^DBUser=zabbix/d" etc/zabbix/zabbix_proxy.conf; \
	\
	sed -i -e "s|^StatsAllowedIP=127.0.0.1|StatsAllowedIP=127.0.0.1,::1|" etc/zabbix/zabbix_proxy.conf; \
	grep "^StatsAllowedIP=127\.0\.0\.1,::1" etc/zabbix/zabbix_proxy.conf; \
	\
	echo "# Socket directory" > etc/zabbix/zabbix_proxy.conf.d/10-defaults.conf; \
	echo "SocketDir=/run/zabbix-proxy" > etc/zabbix/zabbix_proxy.conf.d/10-defaults.conf; \
	\
	echo "# Temporary directory" > etc/zabbix/zabbix_proxy.conf.d/10-defaults.conf; \
	echo "TmpDir=/var/tmp/zabbix-proxy" > etc/zabbix/zabbix_proxy.conf.d/10-defaults.conf; \
	\
	echo "# SSH key location" > etc/zabbix/zabbix_proxy.conf.d/10-defaults.conf; \
	echo "SSHKeyLocation=/var/lib/zabbix/sshkeys" > etc/zabbix/zabbix_proxy.conf.d/10-defaults.conf; \
	\
	echo "# External scripts" > etc/zabbix/zabbix_proxy.conf.d/10-defaults.conf; \
	echo "ExternalScripts=/var/lib/zabbix/externalscripts" > etc/zabbix/zabbix_proxy.conf.d/10-defaults.conf; \
	\
	echo "# PID file" > etc/zabbix/zabbix_proxy.conf.d/10-defaults.conf; \
	echo "PidFile=/run/zabbix-proxy/zabbix_proxy.pid" > etc/zabbix/zabbix_proxy.conf.d/10-defaults.conf; \
	\
	echo "# Console log type" > etc/zabbix/zabbix_proxy.conf.d/10-defaults.conf; \
	echo "LogType=console" > etc/zabbix/zabbix_proxy.conf.d/10-defaults.conf; \
	\
	\
	# Zabbix agent
	\
	sed -i -e 's|^# Include=$|Include=/etc/zabbix/zabbix_agentd.conf.d/*.conf|' etc/zabbix/zabbix_agentd.conf; \
	grep -F "Include=/etc/zabbix/zabbix_agentd.conf.d/*.conf" etc/zabbix/zabbix_agentd.conf; \
	\
	echo "# PID file" > etc/zabbix/zabbix_agentd.conf.d/10-defaults.conf; \
	echo "PidFile=/run/zabbix-agentd/zabbix_agentd.pid" > etc/zabbix/zabbix_agentd.conf.d/10-defaults.conf; \
	\
	echo "# Console log type" > etc/zabbix/zabbix_agentd.conf.d/10-defaults.conf; \
	echo "LogType=console" > etc/zabbix/zabbix_agentd.conf.d/10-defaults.conf; \
	\
	sed -i -e 's/^((?:Hostname|Server(?:|Active))=.*)/# \1/' etc/zabbix/zabbix_agentd.conf; \
	grep '^Hostname\s*=' etc/zabbix/zabbix_agentd.conf && false || true; \
	grep '^Server\s*=' etc/zabbix/zabbix_agentd.conf && false || true; \
	grep '^ServerActive\s*=' etc/zabbix/zabbix_agentd.conf && false || true; \
	\
	\
	# Zabbix agent2
	\
	sed -i -e 's|^# Include=$|Include=/etc/zabbix/zabbix_agent2.conf.d/*.conf|' etc/zabbix/zabbix_agent2.conf; \
	grep -F "Include=/etc/zabbix/zabbix_agent2.conf.d/*.conf" etc/zabbix/zabbix_agent2.conf; \
	\
	echo "# PID file" > etc/zabbix/zabbix_agent2.conf.d/10-defaults.conf; \
	echo "PidFile=/run/zabbix-agent2/zabbix_agent2.pid" > etc/zabbix/zabbix_agent2.conf.d/10-defaults.conf; \
	\
	echo "# Console log type" > etc/zabbix/zabbix_agent2.conf.d/10-defaults.conf; \
	echo "LogType=console" > etc/zabbix/zabbix_agent2.conf.d/10-defaults.conf; \
	\
	sed -i -e 's/^((?:Hostname|Server(?:|Active))=.*)/# \1/' etc/zabbix/zabbix_agent2.conf; \
	grep '^Hostname\s*=' etc/zabbix/zabbix_agent2.conf && false || true; \
	grep '^Server\s*=' etc/zabbix/zabbix_agent2.conf && false || true; \
	grep '^ServerActive\s*=' etc/zabbix/zabbix_agent2.conf && false || true; \
	\
	mkdir -p etc/zabbix/zabbix_agent2.d/plugins.d

RUN set -eux; \
	cd build/zabbix-root; \
	scanelf --recursive --nobanner --osabi --etype "ET_DYN,ET_EXEC" .  | awk '{print $3}' | xargs \
		strip \
			--remove-section=.comment \
			--remove-section=.note \
			-R .gnu.lto_* -R .gnu.debuglto_* \
			-N __gnu_lto_slim -N __gnu_lto_v1 \
			--strip-unneeded



FROM registry.conarx.tech/containers/nginx-php/edge


ARG VERSION_INFO=
LABEL org.opencontainers.image.authors   = "Nigel Kukard <nkukard@conarx.tech>"
LABEL org.opencontainers.image.version   = "edge"
LABEL org.opencontainers.image.base.name = "registry.conarx.tech/containers/nginx-php/edge"


# Copy in built binaries
COPY --from=builder /build/zabbix-root /


RUN set -eux; \
	true "Utilities"; \
	apk add --no-cache \
		curl \
		chromium \
		fping \
		jq \
		mariadb-client \
		mariadb-connector-c \
		postgresql-client \
		openssl \
		libevent \
		libssh2 \
		libxml2 \
		net-snmp-libs \
		openipmi-libs \
		libldap \
		pcre2 \
		py3-bcrypt \
		sqlite \
		unixodbc; \
	true "User setup"; \
	addgroup -S zabbix-server; \
	adduser -S -D -H -h /dev/null -s /sbin/nologin -G zabbix-server -g zabbix-server zabbix-server; \
	addgroup -S zabbix-web-service; \
	adduser -S -D -H -h /var/tmp/zabbix-web-service -s /sbin/nologin -G zabbix-server -g zabbix-web-service zabbix-web-service; \
	addgroup -S zabbix-proxy; \
	adduser -S -D -H -h /dev/null -s /sbin/nologin -G zabbix-proxy -g zabbix-proxy zabbix-proxy; \
	addgroup -S zabbix-agent; \
	adduser -S -D -H -h /dev/null -s /sbin/nologin -G zabbix-agent -g zabbix-agent zabbix-agent; \
	addgroup -S zabbix-agent2; \
	adduser -S -D -H -h /dev/null -s /sbin/nologin -G zabbix-agent2 -g zabbix-agent2 zabbix-agent2; \
	addgroup -S zabbix-frontend; \
	adduser -S -D -H -h /dev/null -s /sbin/nologin -G zabbix-frontend -g zabbix-frontend zabbix-frontend; \
	true "Image adjustments"; \
	# Remove nginx-php test script, we have our own
	rm -f /usr/local/share/flexible-docker-containers/pre-init-tests.d/44-nginx.sh; \
	rm -f /usr/local/share/flexible-docker-containers/pre-init-tests.d/46-nginx-php.sh; \
	rm -f /usr/local/share/flexible-docker-containers/tests.d/44-nginx.sh; \
	rm -f /usr/local/share/flexible-docker-containers/tests.d/46-nginx-php.sh; \
	# Disable nginx & php by default
	mv /etc/supervisor/conf.d/nginx.conf /etc/supervisor/conf.d/nginx.conf.disabled; \
	mv /etc/supervisor/conf.d/php-fpm.conf /etc/supervisor/conf.d/php-fpm.conf.disabled; \
	mv /usr/local/share/flexible-docker-containers/healthcheck.d/44-nginx.sh /usr/local/share/flexible-docker-containers/healthcheck.d/44-nginx.sh.disabled; \
	mv /usr/local/share/flexible-docker-containers/init.d/44-nginx.sh /usr/local/share/flexible-docker-containers/init.d/44-nginx.sh.disabled; \
	mv /usr/local/share/flexible-docker-containers/init.d/46-nginx-php.sh /usr/local/share/flexible-docker-containers/init.d/46-nginx-php.sh.disabled; \
	true "Cleanup"; \
	rm -f /var/cache/apk/*


# Zabbix
COPY etc/nginx/http.d/50_vhost_default.conf.template /etc/nginx/http.d
COPY etc/nginx/http.d/55_vhost_default-ssl-certbot.conf.template /etc/nginx/http.d
COPY etc/supervisor/conf.d/zabbix-agent.conf.disabled /etc/supervisor/conf.d
COPY etc/supervisor/conf.d/zabbix-agent2.conf.disabled /etc/supervisor/conf.d
COPY etc/supervisor/conf.d/zabbix-proxy.conf.tmpl /etc/supervisor/conf.d
COPY etc/supervisor/conf.d/zabbix-server.conf.tmpl /etc/supervisor/conf.d
COPY etc/supervisor/conf.d/zabbix-web-service.conf.disabled /etc/supervisor/conf.d
COPY usr/local/share/flexible-docker-containers/healthcheck.d/48-zabbix-agent.sh /usr/local/share/flexible-docker-containers/healthcheck.d
COPY usr/local/share/flexible-docker-containers/healthcheck.d/48-zabbix-agent2.sh /usr/local/share/flexible-docker-containers/healthcheck.d
COPY usr/local/share/flexible-docker-containers/healthcheck.d/48-zabbix-proxy.sh /usr/local/share/flexible-docker-containers/healthcheck.d
COPY usr/local/share/flexible-docker-containers/healthcheck.d/48-zabbix-server.sh /usr/local/share/flexible-docker-containers/healthcheck.d
COPY usr/local/share/flexible-docker-containers/healthcheck.d/48-zabbix-webservice.sh /usr/local/share/flexible-docker-containers/healthcheck.d
COPY usr/local/share/flexible-docker-containers/init.d/48-zabbix.sh /usr/local/share/flexible-docker-containers/init.d
COPY usr/local/share/flexible-docker-containers/pre-init.d/48-zabbix.sh /usr/local/share/flexible-docker-containers/pre-init.d
COPY usr/local/share/flexible-docker-containers/pre-init-tests.d/48-zabbix.sh /usr/local/share/flexible-docker-containers/pre-init-tests.d
COPY usr/local/share/flexible-docker-containers/pre-exec-tests.d/48-zabbix.sh /usr/local/share/flexible-docker-containers/pre-exec-tests.d
COPY usr/local/share/flexible-docker-containers/tests.d/48-zabbix-agent.sh /usr/local/share/flexible-docker-containers/tests.d
COPY usr/local/share/flexible-docker-containers/tests.d/48-zabbix-agent2.sh /usr/local/share/flexible-docker-containers/tests.d
COPY usr/local/share/flexible-docker-containers/tests.d/48-zabbix-frontend.sh /usr/local/share/flexible-docker-containers/tests.d
COPY usr/local/share/flexible-docker-containers/tests.d/48-zabbix-proxy.sh /usr/local/share/flexible-docker-containers/tests.d
COPY usr/local/share/flexible-docker-containers/tests.d/48-zabbix-server.sh /usr/local/share/flexible-docker-containers/tests.d
COPY usr/local/share/flexible-docker-containers/tests.d/48-zabbix-webservice.sh /usr/local/share/flexible-docker-containers/tests.d
COPY usr/local/share/flexible-docker-containers/tests.d/99-zabbix.sh /usr/local/share/flexible-docker-containers/tests.d


RUN set -eux; \
	true "Flexible Docker Containers"; \
	if [ -n "$VERSION_INFO" ]; then echo "$VERSION_INFO" >> /.VERSION_INFO; fi; \
	fdc set-perms


EXPOSE 10050:10053
EXPOSE 80
