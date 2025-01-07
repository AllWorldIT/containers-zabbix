#!/bin/bash
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


if [ "$ZABBIX_MODE" != "proxy" ]; then
	return
fi


# Check IPv4 port 10051 is reachable
fdc_test_start zabbix-proxy "Testing IPv4 port 10051 is open"
for i in {120..0}; do
	if nc 127.0.0.1 10051 -w 1; then
		fdc_test_pass zabbix-proxy "IPv4 Port 10051 is open"
		break
	fi
	sleep 1
done
if [ "$i" = "0" ]; then
	fdc_test_fail zabbix-proxy "IPv4 Port 10051 is not open"
	false
fi

# Check if we should run the IPv6 tests
if [ -n "$(ip -6 route show default)" ]; then
	# Check IPv6 port 10051 is reachable
	fdc_test_start zabbix-proxy "Testing IPv6 port 10051 is open"
	for i in {120..0}; do
		if nc ::1 10051 -w 1; then
			fdc_test_pass zabbix-proxy "IPv6 Port 10051 is open"
			break
		fi
		sleep 1
	done
	if [ "$i" = "0" ]; then
		fdc_test_fail zabbix-proxy "IPv6 Port 10051 is not open"
		false
	fi
else
	fdc_test_alert zabbix-proxy "Not running IPv6 tests due to no IPv6 default route"
fi

fdc_test_pass zabbix-proxy "Zabbix server tests passed"
