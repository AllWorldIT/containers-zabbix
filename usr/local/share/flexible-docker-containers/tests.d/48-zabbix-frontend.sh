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

	fdc_test_start zabbix-frontend:frontend "Testing frontend API using IPv$ipv"
	fdc_test_progress zabbix-frontend:frontend "Getting API bearer token using IPv$ipv"
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
			fdc_test_fail zabbix-frontend:frontend "Failed to get API bearer token using IPv$ipv"
			cat output.log
			false
		fi
		if [ "$bearer_token" != "null" ]; then
			fdc_test_progress zabbix-frontend:frontend "Got API bearer token using IPv$ipv"
			break
		fi
		fdc_test_progress zabbix-frontend:frontend "Waiting for bearer token from API using IPv$ipv ($i)..."
		sleep 1
	done
	# NK: a value of 0 means timeout
	if [ "$i" = "0" ]; then
		fdc_test_fail zabbix-frontend:frontend "Timeout while getting API bearer token"
		cat output.log
		false
	fi
	echo "API RESULT GET TOKEN: $api_result => $bearer_token"

	fdc_test_progress zabbix-frontend:frontend "Getting hostid via API using IPv$ipv"
	api_result=$(
		zabbix_api_call "$bearer_token" \
			'{"jsonrpc":"2.0","method":"host.get","params":{"filter":{"host":["'"$ZABBIX_SERVER_AGENT_NAME"'"]}},"id":1}' \
			"--ipv$ipv"
	)
	hostid=$(echo "$api_result" | jq ".result[0].hostid" | sed -e 's/"//g')
	if [ -z "$hostid" ]; then
		fdc_test_fail zabbix-frontend:frontend "Failed to get hostid via API using IPv$ipv"
		cat output.log
		false
	fi

	fdc_test_progress zabbix-frontend:frontend "Waiting for agent item 'system.uptime' to update via API using IPv$ipv"
	last_value="0"
	for i in {240..0}; do
		api_result=$(
			zabbix_api_call "$bearer_token" \
				'{"jsonrpc":"2.0","method":"item.get","params":{"output":"extend","hostids":"'"$hostid"'","search":{"key_":"system.uptime"}},"id":1}' \
				"--ipv$ipv"
		)

		value=$(echo "$api_result" | jq ".result[0].lastvalue" | sed -e 's/"//g')

		# If last value is set and we have a new value, then break
		if [ -n "$last_value" ] && [ "$last_value" != "$value" ]; then
			fdc_test_progress zabbix-frontend:frontend "Got last agent item 'system.uptime' value $last_value via IPv$ipv with current value $value ... OK"
			break
		fi
		if [ -n "$value" ]; then
			last_value=$value
		fi
		fdc_test_progress zabbix-frontend:frontend "Waiting for agent item 'system.uptime' value to change using IPv$ipv ($i)..."
		sleep 1
	done
	# NK: a value of 0 means timeout
	if [ "$i" = "0" ]; then
		fdc_test_fail zabbix-frontend:frontend "Timeout while waiting for agent item 'system.uptime'"
		cat output.log
		false
	fi
	fdc_test_pass zabbix-frontend:frontend "API test of data from agent passed using IPv$ipv"

}



function test_zabbix_proxy() {
	proxy_hostname=$1
	proxy_name=$2
	proxy_mode=$3
	proxy_psk_identity=$4
	proxy_psk_key=$5


	fdc_test_start zabbix-frontend:proxy "Creating $proxy_hostname using frontend API"
	fdc_test_progress zabbix-frontend:proxy "Getting API bearer token for $proxy_hostname"
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
			fdc_test_fail zabbix-frontend:proxy "Failed to get API bearer token for $proxy_hostname"
			cat output.log
			false
		fi
		if [ "$bearer_token" != "null" ]; then
			fdc_test_progress zabbix-frontend:proxy "Got API bearer token for $proxy_hostname"
			break
		fi
		fdc_test_progress zabbix-frontend:proxy "Waiting for bearer token from API for $proxy_hostname ($i)..."
		sleep 1
	done
	# NK: a value of 0 means timeout
	if [ "$i" = "0" ]; then
		fdc_test_fail zabbix-frontend:proxy "Timeout while getting API bearer token for $proxy_hostname"
		cat output.log
		false
	fi
	echo "API RESULT GET TOKEN FOR AGENT VIA PROXY: $api_result => $bearer_token"

	# Handle active configuration
	if [ "$proxy_mode" = "active" ]; then
		fdc_test_progress zabbix-frontend:agent "Proxy $proxy_hostname is ACTIVE"
		if [ -n "$proxy_psk_key" ] && [ -n "$proxy_psk_identity" ]; then
			fdc_test_progress zabbix-frontend:agent "Proxy $proxy_hostname is ENCRYPTED"
			address="127.0.0.1"
			allowed_access="$proxy_hostname"
			tls_connect=1
			tls_accept=2
			operating_mode=0
		else
			fdc_test_progress zabbix-frontend:agent "Proxy $proxy_hostname is NOT ENCRYPTED"
			address="127.0.0.1"
			allowed_access="$proxy_hostname"
			tls_connect=1
			tls_accept=1
			operating_mode=0
		fi
	# Handle passive configuration
	elif [ "$proxy_mode" = "passive" ]; then
		fdc_test_progress zabbix-frontend:agent "Proxy $proxy_hostname is PASSIVE"
		if [ -n "$proxy_psk_key" ] && [ -n "$proxy_psk_identity" ]; then
			fdc_test_progress zabbix-frontend:agent "Proxy $proxy_hostname is ENCRYPTED"
			address="$proxy_hostname"
			allowed_access=""
			tls_connect=2
			tls_accept=1
			operating_mode=1
		else
			fdc_test_progress zabbix-frontend:agent "Proxy $proxy_hostname is NOT ENCRYPTED"
			address="$proxy_hostname"
			allowed_access=""
			tls_accept=1
			tls_connect=1
			operating_mode=1
		fi
	else
		fdc_test_fail zabbix-frontend:proxy "Invalid proxy mode $proxy_mode for $proxy_hostname"
		false
	fi

	fdc_test_progress zabbix-frontend:proxy "Setting up proxy $proxy_hostname"
	api_result=$(
		zabbix_api_call "$bearer_token" \
			'{"jsonrpc":"2.0","method":"proxy.create","params":{"name":"'"$proxy_name"'","address":"'"$address"'","proxy_groupid":0,"allowed_addresses":"'"$allowed_access"'","operating_mode":'"$operating_mode"',"tls_accept":'"$tls_accept"',"tls_connect":'"$tls_connect"',"tls_psk_identity":"'"$proxy_psk_identity"'","tls_psk":"'"$proxy_psk_key"'"},"id":1}'
	)
	proxyid1=$(echo "$api_result" | jq ".result.proxyids[0]" | sed -e 's/"//g')
	if [ -z "$proxyid1" ]; then
		fdc_test_fail zabbix-frontend:proxy "Failed to create new proxy $proxy_hostname"
		cat output.log
		false
	fi


	fdc_test_progress zabbix-frontend:proxy "Getting proxyid via API for $proxy_hostname"
	api_result=$(
		zabbix_api_call "$bearer_token" \
			'{"jsonrpc":"2.0","method":"proxy.get","params":{"filter":{"name":"'"$proxy_name"'"}},"id":1}'
	)
	proxyid2=$(echo "$api_result" | jq ".result[0].proxyid" | sed -e 's/"//g')
	if [ -z "$proxyid2" ]; then
		fdc_test_fail zabbix-frontend:proxy "Failed to get proxyid via API for $proxy_hostname"
		cat output.log
		false
	fi


	fdc_test_progress zabbix-frontend:proxy "Waiting for proxy item 'last_access' to update via API for $proxy_hostname"
	last_value="0"
	for i in {240..0}; do
		api_result=$(
			zabbix_api_call "$bearer_token" \
				'{"jsonrpc":"2.0","method":"proxy.get","params":{"output":"extend","proxyids":'"$proxyid1"'},"id":1}'
		)
		value=$(echo "$api_result" | jq ".result[0].lastaccess" | sed -e 's/"//g')

		# If last value is set and we have a new value, then break
		if [ -n "$last_value" ] && [ "$last_value" != "$value" ]; then
			fdc_test_progress zabbix-frontend:proxy "Got last proxy item 'last_access' value $last_value with current value $value for $proxy_hostname ... OK"
			break
		fi
		if [ -n "$value" ]; then
			last_value=$value
		fi
		fdc_test_progress zabbix-frontend:proxy "Waiting for proxy item 'last_access' value to change for $proxy_hostname ($i)..."
		sleep 1
	done
	# NK: a value of 0 means timeout
	if [ "$i" = "0" ]; then
		fdc_test_fail zabbix-frontend:proxy "Timeout while waiting for proxy item 'last_access' for $proxy_hostname"
		cat output.log
		false
	fi
	fdc_test_pass zabbix-frontend:proxy "API test of data from agent passed for $proxy_hostname"
}



function test_zabbix_agent() {
	agent_hostname=$1
	agent_name=$2
	agent_mode=$3
	agent_psk_identity=$4
	agent_psk_key=$5
	agent_proxy=$6


	# Handle active configuration
	if [ "$agent_mode" = "active" ]; then
		fdc_test_progress zabbix-frontend:agent "Agent $agent_hostname is ACTIVE"
		if [ -n "$agent_psk_key" ] && [ -n "$agent_psk_identity" ]; then
			fdc_test_progress zabbix-frontend:agent "Agent $agent_hostname is ENCRYPTED"
			tls_connect=1
			tls_accept=2
			operating_mode=0
		else
			fdc_test_progress zabbix-frontend:agent "Agent $agent_hostname is NOT ENCRYPTED"
			tls_connect=1
			tls_accept=1
			operating_mode=0
		fi
		agent_template="Linux by Zabbix agent active"
	# Handle passive configuration
	elif [ "$agent_mode" = "passive" ]; then
		fdc_test_progress zabbix-frontend:agent "Agent $agent_hostname is PASSIVE"
		if [ -n "$agent_psk_key" ] && [ -n "$agent_psk_identity" ]; then
			fdc_test_progress zabbix-frontend:agent "Agent $agent_hostname is ENCRYPTED"
			tls_connect=2
			tls_accept=1
			operating_mode=1
		else
			fdc_test_progress zabbix-frontend:agent "Agent $agent_hostname is NOT ENCRYPTED"
			tls_accept=1
			tls_connect=1
			operating_mode=1
		fi
		agent_template="Linux by Zabbix agent"
	else
		fdc_test_fail zabbix-frontend:proxy "Invalid proxy mode $agent_mode for $agent_hostname"
		false
	fi



	fdc_test_start zabbix-frontend:agent "Creating $agent_hostname using frontend API"
	fdc_test_progress zabbix-frontend:agent "Getting API bearer token for $agent_hostname"
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
			fdc_test_fail zabbix-frontend:agent "Failed to get API bearer token for $agent_hostname"
			cat output.log
			false
		fi
		if [ "$bearer_token" != "null" ]; then
			fdc_test_progress zabbix-frontend:agent "Got API bearer token for $agent_hostname"
			break
		fi
		fdc_test_progress zabbix-frontend:agent "Waiting for bearer token from API for $agent_hostname ($i)..."
		sleep 1
	done
	# NK: a value of 0 means timeout
	if [ "$i" = "0" ]; then
		fdc_test_fail zabbix-frontend:agent "Timeout while getting API bearer token for $agent_hostname"
		cat output.log
		false
	fi
	echo "API RESULT GET TOKEN FOR AGENT VIA PROXY: $api_result => $bearer_token"



	fdc_test_progress zabbix-frontend:agent "Getting hostgroup via API for $agent_hostname"
	api_result=$(
		zabbix_api_call "$bearer_token" \
			'{"jsonrpc":"2.0","method":"hostgroup.get","params":{"output":"extend","filter":{"name":["Virtual machines"]}},"id":1}'
	)
	hostgroupid=$(echo "$api_result" | jq ".result[0].groupid" | sed -e 's/"//g')

	if [ -z "$hostgroupid" ] || [ "$hostgroupid" = "null" ]; then
		fdc_test_fail zabbix-frontend:agent "Failed to get hostgroup via API for $agent_hostname"
		cat output.log
		false
	fi

	fdc_test_pass zabbix-frontend:agent "Got hostgroup from API for $agent_hostname"



	fdc_test_progress zabbix-frontend:agent "Getting template via API for $agent_hostname"
	api_result=$(
		zabbix_api_call "$bearer_token" \
			'{"jsonrpc":"2.0","method":"template.get","params":{"output":"extend","filter":{"name":["'"$agent_template"'"]}},"id":1}'
	)
	templateid=$(echo "$api_result" | jq ".result[0].templateid" | sed -e 's/"//g')

	if [ -z "$templateid" ] || [ "$templateid" = "null" ]; then
		fdc_test_fail zabbix-frontend:agent "Failed to get template via API for $agent_hostname"
		cat output.log
		false
	fi

	fdc_test_pass zabbix-frontend:agent "Got template from API for $agent_hostname"

	proxy_monitoring=""
	if [ -n "$agent_proxy" ]; then
		# shellcheck disable=SC2154
		fdc_test_progress zabbix-frontend:agent "Getting proxy via API for $agent_hostnamey"
		api_result=$(
			zabbix_api_call "$bearer_token" \
				'{"jsonrpc":"2.0","method":"proxy.get","params":{"output":"extend","filter":{"name":"'"$agent_proxy"'"}},"id":1}'
		)
		proxyid=$(echo "$api_result" | jq ".result[0].proxyid" | sed -e 's/"//g')

		if [ -z "$proxyid" ] || [ "$proxyid" = "null" ]; then
			fdc_test_fail zabbix-frontend:agent "Failed to get proxy via API for $agent_hostname"
			cat output.log
			false
		fi
		# 0 - server, 1 - proxy, 2 - proxy group
		proxy_monitoring=',"monitored_by":1,"proxyid":'"$proxyid"
		fdc_test_pass zabbix-frontend:agent "Got proxy from API for $agent_hostname"
	fi


	fdc_test_progress zabbix-frontend:agent "Setting up $agent_hostname"
	api_result=$(
		zabbix_api_call "$bearer_token" \
			'{"jsonrpc":"2.0","method":"host.create","params":{"host":"'"$agent_name"'","interfaces":[{"main":1,"type":1,"useip":0,"dns":"'"$agent_hostname"'","ip":"127.0.0.1","port":"10050"}]'"$proxy_monitoring"',"groups":[{"groupid":"'"$hostgroupid"'"}],"tls_accept":'"$tls_accept"',"tls_connect":'"$tls_connect"',"tls_psk_identity":"'"$agent_psk_identity"'","tls_psk":"'"$agent_psk_key"'","templates":{"templateid":"'"$templateid"'"}},"id":1}'
	)
	hostid=$(echo "$api_result" | jq ".result.hostids[0]" | sed -e 's/"//g')
	if [ -z "$hostid" ]; then
		fdc_test_fail zabbix-frontend:agent "Failed to create new agent $agent_hostname"
		cat output.log
		false
	fi



	fdc_test_progress zabbix-frontend:agent "Getting hostid via API for $agent_hostname"
	api_result=$(
		zabbix_api_call "$bearer_token" \
			'{"jsonrpc":"2.0","method":"host.get","params":{"filter":{"host":["'"$agent_name"'"]}},"id":1}'
	)
	hostid=$(echo "$api_result" | jq ".result[0].hostid" | sed -e 's/"//g')
	if [ -z "$hostid" ]; then
		fdc_test_fail zabbix-frontend:agent "Failed to get hostid via API for $agent_hostname"
		cat output.log
		false
	fi

	fdc_test_progress zabbix-frontend:agent "Waiting for agent item 'system.uptime' to update via API for $agent_hostname"
	last_value=""
	for i in {240..0}; do
		api_result=$(
			zabbix_api_call "$bearer_token" \
				'{"jsonrpc":"2.0","method":"item.get","params":{"output":"extend","hostids":"'"$hostid"'","search":{"key_":"system.uptime"}},"id":1}'
		)
		value=$(echo "$api_result" | jq ".result[0].lastvalue" | sed -e 's/"//g')

		# If last value is set and we have a new value, then break
		if [ -n "$last_value" ] && [ "$last_value" != "$value" ]; then
			fdc_test_progress zabbix-frontend:agent "Got last agent item 'system.uptime' value $last_value with current value $value for $agent_hostname ... OK"
			break
		fi
		if [ -n "$value" ]; then
			last_value=$value
		fi
		fdc_test_progress zabbix-frontend:agent "Waiting for agent item 'system.uptime' value to change for $agent_hostname ($i)..."
		sleep 1
	done
	# NK: a value of 0 means timeout
	if [ "$i" = "0" ]; then
		fdc_test_fail zabbix-frontend:agent "Timeout while waiting for agent item 'system.uptime' for $agent_hostname"
		cat output.log
		false
	fi
	fdc_test_pass zabbix-frontend:agent "API test of data from agent passed for $agent_hostname"
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
			if echo "SELECT * FROM users;" | psql -h "$POSTGRES_HOST" -U "$POSTGRES_USER" -w "$POSTGRES_DATABASE" -v ON_ERROR_STOP=ON | grep -q testuser; then
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
		if mariadb-admin ping --skip-ssl --host "$MYSQL_HOST" --user "$MYSQL_USER" --connect-timeout=2; then
			# Wait for database initialization to complete
			if echo "SELECT * FROM users;" | mariadb --skip-ssl --host "$MYSQL_HOST" --user "$MYSQL_USER" "$MYSQL_DATABASE" | grep testuser; then
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


#
# PROXIES
#

# a - represents active
# p - represents passive
# e - represents encrypted
#  <proxy hostname> <proxy name> <proxy mode> <proxy PSK identity> <proxy PSK key>

# ACTIVE PROXY

# - Not Encrypted
test_zabbix_proxy zabbix-proxy1a "Zabbix proxy1a" active "" ""
# - Encrypted
test_zabbix_proxy zabbix-proxy2ae "Zabbix proxy2ae" active "zabbixproxy2ae" "01234567890abcdef01234567890abcdef"

# PASSIVE PROXY

# - Not Encrypted
test_zabbix_proxy zabbix-proxy3p "Zabbix proxy3p" passive "" ""
# - Encrypted
test_zabbix_proxy zabbix-proxy4pe "Zabbix proxy4pe" passive "zabbixproxy4pe" "01234567890abcdef01234567890abcdef"


#
# AGENTS
#

# a - represents active
# p - represents passive
# e - represents encrypted
#  <agent hostname> <agent name> <agent mode> <agent PSK identity> <agent PSK key> <proxy name>


# ACTIVE PROXY

# Active Proxy - Not Encrypted
# - Active Agent - Not Encrypted
test_zabbix_agent zabbix-test-agent-via-proxy1a-a "Test agent proxy1a-a" active "" "" "Zabbix proxy1a"
test_zabbix_agent zabbix-test-agent2-via-proxy1a-a "Test agent2 proxy1a-a" active "" "" "Zabbix proxy1a"
# - Active Agent - Encrypted
test_zabbix_agent zabbix-test-agent-via-proxy1a-ae "Test agent proxy1a-ae" active "agentproxy1a-ae" "01234567890abcdef01234567890abcdef" "Zabbix proxy1a"
test_zabbix_agent zabbix-test-agent2-via-proxy1a-ae "Test agent2 proxy1a-ae" active "agent2proxy1a-ae" "01234567890abcdef01234567890abcdef" "Zabbix proxy1a"
# - Passive Agent - Not Encrypted
test_zabbix_agent zabbix-test-agent-via-proxy1a-p "Test agent proxy1a-p" passive "" "" "Zabbix proxy1a"
test_zabbix_agent zabbix-test-agent2-via-proxy1a-p "Test agent2 proxy1a-p" passive "" "" "Zabbix proxy1a"
# - Passive Agent - Encrypted
test_zabbix_agent zabbix-test-agent-via-proxy1a-pe "Test agent proxy1a-pe" passive "agentproxy1a-pe" "01234567890abcdef01234567890abcdef" "Zabbix proxy1a"
test_zabbix_agent zabbix-test-agent2-via-proxy1a-pe "Test agent2 proxy1a-pe" passive "agent2proxy1a-pe" "01234567890abcdef01234567890abcdef" "Zabbix proxy1a"

# Active Proxy - Encrypted
# - Active Agent - Not Encrypted
test_zabbix_agent zabbix-test-agent-via-proxy2ae-a "Test agent proxy2ae-a" active "" "" "Zabbix proxy2ae"
test_zabbix_agent zabbix-test-agent2-via-proxy2ae-a "Test agent2 proxy2ae-a" active "" "" "Zabbix proxy2ae"
# - Active Agent - Encrypted
test_zabbix_agent zabbix-test-agent-via-proxy2ae-ae "Test agent proxy2ae-ae" active "agentproxy2ae-ae" "01234567890abcdef01234567890abcdef" "Zabbix proxy2ae"
test_zabbix_agent zabbix-test-agent2-via-proxy2ae-ae "Test agent2 proxy2ae-ae" active "agent2proxy2ae-ae" "01234567890abcdef01234567890abcdef" "Zabbix proxy2ae"
# - Passive Agent - Not Encrypted
test_zabbix_agent zabbix-test-agent-via-proxy2ae-p "Test agent proxy2ae-p" passive "" "" "Zabbix proxy2ae"
test_zabbix_agent zabbix-test-agent2-via-proxy2ae-p "Test agent2 proxy2ae-p" passive "" "" "Zabbix proxy2ae"
# - Passive Agent - Encrypted
test_zabbix_agent zabbix-test-agent-via-proxy2ae-pe "Test agent proxy2ae-pe" passive "agentproxy2ae-pe" "01234567890abcdef01234567890abcdef" "Zabbix proxy2ae"
test_zabbix_agent zabbix-test-agent2-via-proxy2ae-pe "Test agent2 proxy2ae-pe" passive "agent2proxy2ae-pe" "01234567890abcdef01234567890abcdef" "Zabbix proxy2ae"

# # PASSIVE PROXY

# Passive Proxy - Not Encrypted
# - Active Agent - Not Encrypted
test_zabbix_agent zabbix-test-agent-via-proxy3p-a "Test agent proxy3p-a" active "" "" "Zabbix proxy3p"
test_zabbix_agent zabbix-test-agent2-via-proxy3p-a "Test agent2 proxy3p-a" active "" "" "Zabbix proxy3p"
# - Active Agent - Encrypted
test_zabbix_agent zabbix-test-agent-via-proxy3p-ae "Test agent proxy3p-ae" active "agentproxy3p-ae" "01234567890abcdef01234567890abcdef" "Zabbix proxy3p"
test_zabbix_agent zabbix-test-agent2-via-proxy3p-ae "Test agent2 proxy3p-ae" active "agent2proxy3p-ae" "01234567890abcdef01234567890abcdef" "Zabbix proxy3p"
# - Passive Agent - Not Encrypted
test_zabbix_agent zabbix-test-agent-via-proxy3p-p "Test agent proxy3p-p" passive "" "" "Zabbix proxy3p"
test_zabbix_agent zabbix-test-agent2-via-proxy3p-p "Test agent2 proxy3p-p" passive "" "" "Zabbix proxy3p"
# - Passive Agent - Encrypted
test_zabbix_agent zabbix-test-agent-via-proxy3p-pe "Test agent proxy3p-pe" passive "agentproxy3p-pe" "01234567890abcdef01234567890abcdef" "Zabbix proxy3p"
test_zabbix_agent zabbix-test-agent2-via-proxy3p-pe "Test agent2 proxy3p-pe" passive "agent2proxy3p-pe" "01234567890abcdef01234567890abcdef" "Zabbix proxy3p"

# Passive Proxy - Encrypted
# - Active Agent - Not Encrypted
test_zabbix_agent zabbix-test-agent-via-proxy4pe-a "Test agent proxy4pe-a" active "" "" "Zabbix proxy4pe"
test_zabbix_agent zabbix-test-agent2-via-proxy4pe-a "Test agent2 proxy4pe-a" active "" "" "Zabbix proxy4pe"
# - Active Agent - Encrypted
test_zabbix_agent zabbix-test-agent-via-proxy4pe-ae "Test agent proxy4pe-ae" active "agentproxy4pe-ae" "01234567890abcdef01234567890abcdef" "Zabbix proxy4pe"
test_zabbix_agent zabbix-test-agent2-via-proxy4pe-ae "Test agent2 proxy4pe-ae" active "agent2proxy4pe-ae" "01234567890abcdef01234567890abcdef" "Zabbix proxy4pe"
# - Passive Agent - Not Encrypted
test_zabbix_agent zabbix-test-agent-via-proxy4pe-p "Test agent proxy4pe-p" passive "" "" "Zabbix proxy4pe"
test_zabbix_agent zabbix-test-agent2-via-proxy4pe-p "Test agent2 proxy4pe-p" passive "" "" "Zabbix proxy4pe"
# - Passive Agent - Encrypted
test_zabbix_agent zabbix-test-agent-via-proxy4pe-pe "Test agent proxy4pe-pe" passive "agentproxy4pe-pe" "01234567890abcdef01234567890abcdef" "Zabbix proxy4pe"
test_zabbix_agent zabbix-test-agent2-via-proxy4pe-pe "Test agent2 proxy4pe-pe" passive "agent2proxy4pe-pe" "01234567890abcdef01234567890abcdef" "Zabbix proxy4pe"



fdc_test_pass zabbix-frontend "Zabbix frontend tests passed"
