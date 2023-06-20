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


if [ "$ZABBIX_MODE" != "webservice" ]; then
	return
fi


# Check we get a positive response back when using IPv4
if ! curl -H "User-Agent: Health Check" -ipv4 "http://localhost:10053/report" --output - | grep -q '{"detail":"Method is not supported."}'; then
	fdc_error "Health check failed for Zabbix Webservice using IPv4"
	false
fi


# Return if we don't have IPv6 support
if [ -z "$(ip -6 route show default)" ]; then
	return
fi


# Check we get a positive response back when using IPv6
if ! curl -H "User-Agent: Health Check" -ipv6 "http://localhost:10053/report" --output - | grep -q '{"detail":"Method is not supported."}'; then
	fdc_error "Health check failed for Zabbix Webservice using IPv6"
	false
fi

