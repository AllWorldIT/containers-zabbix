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



function zabbix_api_call() {
	local bearer_token=$1; shift
	local request=$1; shift

	local i
	local api_result
	for i in {3..0}; do
		api_result=$(
			curl --max-time 300 --fail \
				--trace-ascii output.log \
				--header "Content-Type: application/json-rpc" \
				--header "Authorization: Bearer $bearer_token" \
				--data "$request" \
				"$@" \
				"http://localhost/api_jsonrpc.php" || :
		)
		{
			echo "ZABBIX_API_CALL STATUS ($i):"
			cat output.log
		} >&2
		if [ -n "$api_result" ]; then
			break
		fi
		sleep 1
	done

	if [ "$i" = 0 ]; then
		fdc_test_fail zabbix-frontend "API call timeout" >&2
		return 1
	fi

	echo "$api_result"
	return 0
}



function test_zabbix_frontend() {
	ipv=$1

	fdc_test_start zabbix-frontend "Testing frontend API using IPv$ipv"
	fdc_test_progress zabbix-frontend "Getting API bearer token using IPv$ipv"
	for i in {5..0}; do
		# Grab API bearer token
		api_result=$(
			curl --max-time 300 --fail \
				--trace-ascii output.log \
				"--ipv$ipv" \
				--header "Content-Type: application/json-rpc" \
				--data '{"jsonrpc":"2.0","method":"user.login","params":{"username":"'"$ZABBIX_ADMIN_USERNAME"'","password":"'"$ZABBIX_ADMIN_PASSWORD"'"},"id":1}' \
				"http://localhost/api_jsonrpc.php" || :
		)
		{
			echo "TEST_ZABBIX_FRONTEND STATUS ($i):"
			cat output.log
		} >&2
		if [ -z "$api_result" ]; then
			sleep 1
			continue
		fi
		bearer_token=$(echo "$api_result" | jq .result | sed -e 's/"//g')
		if [ -z "$bearer_token" ]; then
			fdc_test_fail zabbix-frontend "Failed to get API bearer token using IPv$ipv"
			cat output.log
			false
		fi
		if [ "$bearer_token" != "null" ]; then
			fdc_test_progress zabbix-frontend "Got API bearer token using IPv$ipv"
			break
		fi
		fdc_test_progress zabbix-frontend "Waiting for bearer token from API using IPv$ipv ($i)..."
		sleep 1
	done
	# NK: a value of 0 means timeout
	if [ "$i" = "0" ]; then
		fdc_test_fail zabbix-frontend "Timeout while getting API bearer token"
		cat output.log
		false
	fi
	echo "API RESULT GET TOKEN: $api_result => $bearer_token"

	fdc_test_progress zabbix-frontend "Getting hostid via API using IPv$ipv"
	api_result=$(
		zabbix_api_call "$bearer_token" \
			'{"jsonrpc":"2.0","method":"host.get","params":{"filter":{"host":["'"$ZABBIX_SERVER_AGENT_NAME"'"]}},"id":1}' \
			"--ipv$ipv"
	)
	hostid=$(echo "$api_result" | jq ".result[0].hostid" | sed -e 's/"//g')
	if [ -z "$hostid" ]; then
		fdc_test_fail zabbix-frontend "Failed to get hostid via API using IPv$ipv"
		cat output.log
		false
	fi

	fdc_test_progress zabbix-frontend "Waiting for agent item 'system.uptime' to update via API using IPv$ipv"
	last_value=""
	for i in {240..0}; do
		api_result=$(
			zabbix_api_call "$bearer_token" \
				'{"jsonrpc":"2.0","method":"item.get","params":{"output":"extend","hostids":"'"$hostid"'","search":{"key_":"system.uptime"}},"id":1}' \
				"--ipv$ipv"
		)

		value=$(echo "$api_result" | jq ".result[0].lastvalue" | sed -e 's/"//g')

		# If last value is set and we have a new value, then break
		if [ -n "$last_value" ] && [ "$last_value" != "$value" ]; then
			fdc_test_progress zabbix-frontend "Got last agent item 'system.uptime' value $last_value via IPv$ipv with current value $value ... OK"
			break
		fi
		if [ -n "$value" ]; then
			last_value=$value
		fi
		fdc_test_progress zabbix-frontend "Waiting for agent item 'system.uptime' value to change using IPv$ipv ($i)..."
		sleep 1
	done
	# NK: a value of 0 means timeout
	if [ "$i" = "0" ]; then
		fdc_test_fail zabbix-frontend "Timeout while waiting for agent item 'system.uptime'"
		cat output.log
		false
	fi
	fdc_test_pass zabbix-frontend "API test of data from agent passed using IPv$ipv"



	fdc_test_progress zabbix-frontend "Waiting for proxy server 'lastacess' via API using IPv$ipv"
	last_value=""
	for i in {240..0}; do
		api_result=$(
			zabbix_api_call "$bearer_token" \
				'{"jsonrpc":"2.0","method":"proxy.get","params":{"output":"extend","filter":{"host":"Zabbix proxy"}},"id":1}' \
				"--ipv$ipv"
		)

		value=$(echo "$api_result" | jq ".result[0].lastaccess" | sed -e 's/"//g')

		# If last value is set and we have a new value, then break
		if [ -n "$last_value" ] && [ "$last_value" != "$value" ]; then
			fdc_test_progress zabbix-frontend "Got last proxy access value $last_value via IPv$ipv with current value $value ... OK"
			break
		fi
		if [ -n "$value" ]; then
			last_value=$value
		fi
		fdc_test_progress zabbix-frontend "Waiting for last proxy access value to change ($i) using IPv$ipv..."
		sleep 1
	done
	# NK: a value of 0 means timeout
	if [ "$i" = "0" ]; then
		fdc_test_fail zabbix-frontend "Timeout while waiting for proxy last access using IPv$ipv"
		cat output.log
		false
	fi
	fdc_test_pass zabbix-frontend "API test of proxy data from agent passed using IPv$ipv"

}



function test_zabbix_agent() {
	agent_hostname=$1
	agent_name=$2
	agent_psk_identity=$3
	agent_psk_key=$4

	fdc_test_start zabbix-frontend "Creating $agent_hostname using frontend API"
	fdc_test_progress zabbix-frontend "Getting API bearer token for $agent_hostname"
	for i in {3..0}; do
		# Grab API bearer token
		api_result=$(
			curl --max-time 300 --fail \
				--trace-ascii output.log \
				--header "Content-Type: application/json-rpc" \
				--data '{"jsonrpc":"2.0","method":"user.login","params":{"username":"'"$ZABBIX_ADMIN_USERNAME"'","password":"'"$ZABBIX_ADMIN_PASSWORD"'"},"id":1}' \
				"http://localhost/api_jsonrpc.php" \
				|| :
		)

		{
			echo "TEST_ZABBIX_FRONTEND STATUS ($i):"
			cat output.log
		} >&2

		if [ -z "$api_result" ]; then
			sleep 1
			continue
		fi

		bearer_token=$(echo "$api_result" | jq .result | sed -e 's/"//g')
		if [ -z "$bearer_token" ]; then
			fdc_test_fail zabbix-frontend "Failed to get API bearer token for $agent_hostname"
			cat output.log
			false
		fi
		if [ "$bearer_token" != "null" ]; then
			fdc_test_progress zabbix-frontend "Got API bearer token for $agent_hostname"
			break
		fi
		fdc_test_progress zabbix-frontend "Waiting for bearer token from API for $agent_hostname ($i)..."
		sleep 1
	done
	# NK: a value of 0 means timeout
	if [ "$i" = "0" ]; then
		fdc_test_fail zabbix-frontend "Timeout while getting API bearer token for $agent_hostname"
		cat output.log
		false
	fi
	echo "API RESULT GET TOKEN FOR AGENT VIA PROXY: $api_result => $bearer_token"



	fdc_test_progress zabbix-frontend "Getting hostgroup via API for $agent_hostname"
	api_result=$(
		zabbix_api_call "$bearer_token" \
			'{"jsonrpc":"2.0","method":"hostgroup.get","params":{"output":"extend","filter":{"name":["Virtual machines"]}},"id":1}'
	)
	hostgroupid=$(echo "$api_result" | jq ".result[0].groupid" | sed -e 's/"//g')

	if [ -z "$hostgroupid" ] || [ "$hostgroupid" = "null" ]; then
		fdc_test_fail zabbix-frontend "Failed to get hostgroup via API for $agent_hostname"
		cat output.log
		false
	fi

	fdc_test_pass zabbix-frontend "Got hostgroup from API for $agent_hostname"



	fdc_test_progress zabbix-frontend "Getting template via API for $agent_hostname"
	api_result=$(
		zabbix_api_call "$bearer_token" \
			'{"jsonrpc":"2.0","method":"template.get","params":{"output":"extend","filter":{"name":["Linux by Zabbix agent active"]}},"id":1}'
	)
	templateid=$(echo "$api_result" | jq ".result[0].templateid" | sed -e 's/"//g')

	if [ -z "$templateid" ] || [ "$templateid" = "null" ]; then
		fdc_test_fail zabbix-frontend "Failed to get template via API for $agent_hostname"
		cat output.log
		false
	fi

	fdc_test_pass zabbix-frontend "Got template from API for $agent_hostname"


	# shellcheck disable=SC2154
	fdc_test_progress zabbix-frontend "Getting proxy via API for $agent_hostnamey"
	api_result=$(
		zabbix_api_call "$bearer_token" \
			'{"jsonrpc":"2.0","method":"proxy.get","params":{"output":"extend","filter":{"host":"Zabbix proxy2"}},"id":1}'
	)
	proxyid=$(echo "$api_result" | jq ".result[0].proxyid" | sed -e 's/"//g')

	if [ -z "$proxyid" ] || [ "$proxyid" = "null" ]; then
		fdc_test_fail zabbix-frontend "Failed to get proxy via API for $agent_hostname"
		cat output.log
		false
	fi

	fdc_test_pass zabbix-frontend "Got proxy from API for $agent_hostname"


	fdc_test_progress zabbix-frontend "Setting up $agent_hostname"
	api_result=$(
		zabbix_api_call "$bearer_token" \
			'{"jsonrpc":"2.0","method":"host.create","params":{"host":"'"$agent_name"'","interfaces":[{"main":1,"type":1,"useip":0,"dns":"'"$agent_hostname"'","ip":"127.0.0.1","port":"10051"}],"proxy_hostid":"'"$proxyid"'","groups":[{"groupid":"'"$hostgroupid"'"}],"tls_accept":2,"tls_connect":2,"tls_psk_identity":"'"$agent_psk_identity"'","tls_psk":"'"$agent_psk_key"'","templates":{"templateid":"'"$templateid"'"}},"id":1}'
	)
	hostid=$(echo "$api_result" | jq ".result.hostids[0]" | sed -e 's/"//g')
	if [ -z "$hostid" ]; then
		fdc_test_fail zabbix-frontend "Failed to create new agent $agent_hostname"
		cat output.log
		false
	fi



	fdc_test_progress zabbix-frontend "Getting hostid via API for $agent_hostname"
	api_result=$(
		zabbix_api_call "$bearer_token" \
			'{"jsonrpc":"2.0","method":"host.get","params":{"filter":{"host":["'"$agent_name"'"]}},"id":1}'
	)
	hostid=$(echo "$api_result" | jq ".result[0].hostid" | sed -e 's/"//g')
	if [ -z "$hostid" ]; then
		fdc_test_fail zabbix-frontend "Failed to get hostid via API for $agent_hostname"
		cat output.log
		false
	fi

	fdc_test_progress zabbix-frontend "Waiting for agent item 'system.uptime' to update via API for $agent_hostname"
	last_value=""
	for i in {240..0}; do
		api_result=$(
			zabbix_api_call "$bearer_token" \
				'{"jsonrpc":"2.0","method":"item.get","params":{"output":"extend","hostids":"'"$hostid"'","search":{"key_":"system.uptime"}},"id":1}'
		)
		value=$(echo "$api_result" | jq ".result[0].lastvalue" | sed -e 's/"//g')

		# If last value is set and we have a new value, then break
		if [ -n "$last_value" ] && [ "$last_value" != "$value" ]; then
			fdc_test_progress zabbix-frontend "Got last agent item 'system.uptime' value $last_value with current value $value for $agent_hostname ... OK"
			break
		fi
		if [ -n "$value" ]; then
			last_value=$value
		fi
		fdc_test_progress zabbix-frontend "Waiting for agent item 'system.uptime' value to change for $agent_hostname ($i)..."
		sleep 1
	done
	# NK: a value of 0 means timeout
	if [ "$i" = "0" ]; then
		fdc_test_fail zabbix-frontend "Timeout while waiting for agent item 'system.uptime' for $agent_hostname"
		cat output.log
		false
	fi
	fdc_test_pass zabbix-frontend "API test of data from agent passed for $agent_hostname"
}



if [ "$ZABBIX_MODE" != "frontend" ]; then
	return
fi

# Wait for database to come up, so we don't fail getting our API login token
# NK: database_type_zabbix comes from init
# shellcheck disable=SC2154
if [ "$database_type_zabbix" = "postgresql" ]; then
	export PGPASSWORD="$POSTGRES_PASSWORD"

	while true; do
		fdc_test_progress zabbix-frontend "Zabbix waiting for PostgreSQL server '$POSTGRES_HOST'..."
		if pg_isready -d "$POSTGRES_DATABASE" -h "$POSTGRES_HOST" -U "$POSTGRES_USER"; then
			userlist=$(echo "SELECT * FROM users;" | psql -h "$POSTGRES_HOST" -U "$POSTGRES_USER" -w "$POSTGRES_DATABASE" -v ON_ERROR_STOP=ON 2>&1)
			echo "$userlist" 2>&1
			# Wait for database initialization to complete
			if echo "SELECT * FROM users;" | psql -h "$POSTGRES_HOST" -U "$POSTGRES_USER" -w "$POSTGRES_DATABASE" -v ON_ERROR_STOP=ON | grep testuser; then
				fdc_test_progress zabbix-frontend "PostgreSQL server is UP, continuing"
				break
			fi
		fi
		sleep 1
	done

	unset PGPASSWORD

elif [ "$database_type_zabbix" = "mysql" ]; then
	export MYSQL_PWD="$MYSQL_PASSWORD"

	while true; do
		fdc_test_progress zabbix-frontend "Zabbix waiting for MySQL server '$MYSQL_HOST'..."
		if mariadb-admin ping --host "$MYSQL_HOST" --user "$MYSQL_USER" --silent --connect-timeout=2; then
			# Wait for database initialization to complete
			if echo "SELECT * FROM users;" | mysql -h "$MYSQL_HOST" -u "$MYSQL_USER" "$MYSQL_DATABASE" | grep testuser; then
				fdc_test_progress zabbix-frontend "MySQL server is UP, continuing"
				break
			fi
		fi
		sleep 1
	done

	unset MYSQL_PWD
fi


# Test frontend access
test_zabbix_frontend 4

# Check if we should run the IPv6 tests
if [ -n "$(ip -6 route show default)" ]; then
	test_zabbix_frontend 6
fi

# Add additional agent via proxy and test result
test_zabbix_agent zabbix-test-agent-via-proxy "Zabbix test agent via proxy" "agenttest" "01234567890abcdef01234567890abcdef"
test_zabbix_agent zabbix-test-agent2-via-proxy "Zabbix test agent2 via proxy" "agent2test" "01234567890abcdef01234567890abcdef"

fdc_test_pass zabbix-frontend "Zabbix frontend tests passed"

