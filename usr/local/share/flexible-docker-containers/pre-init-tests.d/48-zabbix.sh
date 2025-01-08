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


export ZABBIX_ADMIN_USERNAME=testuser
export ZABBIX_ADMIN_PASSWORD=testpassword


if [ "$ZABBIX_MODE" = "server" ]; then
#    echo "DebugLevel=3" >> /etc/zabbix/zabbix_server.conf.d/99-tests.conf
    echo "CacheUpdateFrequency=1" >> /etc/zabbix/zabbix_server.conf.d/99-tests.conf

elif [ "$ZABBIX_MODE" = "proxy" ]; then
#    echo "DebugLevel=3" >> /etc/zabbix/zabbix_proxy.conf.d/99-tests.conf
    true

elif [ "$ZABBIX_MODE" = "agent" ]; then
#    echo "DebugLevel=5" >> /etc/zabbix/zabbix_agentd.conf.d/99-tests.conf
    true

elif [ "$ZABBIX_MODE" = "frontend" ]; then
    cat << EOF > /etc/nginx/http.d/99-fdc-ci.conf
# The CI/CD runner is sometimes slow, so we allow some more time for requests
proxy_read_timeout 900s;
proxy_send_timeout 900s;
fastcgi_read_timeout 900s;
fastcgi_send_timeout 900s;
EOF
fi
