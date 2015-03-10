# sed-Skript zur Nachbereitung der shell-Funktionsaufrufe fuer das zeitliche Profiling der Funktionen.
# Siehe /usr/lib/opennet/on-helper.sh
#
# Dies entspricht folgenden Zeilen zu Beginn jeder shell-Funktion:
#   local __start_time=$(/usr/bin/date +%N)
#   trap 'echo $(( $(/usr/bin/date +%N) - __start_time)) >>/var/run/on-profiling/\1' RETURN
#

# Bash (anstelle von busybox-ash) ist erforderlich fuer die RETURN trap.
1s#/bin/sh#/bin/bash#

# Wir muessen explizit /usr/bin/date (coreutils-date) verwenden (anstelle von /bin/date -> busybox), um Nanosekunden ermitteln zu koennen.
# Die ermittelte Dauer wird als Millisekunden-Wert gespeichert.
s#^\([0-9a-zA-Z_]\+\)() *{ *$#\1() {\n\tlocal __start_time=$(/usr/bin/date +%s%N); trap 'echo $(( ($(/usr/bin/date +%s%N) - __start_time) / 1000)) >>/var/run/on-profiling/\1' RETURN#
