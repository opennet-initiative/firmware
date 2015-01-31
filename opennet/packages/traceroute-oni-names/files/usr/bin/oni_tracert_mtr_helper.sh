#!/bin/sh

# $1 = IP address
# $2 = ( method-traceroute | method-mtr )

rand=2466321 #"random" number for filenames. Hopefully no files created by users will be overwritten this way.

#Important: Always check user input and replace by own string for security reasons
progname="" #used later for calling programs
if [ $2 = "method-traceroute" ]; then
    progname="traceroute"
elif [ $2 = "method-mtr" ]; then
    progname="mtr"
fi
if [  -z $1 ] || [ -z $2 ] || { [ $2 != "method-traceroute" ] && [ $2 != "method-mtr" ]; }; then
   echo "Bad parameter! IP and type of program (traceroute|mtr) as parameter is needed."
   echo "e.g."
   echo "      ./oni-tracert-mtr-helper.sh 192.168.0.33 method-traceroute"
   echo "or"
   echo "      ./oni-tracert-mtr-helper.sh 192.168.0.33 method-mtr"
   echo
   exit
fi

#check for OS because of 'expr' command. We need the GNU version, not BSD (MacOS) version
os=$(uname)
cmd_expr="expr"
if [ "$os" == "Darwin" ]; then
    #set patch for GNZ version of 'expr' on MAC
    cmd_expr="/opt/local/libexec/gnubin/expr"
fi

echo "Please wait a second..."
echo "---plain $progname output---"
echo
file_bin="/usr/sbin/$progname"
file_sbin="/usr/sbin/$progname"

type $progname >> /dev/null #check if traceroute or mtr are available
ret=$?
ip_list=""
traceroute_file="/tmp/traceroute-$rand.log"
if [ ret ]; then
    if [ $progname = "traceroute" ]; then
        echo "traceroute to $1" > $traceroute_file
        traceroute $1 | tee -a $traceroute_file

        while read line; do
            #test for first line of traceroute. This line should be ignored
            tmp=$($cmd_expr match "$line" 'traceroute to')
            if [ "$tmp" != "0" ]; then
                continue
            fi

            #extract IPs
            t1=$(echo $line | cut -d " " -f 3)
            len=$(( ${#t1} - 2 ))
            ip=$($cmd_expr substr $t1 2 $len)
            if [ ${#ip_list} = 0 ]; then
                ip_list=$ip
            else
                ip_list="$ip_list,$ip"
            fi
        done < $traceroute_file

    fi
    if [ $progname = "mtr" ]; then
        mtr -n --report --report-cycles=5 $1 | tee $traceroute_file

        while read line; do
            #test for first line of traceroute. This line should be ignored
            tmp=$($cmd_expr match "$line" 'HOST:')
            if [ "$tmp" != "0" ]; then
                continue
            fi
            tmp=$($cmd_expr match "$line" 'Start:')
            if [ "$tmp" != "0" ]; then
                continue
            fi


            #extract IPs
            ip=$(echo $line | cut -d ' ' -f 2)
            if [ "$ip" == "???" ]; then
                continue
            fi
            if [ ${#ip_list} = 0 ]; then
                ip_list=$ip
            else
                ip_list="$ip_list,$ip"
            fi
        done < $traceroute_file
    fi
fi

echo 
echo "----------------------------"
echo -n "Fetching Opennet Names. Please wait ..."


#---TODO---URL von www.on-i.de holen oder von api.on-i.de ----
#          die URL dann in config speichern, falls das einmalige abholen lange dauert

server=yurika.on-i.de #TODO change this
ret_file="/tmp/ret-$rand.txt"
wget -q -O $ret_file http://$server/api/tracerouteoninames/traceroute-oni.php?input=$ip_list &>/dev/null

if [ ! -f  $ret_file ]; then
        echo
        echo
        echo "Error! Cannot connect to web service. Sorry. Try again later or contact monomartin@on-i.de"
        echo
        exit
else
    out=$(head -1 $ret_file)
    if [ ! -n "$out" ]; then
        echo
        echo
        echo "Error! Cannot connect to web service. Sorry. Try again later or contact monomartin@on-i.de"
        echo
        exit
    fi
fi

echo "  finished."

#echo "Now cat-ting /tmp/ret.txt..."
echo
cat $ret_file
echo

#delete tmp files
if [ -f $traceroute_file ]; then
    rm $traceroute_file
fi
if [ -f $ret_file ]; then
    rm $ret_file
fi
