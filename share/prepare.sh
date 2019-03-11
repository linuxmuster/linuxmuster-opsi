#
# linuxmuster-opsi-prepare
#
# thomas@linuxmuster.net
# 20190311
#

# upgrade and install necessary pkgs if not done before
pkgs_installed || dist_upgrade | tee -a "$LOGFILE"

# copy initial configs

# sudoers
if ! grep -q ^opsiconfd "$SUDOERS_TGT"; then
 echo "Updating $SUDOERS_TGT."
 cp "$SUDOERS_TPL" "$SUDOERS_TGT" || RC="1"
 chmod 440 "$SUDOERS_TGT"
fi

# opsi configs
cp "$SHAREDIR/dbp.repo" "$OPSIREPOHOOKS"
cp "$SHAREDIR/dispatch.conf" "$OPSIBCKNDMGR"
sed -i 's|^autoInstall .*|autoInstall = true|' "$OPSIWINREPO"

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
 useradd -c "OPSI admin user" -g "$ADMINGROUP" -G adm,cdrom,sudo,dip,plugdev,sambashare,pcpatch -m -s /bin/bash "$ADMINUSER" || bailout "Cannot create $ADMINUSER!"
fi

echo
echo "The OPSI system has been successfully prepared."
echo "Please invoke now on the server this command:"
echo "# linuxmuster-opsi --setup --first"
