# linuxmuster-opsi: get opsi product updates on first weekday
SHELL=/bin/sh
PATH=/usr/local/sbin:/usr/local/bin:/sbin:/bin:/usr/sbin:/usr/bin
22 3 0 * *   root    /usr/bin/opsi-product-updater -vv | tee /var/log/opsi-product-updater.log 2>&1
