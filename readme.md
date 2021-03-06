#Kiosk OS customization 
##Introduction
This document explains how to set-up server and clients for the rugged computer kiosk.
Configuration files are tracked with git on monitor.unicefuganda.org:/srv/git/kiosk_os.git (requires SSH credentials) and https://github.com/jean-marc/kiosk_os.git (public). 
Special hooks (note: they do not get copied when cloning a repository) need to be added to git to maintain file permission and ownership (is the file executable?...), see https://www.jottit.com/jg8h7/, the meta-data is saved in [/.gitmeta](/.gitmeta). 

Having the configuration under source control offers several advantages:

* get a log of all the modifications (similar to /etc/kiosk-notes) and the current version (actually the last commit), eg: 

```
git log
commit d728f3d4b881652e264cae6a8c62ae703f3305ec
Author: Jean-Marc Lefébure <lefebure.jeanmarc@gmail.com>
Date:   Sat Mar 23 20:36:46 2013 +0300

	some message...
``` 

* query the version remotely (through VPN) so we could populate our management database with up-to-date information
* update OS with ```git pull```, if the file under source control is the configuration of application 'x', that application will still have to be installed the usual way (apt-get install 'x'). Note that file synchronization with rsync is also an option but there are a few caveats:
	* it needs to be carefully set (using '--exclude' statements) so we do not override log files and other site specific files
	* it should not be done on a live system (there should be another installed OS used for synchronization purpose or PXE network boot)
	* even after excluding subsets, it still uses a lot of bandwidth because the entire filesystem needs to be visited to detect file modification 
* new branches can be created to run tests and merged in the main branch if successful 

The server hosts the OS for the clients, so we only need to document the server OS to cover the whole system.

There are three extra /etc directories:

1. [/etc_original](/etc_original): common to client and server
2. [/etc_server](/etc_server): specific to server (daemon configuration,...) 
3. [/etc_doorway](/etc_doorway): specific to digital doorway (ltsp,...) 
4. [/etc_client](/etc_client): specific to NFS-mounted clients

The system relies on the above to set up three different configurations decided at boot time (through kernel parameter 'client', 'server' and 'doorway'):

1. client: no daemons (DHCP, Apache, ...),we  have ```/etc = /etc_original```.
2. client + server: daemons are started, we have ```/etc = /etc_server + /etc_original```, where '+' means a union file system mount (/etc_server is mounted on top of /etc_original). Note: the client-only OS is still available at /client (it gets NFS-exported as defined in [/etc_server/exports](/etc_server/exports))
3. client + server + doorway: same as above + LTSP daemons are started, we have ```/etc = /etc_doorway + /etc_server + /etc_original```, where '+' means a union file system mount.

The union mount takes place early in the boot process through a customized initrd.img created with the initramfs tool (see [/etc_original/initramfs-tools/scripts/init-bottom/server](/etc_original/initramfs-tools/scripts/init-bottom/server) and [/etc_original/initramfs-tools/hooks/server](/etc_original/initramfs-tools/hooks/server)). This means that the OS is only usable as client-only when running in a chroot jail (unless it is possible to manually do a aufs mount in the root).

Note that this file organization has consequences on apparmor because applications will attempt to access files at non-standard locations eg. /etc_server/passwd instead of /etc/passwd , fortunately this can be fixed by defining aliases:
```
alias /etc/ -> /etc_server/,
alias /etc/ -> /etc_doorway/,
```
in [/etc_server/apparmor.d/tunables/alias](/etc_server/apparmor.d/tunables/alias) and [/etc_doorway/apparmor.d/tunables/alias](/etc_doorway/apparmor.d/tunables/alias) .

##DHCP & TFTP
Dnsmasq is used as a DNS-, DHCP- and TFTP-server to send initrd.img for network boot.

* [/etc_server/dnsmasq.conf](/etc_server/dnsmasq.conf)
* [/var/ftpd/pxelinux.cfg/default](/var/ftpd/pxelinux.cfg/default)

Note that in the 'doorway' configuration, the LTSP package comes with dhcpd and hpa-tftpd, dnsmasq in only used for DNS.

##Web Content
The web server hosts 2 sites: http://content.unicefuganda.org and http://wikipedia.unicefuganda.org, first install apache and some dependencies:

```
apt-get install apache2 libapache2-mod-php5 php5-mysql mysql-server
```
###Content Portal
1. copy the wordpress site from a local mirror (~ 160G worth of data, will take a long time):

```
rsync -av local-mirror:/var/www/content.unicefuganda.org /var/www
```
2. copy the virtual site definition [/etc_server/apache2/sites-available/content.unicefuganda.org](/etc_server/apache2/sites-available/content.unicefuganda.org), enable the site and one module

```
wget http://raw.github.com/jean-marc/kiosk_os/master/etc_server/apache2/sites-available/content.unicefuganda.org /etc/apache2/sites-available/
a2ensite content.unicefuganda.org
a2enmod rewrite
```
3. create the database 'unicef' and a user 'unicef_content' to access it, in mysql client:

```
mysql -u root -p
create database unicef;
grant all privileges on unicef.* to 'unicef_content'@'localhost' identified by 'password';
```
where 'password' must match the credentials in /var/www/content.unicefuganda.org/wp-config.php, the site should be up and running.

Special setting for read-only file system

If the database is installed on a read-only file system (eg. drum, maybe Digital Doorway in the future), the database needs to be authorized by apparmor:
```
mount -o remount,rw /ro
ln -s /ro/etc/apparmor.d/usr.sbin.mysqld /ro/etc/apparmor.d/disable
apparmor_parser -R /ro/etc/apparmor.d/usr.sbin.mysqld
```
Depending on the backend, the database might need write-access to the file system, this will use the tmpfs file system and use extra RAM, to make sure the database does not write to file 'MyISAM' engine can be used or - on recent versions of mysql (5.6) - 'InnoDB' with '--innodb-read-only' option (http://dev.mysql.com/doc/refman/5.6/en/innodb-parameters.html#sysvar_innodb_read_only).

###Wikipedia
The offline wikipedia uses the [kiwix](http://kiwix.org/wiki/Main_Page) server, relevant files are:

1. copy the daemon kiwix-serve (and kiwix-index if needed) from local mirror
2. copy the upstart job [/etc_server/init/kiwix-serve.conf](/etc_server/init/kiwix-serve.conf)
	```
	wget http://raw.github.com/jean-marc/kiosk_os/master/etc_server/init /etc_server/init/
	```
3. copy the virtual site definition [/etc_server/apache2/sites-available/wikipedia.unicefuganda.org](/etc_server/apache2/sites-available/wikipedia.unicefuganda.org), a proxy for the kiwix server, listening on port 1080

```
wget http://raw.github.com/jean-marc/kiosk_os/master/etc_server/apache2/sites-available/wikipedia.unicefuganda.org /etc/apache2/sites-available/
a2ensite wikipedia.unicefuganda.org
a2enmod proxy-http
```
4. get the zim archive from local mirror (also available at http://kiwix.org/wiki/Wikipedia_in_all_languages) and the index (it can also be generated with kiwix-index)

```
rsync -av local-mirror:/var/lib/kiwix /var/lib
```

##NFS
The server exports a large subset of its file system on the local network (192.168.4.0/24) through NFS.
[/etc_server/exports](/etc_server/exports)
Note that booting clients is pretty taxing on the NFS server (for some reason booting an NL2 client:~30s is faster than NL3:~120s, there might be some problem on the client side) and can cause failures if booting more than one client at a time, the script [/etc_server/init.d/manage_client](/etc_server/init.d/manage_client) has been modified to stagger the boots and minimize the load (it might be good to delete /var/lib/misc/dsmasq.leases on a new set).

##Proxy/Firewall

[/etc_server/network/interfaces](/etc_server/network/interfaces)

##Internet Access
The network manager has been removed because it interfers with the /etc_server/network/interfaces
###PPP
Internet is mainly accessed with GPRS modems using PPP protocol. Relevant files are:

* [/etc_server/chatscripts/orange](/etc_server/chatscripts/orange)
* [/etc_server/ppp/peers/orange](/etc_server/ppp/peers/orange)
* [/etc_server/network/interfaces](/etc_server/network/interfaces)
* [/etc_server/cron.d/modem_reconnect](/etc_server/ncron.d/modem_reconnect) a cron job that will attempt a reconnection if interface ppp0 is down.

The interface is brought up by /sbin/ifup, unfortunately it causes a disconnection as soon as the link is established (see bug https://bugs.launchpad.net/ubuntu/+source/ppp/+bug/776193), there seems to be no other fix than patching the executable:
```
sed 's/updetach/        /g' /sbin/ifup >/sbin/ifup_patch
ln -s /sbin/ifup_patch ./ifup
```
The original executable can be recovered by removing the symbolic link.
###Ethernet
A free interface can be used to access the internet (eg. eth1 in /etc_server/network/interfaces), if none is available a USB-to-Ethernet can be used or a new address can be added to the existing interface:
```
dhclient eth0
```
Note that in the latter case there is only one physical network with 2 DHCP servers, the clients might get their lease from the wrong server.
There should be a way to set that up in the interfaces file.

###Wireless

The wireless can also be used see /etc_original/network/interfaces for an example. 

##HTTP filter
We use a combination of caching-proxy server Squid (www.squid-cache.org) and filter SquidGuard (www.squidguard.org) and some iptable rules to redirect HTTP traffic to Squid. 
SquidGuard kicks in right before the page is about to be fetched, URL and IP address are checked against information in /var/lib/squidguard/db and if deemed inappropriate URL is rewritten to http://192.168.4.1/blocked. The database is built from regularly updated blacklist available on-line see http://www.squidguard.org/blacklists.html.

* [/etc_server/squid3/squid.conf](/etc_server/squid3/squid.conf) note the line ```acl lan src all``` to allow the server to access squid because of no prior knowledge of the IP address given through DHCP by the Internet provider. 
* [/etc_server/squid/squidGuard.conf](/etc_server/squid/squidGuard.conf), 
* /usr/local/squid/var/cache/squid the squid cache, note that content.unicefuganda.org and wikipedia.unicefuganda.org are excluded from the cache because thoses sites are hosted locally (it should always cause a 'TCP_MISS' in /var/log/squid3/access.log)
* [/etc_server/network/interfaces](/etc_server/network/interfaces), note the use of '--uid-owner' to filter the HTTP traffic leaving the server
* [/var/www/blocked](/var/www/blocked) the page returned when a site is blocked.

Note that HTTPS traffic is not filtered.

##Webalizer
The report (eg. http://monitor.unicefuganda.org/webalizer/) is updated everyday based on the Squid log file (becauses it filters all HTTP requests), it is available locally at http://server/management/webalizer and on the Internet at for instance http://monitor.unicefuganda.org/monitor/webalizer/kiosk-46. Note that the client IP addresses are on the 192.168.4.0/24 network, the server is 192.168.4.1 or whichever private IP address given by the ISP eg.:10.128.88.120

* [/etc_server/webalizer/webalizer.conf](/etc_server/webalizer/webalizer.conf)

##VPN
As soon as a connection to the Internet is available, the kiosk connects to a VPN server (http://monitor.unicefuganda.org) and joins a virtual network using a unique certificate. The central server can easily connect to any on-line kiosk and run a SSH session (provided public key has been exchanged), kiosks can also bypass the server and talk to each other. 

* /etc_server/openvpn/ca.crt
* [/etc_server/openvpn/client.conf](/etc_server/openvpn/client.conf)
* /etc_server/openvpn/kiosk-generic.crt
* /etc_server/openvpn/kiosk-generic.key

The same certificate can be used on all kiosks, the server will identify individual machines based on their MAC address (/sys/class/net/eth0/address), that information already exists in our management database [http://monitor.unicefuganda.org/sparql?query=describe &lt;96344&gt;](http://monitor.unicefuganda.org/sparql?query=describe%20%3C96344%3E ):
```xml
<mon:Server rdf:ID="96344">
	<mon:time_stamp_v>2013-03-08T21:31:58</mon:time_stamp_v>
	<mon:partOf rdf:resource="#uniport-0"/>
	<mon:model rdf:resource="#D2"/>
	<mon:_mac_>3018ac5fed</mon:_mac_>
</mon:Server>
```
The above snippet indicates that the server with MAC address 3018ac5fed is part of 'uniport-0'. The advantage of that scheme is that all kiosks run exactly the same OS (same hostname, VPN certificats,...) and makes deployment and update easier.
The hostname could also be set automatically by running a database query once at installation, it would require network access to the database or have some cache installed locally, note that it would still use the same VPN certificate but would make identification simpler(```ssh 10.8.0.123 hostname```).


##Client control
Once the server is on, it can start all the clients on the local interface through wake-on-LAN, it will also shut them down before going down.
Wake-on-LAN is a low-level protocol, a machine will turn on if it receives a magic packet on an interface (it must be enable in the BIOS and there are other conditions).
The server uses information stored by the DHCP server in /var/lib/misc/dnsmasq.leases to send magic packets to all the machines that have ever been given a lease (sending UDP packets takes almost no time so it is not such a waste), that means that a new client will have to be started manually.
Shutting down a client is simpler, a simple SSH session is run to invoke poweroff. (note: some NL3 some time reboot instead of shutting down on receiving a 'poweroff' command, to be investigated).

The relevant files are:

* /var/lib/misc/dnsmasq.leases that file is created by dnsmasq
* [/etc_server/init.d/manage_client](/etc_server/init.d/manage_client) reads from the DHCP lease list to turn on clients (or when invoked as ```/etc/init.d/manage_client start```), it reads from the ARP list to shut them down (or when invoked as ```/etc/init.d/manage_client stop```). That script gets installed by running ```update-rc.d manage_client defaults``` (alternatively we could use an upstart job).


##Power management

The main task is to log information from the charge controller and trigger a shutdown when the voltage is nearing a set threshold.
We currently support two models: Morningstar TS-45 and Phocos C-40.
A few files are needed to run the power management task:

* [/etc_server/udev/rules.d/99-persistent-usb_serial_2.rules](/etc_server/udev/rules.d/99-persistent-usb_serial_2.rules)
	it will create a symbolic link to the USB device eg:

	```
	$ ls -l /dev/ts_45 
	lrwxrwxrwx 1 root root 7 2013-03-08 16:51 /dev/ts_45 -> ttyUSB0
	```
* [/usr/local/bin/ts_45.sh](/usr/local/bin/ts_45.sh) invokes the program defined in $CHARGE_CONTROLLER and filter it with the awk script and writes to the log file. It will trigger a shutdown if the voltage is below $LOW_VOLTAGE_DISCONNECT_12 or $LOW_VOLTAGE_DISCONNECT_24 (the actual variable is picked depending on current voltage)
* [/usr/local/bin/ts_45.awk](/usr/local/bin/ts_45.awk) awk script to format output for logging (time stamp and comma separated values).
* /var/log/ts_45.log
* [/etc_server/profile.d/kiosk_parameters.sh](/etc_server/profile.d/kiosk_parameters.sh)
	this where global environment variables are defined including $CHARGE_CONTROLLER
* crontab the above script is run every 10 minutes: (the interval could be made longer) */10 * * * * /usr/local/bin/ts_45.sh; 
* [/usr/local/bin/udp_ping.sh](/usr/local/bin/udp_ping.sh) sends UDP messages to the monitoring server on expired MTN modems (see http://mbuya.unicefuganda.org/?p=642).
Note: the script is also invoked by the remote monitoring task (see remote monitoring) and care must be taken they do not run a the same time.
Note: names should be changed from 'ts_45' to something more generic
User 'unicef_admin' should be part of group 'dialout' to be allowed to open the device.

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

##Traffic accounting

Part of the monitoring task is to measure how much data is being used for Internet access, a few files are necessary:

* [/etc_server/init/traffic_accounting.conf](/etc_server/init/traffic_accounting.conf)
	set up a few rules to capture traffic going out, management traffic (to and from 196.0.26.0/24) is separated from the rest. An environment variable $NET defines the interface used to access the Internet (eg. ppp0 for USB modem, eth0 for Ethernet) (see http://mbuya.unicefuganda.org/?p=703)
* [/usr/local/bin/safe_iptables.sh](/usr/local/bin/safe_iptables.sh) script to read the counter
* [/etc_server/sudoers.d/safe_iptables](/etc_server/sudoers.d/safe_iptables) allows to run the above script without entering password (for remote monitoring), it will be invoked as ```sudo safe_iptables.sh```
Counters get reset when machine is turned off.

##Client file system

All the clients see the same file system with some slight variations when network-mounted:

* [/etc_original/fstab](/etc_original/fstab)
* [/etc_client/fstab](/etc_client/fstab)

A [tmpfs](http://en.wikipedia.org/wiki/Tmpfs) file system is union-mounted on top of the /home/user directory, this makes possible to set up default configurations eg. home pages for browser while allowing the user to make temporary modifications, all changes will be lost once the machine reboots. The reason for that design decision is to guarantee system stability, the downside is the inability to save any file except on external storage (USB stick, cellphone) and increased RAM used (the clients should use swap space unless there is no hard-drive). This is somewhat similar to the 'guest' account already present in Ubuntu.
Based on user s feedback we will create new regular accounts without the above limitations (that creates other problems if the same account is used on different machines at the same time). 
Note that unicef_admin is a regular account but is reserved for administration.

##Thin Clients

There is a provision to have older machines connect as client, they might not have enough CPU power or RAM to run the OS and applications, the solution is to place the burden on the server, the client just runs a graphical client (over ssh) but all the applications are run on the server see www.ltsp.org for more information on thin clients.

###Installation
```
apt-get install ltsp-server-standalone
ltsp-build-client --arch i386
useradd -m -s /bin/bash user_1
useradd -m -s /bin/bash user_2
```
The last command will download a minimum OS (i386) to run on the thin client.
It uses the nbd(http://en.wikipedia.org/wiki/Network_block_device) protocol to export the minimum operating system (/opt/ltsp/images/i386.img) to the thin client, the clients then starts a graphic session on the server. 
The problem is that now all the sessions are run by the same user 'user', it will confuse some applications (Firefox, Chrome,...), a simple solution is to set different accounts ('user_1','user_2') for each machine: see [/opt/ltsp/i386/etc/lts.conf](/opt/ltsp/i386/etc/lts.conf), note that those users live in /etc_doorway/passwd and are invisible in other configurations.
After any modification to the client OS (/opt/ltsp/i386/), the squashfs image needs to be updated ```ltsp-update-image --arch i386```.

##NTP

Network time protocol is used to synchronize the clocks on remote machines, the default built in ntpdate only runs when the machine boots and will fail if no network is available.
ntpd runs as a daemon.
```apt-get install ntp```

##Initramfs

There are 3 different initrd.img files in the system

1. /initrd.img -> /boot/initrd.img-3.0.0-12-generic, used by the server, sets up the different aufs configuratios
2. /var/ftpd/initrd.img sent through PXE to the fat clients ('server' configuration)
3. var/lib/tftpboot/ltsp/i386/initrd.img -> /var/lib/tftpboot/ltsp/initrd.img-3.0.0-31-generic, sent through PXE to the thin clients ('doorway' configuration)

## Git specifics

The repository is hosted on github but also on our local server:
```
sudo git remote add origin_mbuya unicef_admin@monitor.unicefuganda.org:/srv/git/kiosk_os.git
sudo git pull origin
sudo git pull origin_mbuya master
```
Alternatively, without defining a remote branch (convenient when working in chroot jail without DNS):
```
sudo git pull unicef_admin@10.11.6.1:/srv/git/kiosk_os.git master
```

This is convenient for incremental changes, rsync will still be necessary in case of new binary files (executables, media, database,...) 
If there are no network connectivity the repository can be copied to a storage media and used instead:
```
sudo git remote add origin_usb /media/usb/full/path/to/kiosk_os.git
sudo git pull origin_usb master
```
