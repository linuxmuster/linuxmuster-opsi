#
# linuxmuster-opsi-prepare
#
# thomas@linuxmuster.net
# 20170717
#

# hostname must be opsi
hostname -b opsi
echo opsi > /etc/hostname
sed -e "s|@@domainname@@|localhost.localdomain|g" "$HOSTS_TPL" > "$HOSTS_TGT" || RC="1"

# copy initial configs
# samba
if ! grep -q ^"\[opsi" "$SMBCONF_TGT"; then
 echo "Updating $SMBCONF_TGT."
 cp "$SMBCONF_TGT" "$SMBCONF_TPL" || RC="1"
fi

# sudoers
if ! grep -q ^opsiconfd "$SUDOERS_TGT"; then
 echo "Updating $SUDOERS_TGT."
 cp "$SUDOERS_TPL" "$SUDOERS_TGT" || RC="1"
 chmod 440 "$SUDOERS_TGT"
fi

# tftp
if ! grep -q ^tftp "$INETDCONF_TGT"; then
 echo "Updating $INETDCONF_TGT."
 cp "$INETDCONF_TPL" "$INETDCONF_TGT" || RC="1"
 service openbsd-inetd stop &> /dev/null
 service openbsd-inetd start
fi

# opsi setup stuff
opsi-setup --auto-configure-samba || RC="1"
opsi-setup --init-current-config || RC="1"
opsi-setup --set-rights || RC="1"
service opsipxeconfd stop
service opsiconfd stop
rm -f /var/run/opsi*/*.pid
service opsiconfd start || RC="1"
service opsipxeconfd start || RC="1"
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
