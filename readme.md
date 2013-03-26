#Kiosk OS customization 
##Introduction
This document explains how to set-up server and clients for the rugged computer kiosk.
Configuration files are tracked with git on https://github.com/jean-marc/kiosk_os . Special hooks (note: they do not get copied when cloning a repository) need to be added to git to maintain file permission and ownership (is the file executable?...), see https://www.jottit.com/jg8h7/, the meta-data is saved in [/.gitmeta](/.gitmeta). 

Having the configuration under source control offers several advantages:

* get a log of all the modifications (similar to /etc/kiosk-notes) and the current version (actually the last commit), eg: 
```
git log
commit d728f3d4b881652e264cae6a8c62ae703f3305ec
Author: Jean-Marc Lefébure <lefebure.jeanmarc@gmail.com>
Date:   Sat Mar 23 20:36:46 2013 +0300

	some message...
``` 
* query the version remotely (through VPN) so we can populate our management database with up-to-date information
* update OS with ```git pull``` (note we could also do a blank file synchronization with rsync as long as we include /.git)
* we could create new branches to run tests and merge in the main branch if successful 

The server hosts the OS for the clients, so we only need to document the server OS to cover the whole system.

There are three extra /etc directories:

1. [/etc_original](/etc_original): common to client and server
2. [/etc_server](/etc_server): specific to server (daemon configuration,...) 
3. [/etc_client](/etc_client): specific to NFS-mounted clients

The system relies on the above to set up two different configurations decided at boot time (through kernel parameter 'client'):

1. client: no daemons (DHCP, Apache, ...),we  have ```/etc = /etc_original```.
2. client + server: daemons are started, we have ```/etc = /etc_server + /etc_original```, where '+' means a union file system mount (/etc_server is mounted on top of /etc_original). Note: the client-only OS is still available at /client (it gets NFS-exported as defined in [/etc_server/exports](/etc_server/exports))

The union mount takes place early in the boot process through a customized initrd.img created with the initramfs tool (see [/etc_original/initramfs-tools/scripts/init-bottom/server](/etc_original/initramfs-tools/scripts/init-bottom/server) and [/etc_original/initramfs-tools/hooks/server](/etc_original/initramfs-tools/hooks/server)).

##DHCP & TFTP
[/etc_server/dnsmasq.conf](/etc_server/dnsmasq.conf)

##Apache
There are two virtual hosts:

1. [/etc_server/apache2/sites-available/content.unicefuganda.org](/etc_server/apache2/sites-available/content.unicefuganda.org)
2. [/etc_server/apache2/sites-available/wikipedia.unicefuganda.org](/etc_server/apache2/sites-available/wikipedia.unicefuganda.org), a proxy for the kiwix server, listening on port 1080 (see [/etc_server/init/kiwix-serve.conf](/etc_server/init/kiwix-serve.conf)).

###Wikipedia
The offline wikipedia uses the [kiwix](http://kiwix.org/wiki/Main_Page) server, relevant files are:

* [/etc_server/init/kiwix-serve.conf](/etc_server/init/kiwix-serve.conf) upstart script to start the daemon, the server listens on port 1080 and is proxied by apache.
* /usr/local/bin/kiwix-serve the daemon
* /usr/local/bin/kiwix-index to generate the index
* /var/lib/kiwix/latest.zim a symbolic link to the latest archive, available at http://kiwix.org/wiki/Wikipedia_in_all_languages
* /var/lib/kiwix/index/	 contains a database used by the search engine, it is generated from the archive

###Content Portal

##NFS
[/etc_server/exports](/etc_server/exports)

##Proxy/Firewall
[/etc_server/network/interfaces](/etc_server/network/interfaces)

##HTTP filter
We use a combination of Squid and SquidGuard and some iptable rules to redirect HTTP traffic to Squid, there is currently a problem on the server machine as outgoing HTTP traffic is not caught by Squid (more work needed). 
* [/etc_server/squid3/squid.conf](/etc_server/squid3/squid.conf)
* [/etc_server/network/interfaces](/etc_server/network/interfaces)

##Webalizer
The report (eg. http://ssh.unicefuganda.org/webalizer/) is updated everyday based on the Squid log file (becauses it caches all HTTP requests).
* [/etc_server/webalizer/webalizer.conf](/etc_server/webalizer/webalizer.conf)

##VPN
As soon as a connection to the Internet is available, the kiosk connects to a VPN server (http://ssh.unicefuganda.org) and joins a virtual network using a unique certificate. The central server can easily connect to any on-line kiosk and run a SSH session (after public key exchange), kiosks can also bypass the server and talk to each other. 

* [/etc_server/openvpn/client.conf](/etc_server/openvpn/client.conf)
* /etc_server/openvpn/kiosk.crt
* /etc_server/openvpn/kiosk.csr
* /etc_server/openvpn/kiosk.key

An alternate scheme could use the same certificate on all kiosks, the server would have to identify individual machines based on their MAC address (/sys/class/net/eth0/address), that information already exists in our management database [http://inventory.unicefuganda.org/sparql?query=describe &lt;96344&gt;](http://inventory.unicefuganda.org/sparql?query=describe%20%3C96344%3E ):
```xml
<inv:Server rdf:ID="96344">
	<inv:time_stamp_v>2013-03-08T21:31:58</inv:time_stamp_v>
	<inv:time_stamp>1362767518</inv:time_stamp>
	<inv:partOf rdf:resource="#uniport-0"/>
	<inv:model rdf:resource="#D2"/>
	<inv:status>1</inv:status>
	<inv:_mac_>3018ac5fed</inv:_mac_>
</inv:Server>
```
The above snippet indicates that the server with MAC address 3018ac5fed is part of 'uniport-0'. The advantage of that scheme is that all kiosks would be running exactly the same OS (same hostname, VPN certificats,...) and would make deployment and update easier.


##Client control
Once the server is on, it can start all the clients on the local interface through wake-on-LAN, it will also shut them down before going down.
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
	*/10 * * * * /usr/local/bin/ts_45.sh; 
* [/usr/local/bin/udp_ping.sh](/usr/local/bin/udp_ping.sh] sends UDP messages to the monitoring server on expired MTN modems (see http://mbuya.unicefuganda.org/?p=642).
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

##Client file system

All the clients see the same file system with some slight variations when network-mounted:

* [/etc_original/fstab](/etc_original/fstab)
* [/etc_client/fstab](/etc_client/fstab)

A [tmpfs](http://en.wikipedia.org/wiki/Tmpfs) file system is union-mounted on top of the /home/user directory, this makes possible to set up default configurations eg. home pages for browser while allowing the user to make temporary modifications, all changes will be lost once the machine reboots. The reason for that design decision is to guarantee system stability, the downside is the inability to save any file except on external storage (USB stick, cellphone) and increased RAM used (the clients should use swap space unless there is no hard-drive).
Based on user s feedback we will create new regular accounts without the above limitations (that creates other problems if the same account is used on different machines at the same time). 
Note that unicef_admin is a regular account but is reserved for administration.


