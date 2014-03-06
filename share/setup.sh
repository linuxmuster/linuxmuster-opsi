#
# linuxmuster-opsi-setup
#
# thomas@linuxmuster.net
# 26.02.2014
#

# read linuxmuster.net environment
. "$SETTINGS" || exit 1

# test if necessary pkgs are installed
pkgs_installed &> /dev/null || bailout "The neccessary opsi packages are not installed!"

# get network stuff
for i in $OPSICONFIGDIR/depots/*.ini; do
 MYFQDN="$(basename "$i" | sed -e 's|.ini||')"
 [ -n "$MYFQDN" ] && break
 MYFQDN=""
done
[ -z "$MYFQDN" ] && MYFQDN="$(grep ^127 /etc/hosts | grep -v localhost | awk '{ print $2 }' | head -1)"
[ -z "$MYFQDN" ] && MYFQDN="$(hostname -f 2> /dev/null)"
[ -z "$MYFQDN" ] && bailout "Cannot get hostname!"
MYHOSTNAME="${MYFQDN%%.*}"
MYDOMAIN="${MYFQDN/$MYHOSTNAME./}"
MYIP="$(ip route get 8.8.8.8 | head -1 | awk '{ print $7 }')"
[ -z "$MYIP" ] && bailout "Cannot get ip address!"
[ "$MYIP" = "$opsiip" ] || bailout "Ip address is not $opsiip!"
MYNETMASK="$(ifconfig | grep -w inet | grep "$MYIP" | awk '{print $4}' | cut -d ":" -f 2)"
MYNETWORK="$(ipcalc $MYIP/$MYNETMASK | grep ^Network: | awk '{ print $2 }' | awk -F\/ '{ print $1 }')"

# control variables
cert_ok=yes
rand_conf="/var/tmp/opsirand.cnf.$$"
openssl_conf="/var/tmp/opsissl.cnf.$$"
[ -n "$first" ] && cert_ok=no


# functions begin

set_fqdn(){
 local RC="0"
 echo "opsi" > /etc/hostname || RC="1"
 sed -e "s|@@domainname@@|$domainname|g" "$HOSTS_TPL" > "$HOSTS_TGT" || RC="1"
 [ -e "$PCKEYS" ] && sed -i "$PCKEYS" -e "s|$MYFQDN|opsi.$domainname|g" -e "s|\..*\:|\.$domainname\:|g"
 # config.ini
 [ -e "$OPSICONFIG" ] && sed -e "s|$MYFQDN|opsi.$domainname|g" -i "$OPSICONFIG"
 # depot_ini
 local depot_ini="$OPSICONFIGDIR/depots/$MYFQDN.ini"
 if [ -e "$depot_ini" ]; then
  sed -e "s|$MYFQDN|opsi.$domainname|g
          s|^remoteurl .*|remoteurl = smb:\/\/opsi\/opsi_depot|g
          s|^ipaddress .*|ipaddress = $opsiip|g
          s|^network .*|network = $MYNETWORK/$MYNETMASK|g" -i "$depot_ini"
  mv "$depot_ini" "$(dirname $depot_ini)/opsi.$domainname.ini"
 fi
 # clients
 local i
 local newname
 if ls "$OPSICLIENTSDIR"/*.ini &> /dev/null; then
  for i in "$OPSICLIENTSDIR"/*.ini; do
   new_ini="$(basename "$i" | awk -F\. '{ print $1 }').$domainname.ini"
   mv "$i" "$(dirname "$i")/$new_ini"
  done
 fi
 return "$RC"
}

write_cert_data_to_debconf(){
 local RC="0"
 echo "set opsiconfd/cert_country $country" | debconf-communicate -f noninteractive || RC="1"
 echo "set opsiconfd/cert_state $state" | debconf-communicate -f noninteractive || RC="1"
 echo "set opsiconfd/cert_locality $location" | debconf-communicate -f noninteractive || RC="1"
 echo "set opsiconfd/cert_organization $schoolname" | debconf-communicate -f noninteractive || RC="1"
 echo "set opsiconfd/cert_unit linuxmuster.net" | debconf-communicate -f noninteractive || RC="1"
 echo "set opsiconfd/cert_commonname opsi.${domainname}" | debconf-communicate -f noninteractive || RC="1"
 echo "set opsiconfd/cert_email ${admin}@${domainname}" | debconf-communicate -f noninteractive || RC="1"
 return "$RC"
}

write_cert_tmp_config(){
 local RC
 dd if=/dev/urandom of="$rand_conf" count=1 2>/dev/null
 cat << EOF > "$openssl_conf"
RANDFILE = $rand_conf

[ req ]
default_bits = 1024
encrypt_key = yes
distinguished_name = req_dn
x509_extensions = cert_type
prompt = no

[ req_dn ]
C=$country
ST=$state
L=$location
O=$schoolname
OU=linuxmuster.net
CN=opsi.${domainname}
emailAddress=${admin}@${domainname}

[ cert_type ]
nsCertType = server
EOF
 RC="$?"
 return "$RC"
}

create_opsi_cert(){
 local RC="0"
 write_cert_data_to_debconf &> /dev/null || RC="1"
 write_cert_tmp_config || RC="1"
 openssl req -new -x509 -days 1000 -nodes -config "$openssl_conf" -out /etc/opsi/opsiconfd.pem -keyout /etc/opsi/opsiconfd.pem || RC="1"
 openssl gendh -rand $tmp_opsiconfd_rand 512 >> /etc/opsi/opsiconfd.pem || RC="1"
 openssl x509 -subject -dates -fingerprint -noout -in /etc/opsi/opsiconfd.pem || RC="1"
 rm -f "$rand_conf" "$openssl_conf"
 return "$RC"
}

create_certs(){
 local RC="0"
 # ssh
 rm -f /etc/ssh/ssh_host*key*
 ssh-keygen -t dsa -f /etc/ssh/ssh_host_dsa_key -N '' || RC="1"
 ssh-keygen -t rsa -f /etc/ssh/ssh_host_rsa_key -N '' || RC="1"
 # opsi
 create_opsi_cert || RC="1"
 return "$RC"
}

# functions end


# sets host and domainname
# hostname
if [ "$MYFQDN" != "opsi.$domainname" ]; then
 cert_ok=no
 set_fqdn || RC="1"
fi

# update product config
cp "$PRODCNF_TGT" "${PRODCNF_TGT}.linuxmuster-backup"
if [ -n "$first" ]; then
 sed -e "s|@@serverip@@|$serverip|g
         s|@@admin@@|$admin|g
         s|@@domainname@@|$domainname|g" "$PRODCNF_TPL" > "$PRODCNF_TGT" || RC="1"
else
 sed -e "s|^smtphost .*|smtphost = $serverip|
         s|^sender .*|sender = opsi-product-updater@$domainname|
         s|^receivers .*|receivers = ${admin}@$domainname|" -i "$PRODCNF_TGT" || RC="1"
fi

# repair opsi permissions
opsi-setup --set-rights "$OPSISYSDIR" || RC="1"
opsi-setup --set-rights "$OPSICONFIGDIR" || RC="1"

# create ssh and host certs
if [ -n "$first" -o "$cert_ok" != "yes" ]; then
 create_certs || RC="1"
fi

# opsi setup finally
opsi-setup --auto-configure-samba || RC="1"
opsi-setup --init-current-config || RC="1"
/etc/init.d/opsiconfd restart || RC="1"
/etc/init.d/opsipxeconfd restart || RC="1"
