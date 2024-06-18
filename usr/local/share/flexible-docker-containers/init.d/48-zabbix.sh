#!/bin/bash
# Copyright (c) 2022-2023, AllWorldIT.
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


# Initalizae our SQL array
database_sql=()


# Setup basic stuff
if [ "$ZABBIX_MODE" = "server" ]; then
	fdc_info "Processing config for Zabbix Server"
	daemon=zabbix-server

	database_sql=(schema images data)
	# TimescaleDB
	if [ "$ZABBIX_DATABASE_TYPE" = "timescaledb" ]; then
		database_sql+=(timescaledb/schema)
	fi

	ZABBIX_ADMIN_USERNAME=${ZABBIX_ADMIN_USERNAME:-Admin}

	ZABBIX_SERVER_AGENT_NAME=${ZABBIX_SERVER_AGENT_NAME:-Zabbix server}

elif [ "$ZABBIX_MODE" = "frontend" ]; then
	fdc_info "Processing config for Zabbix Frontend"
	daemon=zabbix-frontend

	ZABBIX_SERVER_AGENT_HOSTNAME=${ZABBIX_SERVER_AGENT_HOSTNAME:-zabbix-server}
	ZABBIX_SERVER_AGENT_NAME=${ZABBIX_SERVER_AGENT_NAME:-Zabbix server}

elif [ "$ZABBIX_MODE" = "webservice" ]; then
	fdc_info "Processing config for Zabbix Web Service"
	daemon=zabbix-web-service

elif [ "$ZABBIX_MODE" = "proxy" ]; then
	fdc_info "Processing config for Zabbix Proxy"
	daemon=zabbix-proxy
	database_sql=(schema)

elif [ "$ZABBIX_MODE" = "agent" ]; then
	fdc_info "Processing config for Zabbix Agent"
	daemon=zabbix-agent

elif [ "$ZABBIX_MODE" = "agent2" ]; then
	fdc_info "Processing config for Zabbix Agent2"
	daemon=zabbix-agent2

else
	fdc_error "Environment variable 'ZABBIX_MODE' must be set to either 'server', 'webservice', 'frontend', 'proxy', 'agent' or 'agent2'."
	false
fi
# Fixup config directory
zabbix_conf_dir=$ZABBIX_MODE
if [ "$zabbix_conf_dir" = "agent" ]; then
	zabbix_conf_dir="agentd"
fi


# Zabbix server clients must have a hostname set
if [ "$ZABBIX_MODE" = "proxy" ] || [ "$ZABBIX_MODE" = "agent" ] || [ "$ZABBIX_MODE" = "agent2" ]; then
	fdc_info "Configuring Zabbix client daemon $ZABBIX_MODE"

	# Hostname
	if [ -z "$ZABBIX_HOSTNAME" ]; then
		fdc_error "Environment variable 'ZABBIX_HOSTNAME' must be set when 'ZABBIX_MODE=$ZABBIX_MODE'."
		false
	fi
	echo "Hostname=$ZABBIX_HOSTNAME" > "/etc/zabbix/zabbix_$zabbix_conf_dir.conf.d/20-hostname.conf"

	if [ -z "$ZABBIX_SERVER" ]; then
		fdc_error "Environment variable 'ZABBIX_SERVER' must be set."
		false
	fi
	# Setup custom config
	set | grep -E '^ZABBIX_CONFIG_' | sed -e 's/ZABBIX_CONFIG_//' > "/etc/zabbix/zabbix_$zabbix_conf_dir.conf.d/90-custom.conf"
fi
# Config proxy
if [ "$ZABBIX_MODE" = "proxy" ]; then
	echo "Server=$ZABBIX_SERVER" > "/etc/zabbix/zabbix_$zabbix_conf_dir.conf.d/40-server.conf"
	if [ "$ZABBIX_PROXY_MODE" = "active" ]; then
		echo "ProxyMode=0" >  "/etc/zabbix/zabbix_$zabbix_conf_dir.conf.d/30-proxy-mode.conf"
	elif [ "$ZABBIX_PROXY_MODE" = "passive" ]; then
		echo "ProxyMode=1" >  "/etc/zabbix/zabbix_$zabbix_conf_dir.conf.d/30-proxy-mode.conf"
	else
		fdc_error "Environment variable 'ZABBIX_PROXY_MODE' must be set to either 'passive' or 'active'."
		false
	fi
# Config agent
elif [ "$ZABBIX_MODE" = "agent" ] || [ "$ZABBIX_MODE" = "agent2" ]; then
	echo "ServerActive=$ZABBIX_SERVER" > "/etc/zabbix/zabbix_$zabbix_conf_dir.conf.d/40-server.conf"
	if [ "$ZABBIX_AGENT_MODE" = "active" ]; then
		# NK: StartAgents is not supported by agent2 it seems
		if [ "$ZABBIX_MODE" = "agent" ]; then
			echo "StartAgents=0" >> "/etc/zabbix/zabbix_$zabbix_conf_dir.conf.d/40-server.conf"
		fi
	elif [ "$ZABBIX_AGENT_MODE" = "passive" ]; then
		echo "Server=$ZABBIX_SERVER" >> "/etc/zabbix/zabbix_$zabbix_conf_dir.conf.d/40-server.conf"
	else
		fdc_error "Environment variable 'ZABBIX_AGENT_MODE' must be set to either 'passive' or 'active'."
		false
	fi
fi

# For encryption, it only applies to proxies and agents
if [ "$ZABBIX_MODE" = "proxy" ] || [ "$ZABBIX_MODE" = "agent" ] || [ "$ZABBIX_MODE" = "agent2" ]; then
	fdc_info "Configuring Zabbix client encryption for $ZABBIX_MODE"
	# Encryption config
	if [ -n "$ZABBIX_TLS_PSKIDENTITY" ]; then
		if [ -z "$ZABBIX_TLS_PSKKEY" ]; then
			fdc_error "Environment variable 'ZABBIX_TLS_PSKKEY' must be specified with 'ZABBIX_TLS_PSKIDENTITY'"
			false
		fi
		# Setup PSK encryption
		{
			echo "TLSAccept=psk"
			echo "TLSConnect=psk"
			echo "TLSPSKIdentity=$ZABBIX_TLS_PSKIDENTITY"
			echo "TLSPSKFile=/etc/zabbix/zabbix_$zabbix_conf_dir.conf.d/40-server.key"
		} >> "/etc/zabbix/zabbix_$zabbix_conf_dir.conf.d/40-server.conf"
		# Setup key file
		echo "$ZABBIX_TLS_PSKKEY" > "/etc/zabbix/zabbix_$zabbix_conf_dir.conf.d/40-server.key"
		chmod 0640 "/etc/zabbix/zabbix_$zabbix_conf_dir.conf.d/40-server.key"
		chown "root:$daemon" "/etc/zabbix/zabbix_$zabbix_conf_dir.conf.d/40-server.key"
	fi
fi

# The agent must be enabled for the server
if [ "$ZABBIX_MODE" = "server" ]; then
	fdc_info "Configuring Zabbix Server agent"
	echo "Hostname=$ZABBIX_SERVER_AGENT_NAME" > "/etc/zabbix/zabbix_agentd.conf.d/20-hostname.conf"
	echo "Server=localhost" > "/etc/zabbix/zabbix_agentd.conf.d/40-server.conf"
	echo "ServerActive=localhost" >> "/etc/zabbix/zabbix_agentd.conf.d/40-server.conf"

	echo "StartConnectors=1" >> "/etc/zabbix/zabbix_$zabbix_conf_dir.conf.d/60-connectors.conf"

	# Check if we're configuring the web service
	if [ -n "$ZABBIX_SERVER_WEBSERVICE_URL" ]; then
		echo "WebServiceURL=$ZABBIX_SERVER_WEBSERVICE_URL" > "/etc/zabbix/zabbix_$zabbix_conf_dir.conf.d/60-reportwriters.conf"
		echo "StartReportWriters=1" >> "/etc/zabbix/zabbix_$zabbix_conf_dir.conf.d/60-reportwriters.conf"
	fi
	# Setup custom config
	set | grep -E '^ZABBIX_CONFIG_' | sed -e 's/ZABBIX_CONFIG_//' > "/etc/zabbix/zabbix_$zabbix_conf_dir.conf.d/90-custom.conf"
fi

# Zabbix web service must have allowed IP's set
if [ "$ZABBIX_MODE" = "webservice" ]; then
	fdc_info "Configuring Zabbix Web Service"
	# Allowed IP's
	if [ -z "$ZABBIX_WEBSERVICE_ALLOWEDIP" ]; then
		fdc_error "Environment variable 'ZABBIX_WEBSERVICE_ALLOWEDIP' must be set when 'ZABBIX_MODE=$ZABBIX_MODE'."
		false
	fi
	sed -i -e "s|^AllowedIP=127.0.0.1,::1|AllowedIP=127.0.0.1,::1,$ZABBIX_WEBSERVICE_ALLOWEDIP|" /etc/zabbix/zabbix_web_service.conf
	# Check it was set
	if ! grep -q -E '^AllowedIP=127.0.0.1,::1,'"$ZABBIX_WEBSERVICE_ALLOWEDIP"'$' /etc/zabbix/zabbix_web_service.conf; then
		fdc_error "Failed to set 'AllowedIP=' in '/etc/zabbix/zabbix_web_service.conf'"
		false
	fi
	# Setup custom config
	set | grep -E '^ZABBIX_CONFIG_' | sed -e 's/ZABBIX_CONFIG_//' >> /etc/zabbix/zabbix_web_service.conf
fi



#
# Setup temporary directories for all modes
#
fdc_info "Setting up Zabbix runtime directories for $ZABBIX_MODE"
if [ ! -d "/run/$daemon" ]; then
	mkdir "/run/$daemon"
fi
if [ ! -d "/var/tmp/$daemon" ]; then
	mkdir "/var/tmp/$daemon"
fi

chown "root:$daemon" "/run/$daemon" "/var/tmp/$daemon"
chmod 0750 "/run/$daemon" "/var/tmp/$daemon"



#
# Service and database configuration
#

if [ "$ZABBIX_MODE" = "server" ] || [ "$ZABBIX_MODE" = "proxy" ] || [ "$ZABBIX_MODE" = "frontend" ]; then
	fdc_info "Configuring database for Zabbix daemon $ZABBIX_MODE"

	# Work out database details
	case "$ZABBIX_DATABASE_TYPE" in
		mysql)
			if [ -z "$MYSQL_DATABASE" ]; then
				fdc_error "Environment variable 'MYSQL_DATABASE' is required"
				false
			fi
			# Check for a few things we need
			if [ -z "$MYSQL_HOST" ]; then
				fdc_error "Environment variable 'MYSQL_HOST' is required"
				false
			fi
			if [ -z "$MYSQL_USER" ]; then
				fdc_error "Environment variable 'MYSQL_USER' is required"
				false
			fi
			if [ -z "$MYSQL_PASSWORD" ]; then
				fdc_error "Environment variable 'MYSQL_PASSWORD' is required"
				false
			fi
			database_type_zabbix=mysql
			database_type_frontend=MYSQL
			database_host=$MYSQL_HOST
			database_name=$MYSQL_DATABASE
			database_username=$MYSQL_USER
			database_password=$MYSQL_PASSWORD
			;;

		postgresql|timescaledb)
			# Check for a few things we need
			if [ -z "$POSTGRES_DATABASE" ]; then
				fdc_error "Environment variable 'POSTGRES_DATABASE' is required"
				false
			fi
			if [ -z "$POSTGRES_HOST" ]; then
				fdc_error "Environment variable 'POSTGRES_HOST' is required"
				false
			fi
			if [ -z "$POSTGRES_USER" ]; then
				fdc_error "Environment variable 'POSTGRES_USER' is required"
				false
			fi
			if [ -z "$POSTGRES_PASSWORD" ]; then
				fdc_error "Environment variable 'POSTGRES_PASSWORD' is required"
				false
			fi
			database_type_zabbix=postgresql
			database_type_frontend=POSTGRESQL
			database_host=$POSTGRES_HOST
			database_name=$POSTGRES_DATABASE
			database_username=$POSTGRES_USER
			database_password=$POSTGRES_PASSWORD
			;;

		*)
			fdc_error "Environment variable 'ZABBIX_DATABASE_TYPE' must be set when 'ZABBIX_MODE' is set to 'server', 'frontend' or 'proxy'."
			false
			;;
	esac
fi

if [ "$ZABBIX_MODE" = "server" ] || [ "$ZABBIX_MODE" = "proxy" ]; then
	fdc_info "Configuring files and permissions for Zabbix daemon $ZABBIX_MODE"

	# SSH is a bit particular about permissions, but we'll try 0640 for now until we have a problem
	chown "root:$daemon" /var/lib/zabbix/sshkeys
	chmod 0750 /var/lib/zabbix/sshkeys
	find /var/lib/zabbix/sshkeys -type f -name "id_*" -print0 | xargs -r chown "root:$daemon" || : > /dev/null 2>&1
	find /var/lib/zabbix/sshkeys -type f -name "id_*" -print0 | xargs -r chmod 0640 || : > /dev/null 2>&1
	find /var/lib/zabbix/sshkeys -type f -name "*.pub" -print0 | xargs -r chown "root:$daemon" || : > /dev/null 2>&1
	find /var/lib/zabbix/sshkeys -type f -name "*.pub" -print0 | xargs -r chmod 0640 || : > /dev/null 2>&1

	chown root:root /var/lib/zabbix/alertscripts
	find /var/lib/zabbix/alertscripts -type f -print0 | xargs -r chmod 0755 || : > /dev/null 2>&1
	chmod 0755 /var/lib/zabbix/alertscripts

	chown root:root /var/lib/zabbix/externalscripts
	find /var/lib/zabbix/externalscripts -type f -print0 | xargs -r chmod 0755 || : > /dev/null 2>&1
	chmod 0755 /var/lib/zabbix/externalscripts

	# Enable the relevant daemon
	sed -e "s/@ZABBIX_DB@/$database_type_zabbix/" < "/etc/supervisor/conf.d/$daemon.conf.tmpl" > "/etc/supervisor/conf.d/$daemon.conf"

	# Output config
	cat <<EOF > "/etc/zabbix/zabbix_$ZABBIX_MODE.conf.d/30-database.conf"
# Database details
DBHost=$database_host
DBName=$database_name
DBUser=$database_username
DBPassword=$database_password
EOF
	chown "root:$daemon" "/etc/zabbix/zabbix_$ZABBIX_MODE.conf.d/30-database.conf"
	chmod 0640 "/etc/zabbix/zabbix_$ZABBIX_MODE.conf.d/30-database.conf"

fi

# Zabbix server needs the agent enabled too
if [ "$ZABBIX_MODE" = "agent" ] || [ "$ZABBIX_MODE" = "server" ]; then
	fdc_info "Enabling Zabbix Agent daemon"
	# Check if we need to enable the agent service
	if [ -e /etc/supervisor/conf.d/zabbix-agent.conf.disabled ]; then
		mv "/etc/supervisor/conf.d/zabbix-agent.conf"{.disabled,}
	fi

elif [ "$ZABBIX_MODE" = "agent2" ]; then
	fdc_info "Enabling Zabbix Agent2 daemon"
	# Check if we need to enable the agent2 service
	if [ -e /etc/supervisor/conf.d/zabbix-agent2.conf.disabled ]; then
		mv "/etc/supervisor/conf.d/zabbix-agent2.conf"{.disabled,}
	fi

# Zabbix frontend needs nginx and php-fpm
elif [ "$ZABBIX_MODE" = "frontend" ]; then
	fdc_info "Enabling Zabbix Frontend daemons"
	# Check if we need to enable the nginx and php-fpm services
	if [ -e /etc/supervisor/conf.d/nginx.conf.disabled ]; then
		mv "/etc/supervisor/conf.d/nginx.conf"{.disabled,}
	fi
	if [ -e /etc/supervisor/conf.d/php-fpm.conf.disabled ]; then
		mv "/etc/supervisor/conf.d/php-fpm.conf"{.disabled,}
	fi

	cat <<EOF > /etc/zabbix/zabbix.conf.php
<?php
// Database config
global \$DB;
\$DB['TYPE'] = '$database_type_frontend';
\$DB['SERVER'] = '$database_host';
//\$DB['PORT'] = '0';
\$DB['DATABASE'] = '$database_name';
\$DB['USER'] = '$database_username';
\$DB['PASSWORD'] = '$database_password';
\$DB['SCHEMA'] = '';

// Zabbix server agent details
\$ZBX_SERVER = '$ZABBIX_SERVER_AGENT_HOSTNAME';
\$ZBX_SERVER_PORT = '10051';
\$ZBX_SERVER_NAME = '$ZABBIX_SERVER_AGENT_NAME';

// Other settings
\$IMAGE_FORMAT_DEFAULT = IMAGE_FORMAT_PNG;
\$DB['DOUBLE_IEEE754'] = 'true';
EOF
	if [ -n "$ZABBIX_FRONTEND_SSO_USE_PROXY_HEADERS" ]; then
		cat <<EOF >> /etc/zabbix/zabbix.conf.php

// SSO overrides
\$SSO['SETTINGS'] = ['use_proxy_headers' => true];
EOF
	fi
	chown root:www-data /etc/zabbix/zabbix.conf.php
	chmod 0640 /etc/zabbix/zabbix.conf.php

elif [ "$ZABBIX_MODE" = "webservice" ]; then
	fdc_info "Enabling Zabbix Web Service daemon"
	# Check if we need to enable the service
	if [ -e /etc/supervisor/conf.d/zabbix-web-service.conf.disabled ]; then
		mv "/etc/supervisor/conf.d/zabbix-web-service.conf"{.disabled,}
	fi
fi



#
# Database initialization
#

# This only used by the Zabbix server mode

if [ "${#database_sql[@]}" -gt 0 ]; then
	fdc_info "Setting up database ($ZABBIX_DATABASE_TYPE) for Zabbix daemon $ZABBIX_MODE"

	# Generate password
	if [ -n "$ZABBIX_ADMIN_PASSWORD" ]; then
		zabbix_admin_password_hashed=$(echo "$ZABBIX_ADMIN_PASSWORD" | python -c 'import bcrypt; import sys; print(bcrypt.hashpw(sys.stdin.readline().rstrip().encode("UTF-8"), bcrypt.gensalt(rounds=10)).decode("UTF-8"));')
	fi

	if [ "$database_type_zabbix" = "postgresql" ]; then
		export PGPASSWORD="$POSTGRES_PASSWORD"

		while true; do
			fdc_notice "Zabbix waiting for PostgreSQL server '$POSTGRES_HOST'..."
			if pg_isready -d "$POSTGRES_DATABASE" -h "$POSTGRES_HOST" -U "$POSTGRES_USER"; then
				fdc_notice "PostgreSQL server is UP, continuing"
				break
			fi
			sleep 1
		done

		# Check if the domain table exists, if not, create the database
		if echo "\dt users" | psql -h "$POSTGRES_HOST" -U "$POSTGRES_USER" -w "$POSTGRES_DATABASE" -v ON_ERROR_STOP=ON  2>&1 | grep -q 'Did not find any relation'; then
			fdc_notice "Initializing Zabbix PostgreSQL database"
			# TimescaleDB
			if [ "$ZABBIX_DATABASE_TYPE" = "timescaledb" ]; then
				fdc_notice "Enabling Timescaledb for Zabbix PostgreSQL database"
				echo "CREATE EXTENSION IF NOT EXISTS timescaledb CASCADE;" | psql -h "$POSTGRES_HOST" -U "$POSTGRES_USER" -w "$POSTGRES_DATABASE" -v ON_ERROR_STOP=ON 2>&1
			fi

			# Normal PostgreSQL
			for i in "${database_sql[@]}"; do
				fdc_notice "Loading SQL '$i' into Zabbix PostgreSQL database"
				psql -h "$POSTGRES_HOST" -U "$POSTGRES_USER" -w "$POSTGRES_DATABASE" -v ON_ERROR_STOP=ON 2>&1 < "/opt/zabbix/share/$daemon/$database_type_zabbix/$i.sql"
			done
			# Check if we're updating the admin user details
			if [ -n "$zabbix_admin_password_hashed" ]; then
				fdc_notice "Setting admin details for Zabbix PostgreSQL database"
				echo "UPDATE users SET username = '$ZABBIX_ADMIN_USERNAME', passwd = '$zabbix_admin_password_hashed' WHERE username = 'Admin';" | psql -h "$POSTGRES_HOST" -U "$POSTGRES_USER" -w "$POSTGRES_DATABASE" -v ON_ERROR_STOP=ON 2>&1
			else
				fdc_notice "NOT setting admin details for Zabbix PostgreSQL database"
			fi

		fi

		unset PGPASSWORD

	elif [ "$database_type_zabbix" = "mysql" ]; then
		export MYSQL_PWD="$MYSQL_PASSWORD"

		while true; do
			fdc_notice "Zabbix waiting for MySQL server '$MYSQL_HOST'..."
			if mysqladmin ping --host "$MYSQL_HOST" --user "$MYSQL_USER" --silent --connect-timeout=2; then
				fdc_notice "MySQL server is UP, continuing"
				break
			fi
			sleep 1
		done

		# Check if the domain table exists, if not, create the database
		if echo "SHOW CREATE TABLE users;" | mariadb --skip-ssl --host "$MYSQL_HOST" --user "$MYSQL_USER" "$MYSQL_DATABASE" 2>&1 | grep -q "ERROR 1146.*Table.*doesn't exist"; then
			fdc_notice "Initializing Zabbix MySQL database"
			{
				for i in "${database_sql[@]}"; do
					cat "/opt/zabbix/share/$daemon/$database_type_zabbix/$i.sql"
				done
				# Check if we're updating the admin user details
				if [ -n "$zabbix_admin_password_hashed" ]; then
					echo "UPDATE users SET username = '$ZABBIX_ADMIN_USERNAME', passwd = '$zabbix_admin_password_hashed' WHERE username = 'Admin';"
				fi
			} | mariadb --skip-ssl --host "$MYSQL_HOST" --user "$MYSQL_USER" "$MYSQL_DATABASE"
		fi

		unset MYSQL_PWD
	fi
fi
