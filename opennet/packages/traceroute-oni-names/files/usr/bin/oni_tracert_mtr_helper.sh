#!/bin/sh

# $1 = IP address
# $2 = ( method-traceroute | method-mtr )
CONTACT_EMAIL="monomartin@on-i.de"

if [ "$2" = "method-traceroute" ]; then
    progname="traceroute"
elif [ "$2" = "method-mtr" ]; then
    progname="mtr"
else
    progname=""
fi

if [ "$#" -ne 2 ] || [ -z "$1" ] || [ -z "$progname" ]; then
   echo "Bad parameter! IP and type of program (traceroute|mtr) as parameter is needed."
   echo "e.g."
   echo "      ./oni-tracert-mtr-helper.sh 192.168.0.33 method-traceroute"
   echo "or"
   echo "      ./oni-tracert-mtr-helper.sh 192.168.0.33 method-mtr"
   echo
   exit 1
fi >&2

echo "Please wait a second..."
echo "---plain $progname output---"
echo

type "$progname" >/dev/null 2>&1 || {
    echo "No traceroute program ($progname) found."
    exit 2
} >&2

if [ "$progname" = "traceroute" ]; then
    # replace any "*" (unknown) with space
    traceroute -n "$1" | tr '*' ' ' | while read line; do
        # Ausgabe (Debugging)
        echo "$line"
        # print IP
        echo "$line" | awk '{ print $2 }'
    done
else
    # ignore first lines ("HOST:"; "Start:")
    mtr --no-dns --report --report-cycles=5 "$1" | grep -v "^[A-Z]" | while read line; do
        # Ausgabe (Debugging)
        echo "$line"
        echo "$line" | awk '{ print $2 }'
    done
fi | grep -v "^$" | tr '\n' ','

echo 
echo "----------------------------"
echo -n "Fetching Opennet Names. Please wait ..."


#---TODO---URL von www.on-i.de holen oder von api.on-i.de ----
#          die URL dann in config speichern, falls das einmalige abholen lange dauert

server=yurika.on-i.de #TODO change this
response=$(wget -q -O - "http://$server/api/tracerouteoninames/traceroute-oni.php?input=$ip_list" 2>/dev/null)

# file does not exist or is empty?
if [ -z "$response" ]; then
    echo
    echo
    echo "Error! Cannot connect to web service. Sorry. Try again later or contact $CONTACT_EMAIL"
    echo
    exit 3
fi >&2

echo "  finished."

# output of the web API
echo
echo "$response"
echo
