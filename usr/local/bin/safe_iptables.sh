#!/bin/sh
# will have to be allowed to run without password in sudoer file
iptables -L TRAFFIC_ACCT -v -x
