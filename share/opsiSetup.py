#!/usr/bin/python3
#
# opsiSetup
# thomas@linuxmuster.net
# 20190314
#

import configparser
import os
import sys

# arguments
clientname = sys.argv[1]
try:
    forcelist = sys.argv[2]
except:
    forcelist = None

# path to client ini
inidir = '/var/lib/opsi/config/clients'
inifile = inidir + '/' + clientname + '.ini'
bakfile = inifile + '.bak'

if not os.path.isfile(inifile):
    print('Inifile not found!')
    sys.exit(1)
if not os.path.isfile(bakfile):
    print('Old inifile not found!')
    sys.exit(1)

# read client inis
newini = configparser.ConfigParser(inline_comment_prefixes=('#', ';'))
backupini = configparser.ConfigParser(inline_comment_prefixes=('#', ';'))
newini.read(inifile)
backupini.read(bakfile)

# get old products and versions and collect them in an array
setup_products = []
for (product, product_state) in backupini.items('localboot_product_states'):
    # skip not installed products
    if 'installed' not in product_state:
        continue
    bak_version = backupini.get(product + '-state', 'productversion')
    try:
        new_version = newini.get(product + '-state', 'productversion')
    except:
        setup_products.append(product)
        continue
    if bak_version != new_version:
        setup_products.append(product)
        continue
    # add forced products
    if forcelist not None:
        for item in forcelist.split(','):
            if product == item:
                setup_products.append(product)
                break

# change action to setup for collected products
if len(setup_products) > 0:
    print('Changing action to setup for:')
    for product in setup_products:
        print('# ' + product)
        backupini.set('localboot_product_states', product, 'installed:setup')
else:
    print('Nothing to do.')
    sys.exit(0)

# write changed backup file
print('Writing changed client ini.')
with open(bakfile, 'w') as outfile:
    backupini.write(outfile)

# move changed file in place
os.system('mv ' + bakfile + ' ' + inifile)
os.system('opsi-set-rights ' + inidir)
