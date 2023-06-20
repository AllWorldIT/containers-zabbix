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


function test_zabbix_webservice() {
	ipv=$1

	fdc_test_start zabbix-webservice "Check Zabbix Web Service is responding using IPv$ipv..."
	if ! curl --verbose "--ipv$ipv" "http://localhost:10053/report" --output test.out; then
		fdc_test_fail zabbix-webservice "Failed to get test data from Zabbix Web Service using IPv$ipv"
		return 1
	fi

	echo '{"detail":"Method is not supported."}' > test.out.correct
	if ! diff test.out.correct test.out; then
		fdc_test_fail zabbix-webservice "Contents of output does not match what it should be using IPv$ipv"
		return 1
	fi

	fdc_test_pass zabbix-webservice "Zabbix Web Service is responding using IPv4"

	return 0
}



if [ "$ZABBIX_MODE" != "webservice" ]; then
	return
fi

test_zabbix_webservice 4

# Check if we should run the IPv6 tests
if [ -n "$(ip -6 route show default)" ]; then
	test_zabbix_webservice 6
fi

fdc_test_pass zabbix-webservice "Zabbix Web Service tests passed"
