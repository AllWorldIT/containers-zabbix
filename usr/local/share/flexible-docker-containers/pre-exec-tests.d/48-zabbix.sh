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


if [ "$ZABBIX_MODE" = "server" ]; then

	# shellcheck disable=SC2154
	if [ "$database_type_zabbix" = "postgresql" ]; then
		export PGPASSWORD="$POSTGRES_PASSWORD"

		fdc_notice "Adding Zabbix proxy configuration"
		(
			echo "DELETE FROM ids WHERE table_name='hosts' AND field_name='hostid';"
			echo "DELETE FROM ids WHERE table_name='interface' AND field_name='interfaceid';"
			echo "INSERT INTO ids (table_name,field_name,nextid) VALUES ('hosts','hostid',(SELECT MAX(hostid) AS id FROM hosts)+1);"
			echo "INSERT INTO ids (table_name,field_name,nextid) VALUES ('interface','interfaceid',(SELECT MAX(interfaceid) AS id FROM interface)+1);"

			echo "INSERT INTO hosts (hostid,host,description,proxy_address,status,tls_accept,tls_connect) VALUES ((SELECT nextid FROM ids WHERE table_name = 'hosts' AND field_name = 'hostid')+1,'Zabbix proxy','Zabbix proxy','zabbix-proxy',5,1,1);"

			echo "INSERT INTO hosts (hostid,host,description,status,tls_accept,tls_connect,tls_psk_identity,tls_psk) VALUES ((SELECT nextid FROM ids WHERE table_name = 'hosts' AND field_name = 'hostid')+2,'Zabbix proxy2','Zabbix proxy2',6,1,2,'proxytest','01234567890abcdef01234567890abcdef');"
			echo "INSERT INTO interface (interfaceid,hostid,main,type,useip,dns,port) VALUES ((SELECT nextid FROM ids WHERE table_name = 'interface' AND field_name = 'interfaceid')+1,(SELECT nextid FROM ids WHERE table_name = 'hosts' AND field_name = 'hostid')+2,1,0,0,'zabbix-proxy2',10051);"

			echo "INSERT INTO host_rtdata (hostid) VALUES ((SELECT hostid FROM hosts WHERE host = 'Zabbix proxy'));"
			echo "INSERT INTO host_rtdata (hostid) VALUES ((SELECT hostid FROM hosts WHERE host = 'Zabbix proxy2'));"

			echo "DELETE FROM ids WHERE table_name='hosts' AND field_name='hostid';"
			echo "DELETE FROM ids WHERE table_name='interface' AND field_name='interfaceid';"
			echo "INSERT INTO ids (table_name,field_name,nextid) VALUES ('hosts','hostid',(SELECT MAX(hostid) AS id FROM hosts)+1);"
			echo "INSERT INTO ids (table_name,field_name,nextid) VALUES ('interface','interfaceid',(SELECT MAX(interfaceid) AS id FROM interface)+1);"
		) | psql -h "$POSTGRES_HOST" -U "$POSTGRES_USER" -w "$POSTGRES_DATABASE" -q -v ON_ERROR_STOP=ON

		unset PGPASSWORD

	elif [ "$database_type_zabbix" = "mysql" ]; then
		export MYSQL_PWD="$MYSQL_PASSWORD"

		fdc_notice "Adding Zabbix proxy configuration"
		(
			echo "DELETE FROM ids WHERE table_name='hosts' AND field_name='hostid';"
			echo "DELETE FROM ids WHERE table_name='interface' AND field_name='interfaceid';"
			echo "INSERT INTO ids (table_name,field_name,nextid) VALUES ('hosts','hostid',(SELECT MAX(hostid) AS id FROM hosts)+1);"
			echo "INSERT INTO ids (table_name,field_name,nextid) VALUES ('interface','interfaceid',(SELECT MAX(interfaceid) AS id FROM interface)+1);"

			echo "INSERT INTO hosts (hostid,host,description,proxy_address,status,tls_accept,tls_connect) VALUES ((SELECT nextid FROM ids WHERE table_name = 'hosts' AND field_name = 'hostid')+1,'Zabbix proxy','Zabbix proxy','zabbix-proxy',5,1,1);"

			echo "INSERT INTO hosts (hostid,host,description,status,tls_accept,tls_connect,tls_psk_identity,tls_psk) VALUES ((SELECT nextid FROM ids WHERE table_name = 'hosts' AND field_name = 'hostid')+2,'Zabbix proxy2','Zabbix proxy2',6,1,2,'proxytest','01234567890abcdef01234567890abcdef');"
			echo "INSERT INTO interface (interfaceid,hostid,main,type,useip,dns,port) VALUES ((SELECT nextid FROM ids WHERE table_name = 'interface' AND field_name = 'interfaceid')+1,(SELECT nextid FROM ids WHERE table_name = 'hosts' AND field_name = 'hostid')+2,1,0,0,'zabbix-proxy2',10051);"

			echo "INSERT INTO host_rtdata (hostid) VALUES ((SELECT hostid FROM hosts WHERE host = 'Zabbix proxy'));"
			echo "INSERT INTO host_rtdata (hostid) VALUES ((SELECT hostid FROM hosts WHERE host = 'Zabbix proxy2'));"

			echo "DELETE FROM ids WHERE table_name='hosts' AND field_name='hostid';"
			echo "DELETE FROM ids WHERE table_name='interface' AND field_name='interfaceid';"
			echo "INSERT INTO ids (table_name,field_name,nextid) VALUES ('hosts','hostid',(SELECT MAX(hostid) AS id FROM hosts)+1);"
			echo "INSERT INTO ids (table_name,field_name,nextid) VALUES ('interface','interfaceid',(SELECT MAX(interfaceid) AS id FROM interface)+1);"
		) | mariadb --skip-ssl --host "$MYSQL_HOST" --user "$MYSQL_USER" "$MYSQL_DATABASE"

		unset MYSQL_PWD
	fi

fi
