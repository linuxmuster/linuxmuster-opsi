#!/bin/sh
#
# Upgrade opsi to 4.1 and ubuntu to 18.04
# thomas@linuxmuster.net
# 20190311
#

if [ -d /etc/opsi/package-updater.repos.d ]; then
  echo "Opsi is already upgraded to version 4.1!"
  exit 1
fi

if [ "$1" = "-h" -o "$1" = "--help" ]; then
  echo "Usage: $0 \"<opsiadmin password>\""
  exit 0
fi

# get opsiadmin password from command line
password="$1"

distupgrade(){
  RC="0"
  export DEBIAN_FRONTEND=noninteractive
  apt update || RC="1"
  echo -e '\n\n\n' | apt-get -y dist-upgrade || RC="1"
  apt clean || RC="1"
  apt-get -y autoremove || RC="1"
  return "$RC"
}

opsisetup(){
  RC="0"
  opsi-setup --auto-configure-samba || RC="1"
  opsi-setup --init-current-config || RC="1"
  opsi-setup --set-rights || RC="1"
  service opsipxeconfd stop
  service opsiconfd stop
  rm -f /var/run/opsi*/*.pid
  service opsiconfd start || RC="1"
  service opsipxeconfd start || RC="1"
  return "$RC"
}

RC="0"
rm -f /etc/apt/sources.list.d/lmn7.list
sed -i 's|xenial|bionic|g' /etc/apt/sources.list
sed -e 's|@@issue@@|18.04|g' /usr/share/linuxmuster-opsi/opsi.list > /etc/apt/sources.list.d/opsi.list
distupgrade || RC="1"
cp /usr/share/linuxmuster-opsi/dbp.repo /etc/opsi/package-updater.repos.d
cp /usr/share/linuxmuster-opsi/dispatch.conf /etc/opsi/backendManager
opsisetup || RC="1"
if [ -n "password" ]; then
  linuxmuster-opsi --password="$password"
else
  linuxmuster-opsi --password || RC="1"
fi

if [ "$RC" = "0" ]; then
  echo "Upgrade done, please reboot!"
else
  echo "Finished with errors!"
fi
