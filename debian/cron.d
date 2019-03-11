# linuxmuster-opsi: get opsi package updates on first weekday
SHELL=/bin/sh
PATH=/usr/local/sbin:/usr/local/bin:/sbin:/bin:/usr/sbin:/usr/bin
22 3 0 * *   root    /usr/bin/opsi-package-updater -vv | tee /var/log/opsi-package-updater.log 2>&1
