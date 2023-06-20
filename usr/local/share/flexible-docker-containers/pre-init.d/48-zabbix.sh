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


if [ "$ZABBIX_MODE" = "frontend" ]; then
	fdc_info "Enabling Zabbix Frontend NGINX"
	if [ -e /usr/local/share/flexible-docker-containers/healthcheck.d/44-nginx.sh.disabled ]; then
		mv "/usr/local/share/flexible-docker-containers/healthcheck.d/44-nginx.sh"{.disabled,}
	fi
	if [ -e /usr/local/share/flexible-docker-containers/init.d/44-nginx.sh.disabled ]; then
		mv "/usr/local/share/flexible-docker-containers/init.d/44-nginx.sh"{.disabled,}
	fi
	if [ -e /usr/local/share/flexible-docker-containers/init.d/46-nginx-php.sh.disabled ]; then
		mv "/usr/local/share/flexible-docker-containers/init.d/46-nginx-php.sh"{.disabled,}
	fi
fi
