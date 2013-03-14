#Kiosk OS customization 
##Introduction
This document explains how to set-up server and clients for the rugged computer kiosk.
Configuration files are tracked with git on https://github.com/jean-marc/kiosk_os . https://www.jottit.com/jg8h7/ documents how to maintain file permissions and ownership. 

The server hosts the OS for the clients, so we only need to document the server OS to cover the whole system. 
##DHCP & TFTP
[/etc_server/dnsmasq.conf](/etc_server/dnsmasq.conf)
##NFS
[/etc_server/exports](/etc_server/exports)
##Proxy/Firewall
[/etc_server/network/interfaces](/etc_server/network/interfaces)
##HTTP filter
We use SquidGuard
[/etc_server/squid3/squid.conf](/etc_server/squid3/squid.conf)
##Client control
Once the server is on it can start all the clients on the local interface through wake-on-LAN, it will also shut them down before going down.
Wake-on-LAN is a low-level protocol, a machine will turn on if it receives a magic packet on an interface (it must be enable in the BIOS and there are other conditions).
The server uses information stored by the DHCP server in /var/lib/misc/dnsmasq.leases to send magic packets to all the machines that have ever been given a lease (sending UDP packets takes almost no time so it is not such a waste), that means that a new client will have to be started manually.
Shutting down a client is simpler, a simple SSH session is run to invoke poweroff.

The relevant files are:
* /var/lib/misc/dnsmasq.leases that file is created by dnsmasq
* [/etc_server/init.d/manage_client](/etc_server/init.d/manage_client) System-V type daemon, it reads from the DHCP lease list to turn on clients (or when invoked as ```/etc/init.d/manage_client start```), it reads from the ARP list to shut them down (or when invoked as ```/etc/init.d/manage_client stop```).


##Power management

The main task is to log information from the charge controller and trigger a shutdown when the voltage is nearing a set threshold.
We currently support two models: Morningstar TS-45 and Phocos C-40

###TS_45
The TS 45 is a solar charger, it means that it does not keep track of the current going through the load, just the voltage. 
need to install libmodbus, there does not seem to be .deb package so you have to build it, get the archive from http://libmodbus.org/download/, unpack, run 
```
	./configure 
	make
	sudo make install
	sudo ldconfig
```
build the client (https://github.com/jean-marc/ts_mppt)

###Phocos
The charge controller uses a TTL interface and requires a TTL-to-serial or TTL-to-USB adapter (eg. [here](http://compare.ebay.com/like/251117477526?var=lv&ltyp=AllFixedPriceItemTypes&var=sbar&_lwgsi=y&cbt=y)). The client is a python script (https://github.com/jean-marc/ts_mppt/blob/master/phocos.py)

A few files are needed to run the power management task:
* [/etc_server/udev/rules.d/99-persistent-usb_serial_2.rules](/etc_server/udev/rules.d/99-persistent-usb_serial_2.rules)
	it will create a symbolic link to the USB device eg:
	```
	$ ls -l /dev/ts_45 
	lrwxrwxrwx 1 root root 7 2013-03-08 16:51 /dev/ts_45 -> ttyUSB0
	```
* [/usr/local/bin/ts_45.sh](/usr/local/bin/ts_45.sh)
* [/usr/local/bin/ts_45.awk](/usr/local/bin/ts_45.awk)
* /var/log/ts_45.log
	invokes the program defined in $CHARGE_CONTROLLER and filter it with the awk script and writes to the log file. It will trigger a shutdown if the voltage is below $LOW_VOLTAGE_DISCONNECT_12 or $LOW_VOLTAGE_DISCONNECT_24 (the actual variable is picked depending on current voltage)
* [/etc_server/profile.d/kiosk_parameters.sh](/etc_server/profile.d/kiosk_parameters.sh)
	this where global environment variables are defined including $CHARGE_CONTROLLER
* crontab
	the above script is run every 10 minutes: (the interval could be made longer)
	*/10 * * * * /usr/local/bin/ts_45.sh; /usr/local/bin/udp_ping.sh
Note: the script is also invoked by the remote monitoring task (see remote monitoring) and care must be taken they do not run a the same time.
Note: names should be changed from 'ts_45' to something more generic

##Traffic accounting

Part of the monitoring task is to measure how much data is being used for Internet access, a few files are necessary:
* [/etc_server/init/traffic_accounting.conf](/etc_server/init/traffic_accounting.conf)
	set up a few rules to capture traffic going out, management traffic (to and from 196.0.26.0/24) is separated from the rest. An environment variable $NET defines the interface used to access the Internet (eg. ppp0 for USB modem, eth0 for Ethernet) (see http://mbuya.unicefuganda.org/?p=703)
* [/usr/local/bin/safe_iptables.sh](/usr/local/bin/safe_iptables.sh)
	script to read the counter
* [/etc_server/sudoers.d/safe_iptables](/etc_server/sudoers.d/safe_iptables)
	allows to run the above script without entering password (for remote monitoring), it will be invoked as ```sudo safe_iptables.sh```
Counters get reset when machine is turned off.
