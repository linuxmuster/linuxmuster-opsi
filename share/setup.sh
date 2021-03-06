#
# linuxmuster-opsi-setup
#
# thomas@linuxmuster.net
# 20190308
#

# read linuxmuster.net environment
. "$SETTINGS" || exit 1
# mailip is serverip on lmn62
grep -q ^mailip "$SETTINGS" || mailip="$serverip"

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
 if [ -e "$PCKEYS" ]; then
  sed -i "$PCKEYS" -e "s|$MYFQDN|opsi.$domainname|g" -e "s|\..*\:|\.$domainname\:|g" || RC="1"
 else
  RC="1"
 fi
 # config.ini
 if [ -e "$OPSICONFIG" ]; then
  sed -e "s|$MYFQDN|opsi.$domainname|g" -i "$OPSICONFIG" || RC="1"
 else
  RC="1"
 fi
 # depot_ini
 local depot_ini="$OPSICONFIGDIR/depots/$MYFQDN.ini"
 if [ -e "$depot_ini" ]; then
  sed -e "s|$MYFQDN|opsi.$domainname|g
          s|^remoteurl .*|remoteurl = smb:\/\/opsi\/opsi_depot|g
          s|^ipaddress .*|ipaddress = $opsiip|g
          s|^network .*|network = $MYNETWORK/$MYNETMASK|g" -i "$depot_ini" || RC="1"
  mv "$depot_ini" "$(dirname $depot_ini)/opsi.$domainname.ini"
 else
  RC="1"
 fi
 # clients
 local i
 local newname
 if ls "$OPSICLIENTSDIR"/*.ini &> /dev/null; then
  for i in "$OPSICLIENTSDIR"/*.ini; do
   new_ini="$(basename "$i" | awk -F\. '{ print $1 }').$domainname.ini"
   mv "$i" "$(dirname "$i")/$new_ini" || RC="1"
  done
 fi
 return "$RC"
}

set_ip(){
 # write ip to config.ini
 local RC=0
 if [ -e "$OPSICONFIG" ]; then
  sed -e "s|https://.*|https://${opsiip}:4447/rpc\"\]|g" -i "$OPSICONFIG" || RC="1"
 else
  RC="1"
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
 openssl req -new -x509 -days 3654 -nodes -config "$openssl_conf" -out "$CONFDPEM" -keyout "$CONFDPEM" || RC="1"
 openssl gendh -rand $tmp_opsiconfd_rand 512 >> "$CONFDPEM" || RC="1"
 openssl x509 -subject -dates -fingerprint -noout -in "$CONFDPEM" || RC="1"
 rm -f "$rand_conf" "$openssl_conf"
 return "$RC"
}

create_certs(){
 local RC="0"
 # lmn7
 if [ -s "$OPSIKEY" -a -s "$OPSICERT" ]; then
   cat "$OPSIKEY" "$OPSICERT" > "$CONFDPEM" || RC="1"
 else
   # lmn62
   rm -f /etc/ssh/ssh_host*key*
   ssh-keygen -t dsa -f /etc/ssh/ssh_host_dsa_key -N '' || RC="1"
   ssh-keygen -t rsa -f /etc/ssh/ssh_host_rsa_key -N '' || RC="1"
   create_opsi_cert || RC="1"
 fi
 # opsi
 return "$RC"
}

# functions end


# sets host and domainname
# hostname
if [ "$MYFQDN" != "opsi.$domainname" ]; then
 cert_ok=no
 set_fqdn || RC="1"
fi

# set ip in config.ini
set_ip || RC="1"

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
service opsipxeconfd stop
service opsiconfd stop
rm -f /var/run/opsi*/*.pid
service opsiconfd start || RC="1"
service opsipxeconfd start || RC="1"
