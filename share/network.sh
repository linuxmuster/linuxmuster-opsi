#
# linuxmuster-opsi-network
#
# thomas@linuxmuster.net
# 20170718
#

# handle network interface to use
if [ -z "$iface" ]; then
  # get list of ethernet interfaces
  ifaces=( $(ip link show | grep -B1 'link/ether' | grep ^[0-9] | awk '{ print $2 }' | awk -F\: '{ print $1 }') )
  if [ ${#ifaces[@]} -eq 0 ]; then
    echo "No ethernet interface found!"
    usage
  elif [ ${#ifaces[@]} -eq 1 ]; then
    # only one interface found, use it
    iface="$ifaces"
  else
    # more than one interfaces
    i="$(echo ${ifaces[@]})"
    while true; do
      read -p "Enter network interface to use [$i]: " -a iface
      echo $i | grep -qw $iface && break
    done
  fi
fi
# test if interface is already configured
res="$(grep -r ^iface /etc/network/* | grep -v ^"$IFACES_TGT" | grep -qw "$iface" | awk -F\: '{ print $1 }' | head -1)"
if [ -n "$res" ]; then
  echo "Interface $iface is already configured in $res."
  exit 1
fi

# save opsiip so they do not get overwritten by settings
opsiip_new="$opsiip"

# read previous setup values if present
if [ -s "$SETTINGS" ]; then
  source "$SETTINGS"
  # restore given opsiip
  [ -n "$opsiip_new" ] && opsiip="$opsiip_new"
fi

# handle ip address
if [ -z "$opsiip_new" ]; then
  # set default value
  [ -z "$opsiip" ] && opsiip="10.16.1.2"
  while true; do
    read -e -i "$opsiip" -p "Enter ip address: " input
    opsiip="${input:-$opsiip}"
    validip $opsiip && break
  done
fi

# handle netmask
if [ -z "$netmask" ]; then
  [ -n "$internalnet" -a -n "$broadcast" ] && netmask="$(ipcalc -b $(ipcalc $internalnet - $broadcast | tail -1) | grep ^Netmask | awk '{ print $2 }')"
  # set default value
  [ -z "$netmask" ] && netmask="255.240.0.0"
  while true; do
    read -e -i "$netmask" -p "Enter netmask: " input
    netmask="${input:-$netmask}"
    validmask $netmask && break
  done
fi

# handle gateway address
if [ -z "$gateway" ]; then
  gateway="$ipcopip"
  # set default value
  [ -z "$gateway" ] && gateway="10.16.1.254"
  while true; do
    read -e -i "$gateway" -p "Enter gateway address: " input
    gateway="${input:-$gateway}"
    validip $gateway && break
  done
fi

# handle nameserver address
if [ -z "$nameserver" ]; then
  nameserver="$serverip"
  # set default value
  [ -z "$nameserver" ] && nameserver="10.16.1.1"
  while true; do
    read -e -i "$nameserver" -p "Enter nameserver address: " input
    nameserver="${input:-$nameserver}"
    validip $nameserver && break
  done
fi

# write interface file
ifdown "$iface"
sed -e "s|@@iface@@|$iface|g
        s|@@opsiip@@|$opsiip|
        s|@@netmask@@|$netmask|
        s|@@gateway@@|$gateway|
        s|@@nameserver@@|$nameserver|" "$IFACES_TPL" > "$IFACES_TGT"
# change dns-search entry if domainname is set, default is localhost.localdomain
[ -n "$domainname" ] && sed -i "s|dns-search .*|dns-search $domainname|" "$IFACES_TGT"
ifup "$iface"
