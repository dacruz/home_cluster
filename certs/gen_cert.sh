#!/usr/bin/env sh

set -e

BASEDIR=$(dirname "$0")

if [ "$(id -u)" != "0" ]; then
   echo "You should run $0 as root"
   exit 1
fi

if [[ -z $1 ]]
then
    echo "Usage: $0 DOMAIN" >&2
    exit 1
fi

domain=$1

certbot -d "*.$domain" --manual --preferred-challenges dns certonly

tmp_dir=`mktemp -d -t gen_cert`
cd $tmp_dir
certbot certificates 2>>/dev/null | grep $domain | grep -w -e 'fullchain.pem' -e 'privkey.pem' | rev | cut -d " " -f1 | rev | xargs -I{} cp {} ./
split -a 1 -p "-----BEGIN CERTIFICATE-----"  fullchain.pem fullchain_
cat fullchain_a fullchain_b >> fullchain_no_root.pem
cd - > /dev/null

cp $tmp_dir/fullchain_no_root.pem $BASEDIR/$domain.crt && ls $BASEDIR/$domain.crt
cp $tmp_dir/privkey.pem $BASEDIR/$domain.key && ls $BASEDIR/$domain.key

rm -rf $tmp_dir


