# Cert Metadata specifically for Clear Creek Fire

COUNTRY=US
STATE=ID
CITY=BOISE
ORGANIZATION=WLPNW
ORGANIZATIONAL_UNIT=TAKUSERS

CAPASS=${CAPASS:-wolfpnwtak}
PASS=${PASS:-$CAPASS}

## subdirectory to put all the actual certs and keys in
DIR=files

##### don't edit below this line #####

if [[ -z ${STATE} || -z ${CITY} || -z ${ORGANIZATIONAL_UNIT} ]]; then
  echo "Please set the following variables before running this script: STATE, CITY, ORGANIZATIONAL_UNIT. \n
  The following environment variables can also be set to further secure and customize your certificates: ORGANIZATIO$
  exit -1
fi

SUBJBASE="/C=${COUNTRY}/"
if [ -n "$STATE" ]; then
 SUBJBASE+="ST=${STATE}/"
fi
if [ -n "$CITY" ]; then
 SUBJBASE+="L=${CITY}/"
fi
if [ -n "$ORGANIZATION" ]; then
 SUBJBASE+="O=${ORGANIZATION}/"
fi
if [ -n "$ORGANIZATIONAL_UNIT" ]; then
 SUBJBASE+="OU=${ORGANIZATIONAL_UNIT}/"
fi
