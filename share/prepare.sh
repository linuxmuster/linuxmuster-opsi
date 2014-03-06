#
# linuxmuster-opsi-prepare
#
# thomas@linuxmuster.net
# 27.02.2014
#

# hostname must be opsi
if [ "$(hostname)" != "opsi" ]; then
 hostname -b opsi
 echo opsi > /etc/hostname
 sed -e "s|@@domainname@@|localhost.localdomain|g" "$HOSTS_TPL" > "$HOSTS_TGT" || RC="1"
fi

if ! pkgs_installed; then
 # copy opsi.list
 cp "$OPSILIST" "$SOURCESLISTDIR"
 # get repo key
 wget -O - "$OPSIKEYURL" | apt-key add - || bailout "Cannot install opsi repository key!"
 # install packages
 apt-get update
 apt-get -y dist-upgrade
 apt-get -y install $OPSIPKGS || bailout "Error on installing opsi packages!"
 echo "Test for installed opsi packages again ..."
 pkgs_installed &> /dev/null || bailout "Not all necessary opsi packages are installed!"
 echo "Ok."
 echo
else
 apt-get update
 apt-get -y dist-upgrade
fi

# copy initial configs
cp "$SMBCONF" /etc/samba || RC="1"
cp "$SUDOERS" /etc || RC="1"
chmod 440 /etc/sudoers

# opsi setup stuff
opsi-setup --auto-configure-samba || RC="1"
opsi-setup --init-current-config || RC="1"
opsi-setup --set-rights || RC="1"
/etc/init.d/opsiconfd restart || RC="1"
/etc/init.d/opsipxeconfd restart || RC="1"
[ "$RC" = "0" ] || bailout "Opsi setup error!"

# opsiadmin user
if ! id "$ADMINUSER" &> /dev/null; then
 echo
 echo "Creating $ADMINUSER account ..."
 useradd -c "OPSI admin user" -g "$ADMINGROUP" -G adm,cdrom,sudo,dip,plugdev,lpadmin,sambashare,pcpatch -m -s /bin/bash "$ADMINUSER" || bailout "Cannot create $ADMINUSER!"
fi

# set password for opsiadmin
set_opsipassword || bailout "Opsi password error!"

echo
echo "The OPSI system has been successfully prepared."
echo "Please invoke now on the server this command:"
echo "# linuxmuster-opsi --setup --first"
