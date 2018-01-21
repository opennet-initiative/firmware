#!/bin/sh
#
# Version: 2015-03-23
#
# Uebertrage die neue CA (von 2013) auf APs mit der alten CA (von 2005).
#
# Dieses Skript war die Notlösung für das Problem der ablaufenden CA. Deren Zertifikat musste auf
# alle Clients übertragen werden, damit die VPN-Clients die Server-Zertifikate, die von der neuen
# CA unterschrieben wurden, akzeptieren.
# Zukünftig (ab Firmware v0.5-2) aktualisieren wir stattdessen das separate Paket 'on-certificates'.
#
# Ausfuehrung (auf einem AP):
#   wget -q -O - http://ca.opennet-initiative.de/tools/upgrade_ca_2005.sh | sh -s auto
#   wget -q -O - http://192.168.10.2/tools/upgrade_ca_2005.sh | sh -s auto
#

set -eu


# wir betten hier unsere neuen CA-Daten ein, um einen separaten Download zu vermeiden
NEW_CA_DATA="
# CA root 2005
-----BEGIN CERTIFICATE-----
MIIEhTCCA22gAwIBAgIBADANBgkqhkiG9w0BAQQFADCBjTELMAkGA1UEBhMCREUx
HzAdBgNVBAgTFk1lY2tsZW5idXJnLVZvcnBvbW1lcm4xEDAOBgNVBAcTB1Jvc3Rv
Y2sxEDAOBgNVBAoTB09wZW5OZXQxEzARBgNVBAMTCk9wZW5OZXQtQ0ExJDAiBgkq
hkiG9w0BCQEWFWluZm9Ab3Blbm5ldC1mb3J1bS5kZTAeFw0wNTA0MTQxNTI3NDBa
Fw0xNTA0MTIxNTI3NDBaMIGNMQswCQYDVQQGEwJERTEfMB0GA1UECBMWTWVja2xl
bmJ1cmctVm9ycG9tbWVybjEQMA4GA1UEBxMHUm9zdG9jazEQMA4GA1UEChMHT3Bl
bk5ldDETMBEGA1UEAxMKT3Blbk5ldC1DQTEkMCIGCSqGSIb3DQEJARYVaW5mb0Bv
cGVubmV0LWZvcnVtLmRlMIIBIjANBgkqhkiG9w0BAQEFAAOCAQ8AMIIBCgKCAQEA
u1L/yTFYcGQiDe/Bgadlz3eYyz0zZthejP8VRdQIsqXS2Ho2OjMsMxCQOppaST7l
D1lWliG2YDPCKSCmKWXCY572XgUZ98QqYT1wfjN8hAwDa974y5S/JX7D4cYc3DZC
h0jIE6gEu72bB3cRSaOA4i5czHRXsWxkfdF19BsPgMMp3wCx/IjNj1KU/AfVATU4
iBdHe74fzuifeJsCx9UbBOugP3TU3lTNmpORAJIP4wGYwPryP+05k2RcEdOvolKP
qZzi2hi7aaDe3jb6buzjlQJXZNwDStFjnlqYe4ofddOCEUvQV6aBkLJXe8LXPVjk
cb4sE9RAqnuTS6pj/B63nwIDAQABo4HtMIHqMB0GA1UdDgQWBBQqhv8v5THmbBIi
Fb+WnFaBcuu4MjCBugYDVR0jBIGyMIGvgBQqhv8v5THmbBIiFb+WnFaBcuu4MqGB
k6SBkDCBjTELMAkGA1UEBhMCREUxHzAdBgNVBAgTFk1lY2tsZW5idXJnLVZvcnBv
bW1lcm4xEDAOBgNVBAcTB1Jvc3RvY2sxEDAOBgNVBAoTB09wZW5OZXQxEzARBgNV
BAMTCk9wZW5OZXQtQ0ExJDAiBgkqhkiG9w0BCQEWFWluZm9Ab3Blbm5ldC1mb3J1
bS5kZYIBADAMBgNVHRMEBTADAQH/MA0GCSqGSIb3DQEBBAUAA4IBAQAt1uF9TFgx
39ZZpwIU9WRQk+Nvv8vXM3z6xAOnC1R0lDrmEv7kxJFGBRQXPv8HUD15biZQeQ00
QIUNMEd8s92v9jdrc52DZ8ivva8eiefUfPJbPJtdsKWpCqQLQIpCmew3deOtfMN8
ZMq7boUQ1dgniJl8nmUJzJdSgpWY9MMElVBNmJ08++WI7JegNpd+O7j7aL+YXtWc
+epfbKqCyjQiGjBYQxzgH477UjW/RjnJY3v8wAfXrYGCfZvJYIA8Amwq7SeMVHuA
eq6+u5HhCtlkmsXogpuw4KW7VFTCQJ9vUiS7MIgw1oohmDXd18yRpw4+4GshzeaE
RN2EbaPHFlUX
-----END CERTIFICATE-----
# CA Server 2014
-----BEGIN CERTIFICATE-----
MIIGZjCCBE6gAwIBAgIJAJ52z3EPcf7xMA0GCSqGSIb3DQEBCwUAMIGuMQswCQYD
VQQGEwJERTEfMB0GA1UECBMWTWVja2xlbmJ1cmctVm9ycG9tbWVybjEgMB4GA1UE
ChMXT3Blbm5ldCBJbml0aWF0aXZlIGUuVi4xEzARBgNVBAsTCk9wZW5uZXQgQ0Ex
GzAZBgNVBAMTEm9wZW5uZXQtcm9vdC5jYS5vbjEqMCgGCSqGSIb3DQEJARYbYWRt
aW5Ab3Blbm5ldC1pbml0aWF0aXZlLmRlMB4XDTE0MDMzMDEwMDczMloXDTI0MDMy
NzEwMDczMlowgbAxCzAJBgNVBAYTAkRFMR8wHQYDVQQIExZNZWNrbGVuYnVyZy1W
b3Jwb21tZXJuMSAwHgYDVQQKExdPcGVubmV0IEluaXRpYXRpdmUgZS5WLjETMBEG
A1UECxMKT3Blbm5ldCBDQTEdMBsGA1UEAxMUb3Blbm5ldC1zZXJ2ZXIuY2Eub24x
KjAoBgkqhkiG9w0BCQEWG2FkbWluQG9wZW5uZXQtaW5pdGlhdGl2ZS5kZTCCASIw
DQYJKoZIhvcNAQEBBQADggEPADCCAQoCggEBAOe677gUZ+T2l5wSGUil+Dg2V2Fn
p73G4TqvXGe8oLBX4mOMawVUPtN0jiepGnZJT+iYp9w8iAGMCH9IVk7xdgzNF2aK
gLaqt+ZTAiV2IGT5EPwZjOAfiJv9QrWyrq7TkLZzCquKu+0phG/TW7CEf4JHuhoZ
fQEcnmHURhl5Fc1fUrq1QAfiAkJ12pr+5fqxjZrVME///6mjXvhKuvvI9pt7gJ0w
S7Nm5grsIHSnNqWpJWl+o7hA3/Qnj+zTfuMMGhBHm/3UyVLj8YN56h1DqoMtT3Zp
vVcvVoCiaO9f5pNvE5Ho9UueasPl9VQghocELJwKc8hJqlMrqPG43bsDnMcCAwEA
AaOCAYEwggF9MAwGA1UdEwQFMAMBAf8wHwYDVR0jBBgwFoAU+tqmJSQsIOflo18v
n2vB6hka+MEwHQYDVR0OBBYEFMHCtS7kheDpQ9OaS6I5dpQP4cFBMB4GCWCGSAGG
+EIBDQQRFg9PcGVubmV0IFJvb3QgQ0EwLwYJYIZIAYb4QgEIBCIWIGh0dHA6Ly9j
YS5vcGVubmV0LWluaXRpYXRpdmUuZGUvMDcGCWCGSAGG+EIBBAQqFihodHRwOi8v
Y2Eub3Blbm5ldC1pbml0aWF0aXZlLmRlL3Jvb3QuY3JsMDcGCWCGSAGG+EIBAwQq
FihodHRwOi8vY2Eub3Blbm5ldC1pbml0aWF0aXZlLmRlL3Jvb3QuY3JsMC8GCWCG
SAGG+EIBAgQiFiBodHRwOi8vY2Eub3Blbm5ldC1pbml0aWF0aXZlLmRlLzA5BgNV
HR8EMjAwMC6gLKAqhihodHRwOi8vY2Eub3Blbm5ldC1pbml0aWF0aXZlLmRlL3Jv
b3QuY3JsMA0GCSqGSIb3DQEBCwUAA4ICAQBFMcuDQlu14gFvdKbIbwEM07NWEtlE
zqmt1n4n6J6ZCD0jgjzMUaQYvG6bs+yMk2wYmohUtxGkoyZcgs7JC1Le7Rvya3Rc
r977NOVIdtB9hbB9GtwrUF31t8W8tPFqd1DIHiESbYn+7WcHvnjnPZiwPJlfsicZ
XzZeI0BjioRkhrpX+U0bERCq0RAjg4Cmt8mcs+0pkyUg8ALhMMwC3VMX6whWqTfa
iXDjNrVh4jfCceKC5peqAolWM7Oqwg9LF4gvQ2xPuUVNeUXtoDl7Bp+LEDtkRavo
pGziowoK7awG3jDN6dSylykSg97yNhx75mRmHHbElMZ2xiKEDI/sE5WfzK9LfP12
m4YWOx3ycpleWpo5ECFhGVbYkHfy3b8DGwRb4o1VUvGo4G/4LPV5yXJhKif5+A3g
IbJt9VihxA3X+SfnlhG+8okhdy44qJ0Y9aP2hTCPWtXjO8ZVmfVtS8WxdcjcoA29
9Ywv4HSst/Z6ibxSIwFDuyO+BCn6tIej6W6aRKL63fY58vi6CcG3L4Fd6TwKW9mM
75zke+sP82Za66RZHQOIOIculOmv5ExOhNsKS9iHQmH0MYb5Lx7XicPCpLJWvxD/
ycrJDxyhdB74mhLojjYLwErf2r1FF/nGivasUyzxPsC8WvUB0ADQKwrHt2TDmz/S
Dzw47o27ziWuGw==
-----END CERTIFICATE-----
# CA root 2013
-----BEGIN CERTIFICATE-----
MIIHZjCCBU6gAwIBAgIJANCUEcpFurXxMA0GCSqGSIb3DQEBDQUAMIGuMQswCQYD
VQQGEwJERTEfMB0GA1UECBMWTWVja2xlbmJ1cmctVm9ycG9tbWVybjEgMB4GA1UE
ChMXT3Blbm5ldCBJbml0aWF0aXZlIGUuVi4xEzARBgNVBAsTCk9wZW5uZXQgQ0Ex
GzAZBgNVBAMTEm9wZW5uZXQtcm9vdC5jYS5vbjEqMCgGCSqGSIb3DQEJARYbYWRt
aW5Ab3Blbm5ldC1pbml0aWF0aXZlLmRlMB4XDTEzMTIyMjAwMDAwMFoXDTMzMTIy
MTIzNTk1OVowga4xCzAJBgNVBAYTAkRFMR8wHQYDVQQIExZNZWNrbGVuYnVyZy1W
b3Jwb21tZXJuMSAwHgYDVQQKExdPcGVubmV0IEluaXRpYXRpdmUgZS5WLjETMBEG
A1UECxMKT3Blbm5ldCBDQTEbMBkGA1UEAxMSb3Blbm5ldC1yb290LmNhLm9uMSow
KAYJKoZIhvcNAQkBFhthZG1pbkBvcGVubmV0LWluaXRpYXRpdmUuZGUwggIiMA0G
CSqGSIb3DQEBAQUAA4ICDwAwggIKAoICAQDWt60B2V7G01XFkxvIYoIHpzESJHfl
W3MFlJYrzEFruUU4icXnHHJYHzlfGR4xiMKLmnEuyGfdx5K7rc8DTINbSt3sjXJa
0H/5015BsaiDPF8nIrR4Knd3D07Li+bNLOcIG4I6UjgRYpqWpq5jRb6rNSSG5U1Z
ctPI60tB8UOkB6YhCx9ETjRp74wnnmC+WFOURi2bvy4zjlB6ze6r0ic033ULlmwz
MPDsDZqYhTWtQuz/hvb+OKeMMLkqskd0P8x+4GrRkJN8jfuKUBt4CCrBDa0Eqf1P
ORUKrGGHN95heBmA+CMivpUBDKtQ9nIK6zjy9DDpj3vGAj1N/goVmhi4cejYvvwx
Oar2diB6FpGKVaNVHABO/I2uHW45XFiuopCGdP3jGH8E7p4jicx1kUKTaBWbA36g
hppUdOZUtRa1/7flxfAPonRjg4DOkcDyf8/lys+A/KysEvdhh2p7xWj49ZNQDhJE
tE3b0+EPtGUQVWyYjQkDXAYfCDEWyMq2UU9ywQs4RfzQgY/8HkKD10EqRnIJYkFg
rbLengwYF7uyrubKdBAGh8H35LOf2aAyu4al6Zd8wI1F5Fdpk6EV7SFrqsNevDP9
rbWG/9oVRV7uhSgeL8EbuF3g3e2iLWDJi4dxuYdCjbs5oF/yQjaWfWCA9viFxGHK
5meKOd2ZdFhHUQIDAQABo4IBgzCCAX8wDwYDVR0TAQH/BAUwAwEB/zAdBgNVHQ4E
FgQU+tqmJSQsIOflo18vn2vB6hka+MEwCwYDVR0PBAQDAgEGMDkGA1UdHwQyMDAw
LqAsoCqGKGh0dHA6Ly9jYS5vcGVubmV0LWluaXRpYXRpdmUuZGUvcm9vdC5jcmww
EQYJYIZIAYb4QgEBBAQDAgAHMC8GCWCGSAGG+EIBAgQiFiBodHRwOi8vY2Eub3Bl
bm5ldC1pbml0aWF0aXZlLmRlLzA3BglghkgBhvhCAQMEKhYoaHR0cDovL2NhLm9w
ZW5uZXQtaW5pdGlhdGl2ZS5kZS9yb290LmNybDA3BglghkgBhvhCAQQEKhYoaHR0
cDovL2NhLm9wZW5uZXQtaW5pdGlhdGl2ZS5kZS9yb290LmNybDAvBglghkgBhvhC
AQgEIhYgaHR0cDovL2NhLm9wZW5uZXQtaW5pdGlhdGl2ZS5kZS8wHgYJYIZIAYb4
QgENBBEWD09wZW5uZXQgUm9vdCBDQTANBgkqhkiG9w0BAQ0FAAOCAgEABc8BnTqs
tqZwjHJXZtqX7db3siScznVaDdsmhvv1L7MIs7LH4ndfm2EbjBJ87uDRUfFZf2ZM
08TwBtRFEnF4FV512WHF/KcQi0hEGqeegO4w1jyiG2jHrHd4xtNwZ2rQ+IAOe4/Z
ozx1auvzjneD2NCoxkm0CaVHFNIxXzv9pfrCeIAMtKD2bideSfFD2HIYr50jobDq
YwZuWe0GS5Oku6NKNvO4W/ncAOxJRsJRW9rgZA5xIntL9YugmMPCwOQ+9RGZbD8f
ZFF/xSvmj4+EIPlSvLd0Y+7Fdcx/XJFq5l8hTN8+zHWwgBWEkvcCUsYPEPQqdWTS
K2TDMkJLK22QH2rP7mkgcDAnezusz+XzN8ssKdSdPUk/P+J1M/DYQSTCwUtsBZKc
rYR3BGOGWgW2gpJFtqYCjEz87uCQ0qKz5nT1iH6KBTWLryQ5vX7vSp0wesuU3MdC
75nidAMMRICX2vZ1aB5nKj3SzOCYKsv7Fcb2g5+5IHT82ziNw5Sku3HqTB9h003W
ozXdQcv4cJfuTKyCvhDBF1kaRH12kaqRfkh5PQ3WmNnkj3aJ+mHs3qabfoXQiBYu
gvoeS4I84wHGXvopsx7opxSCL2mT2gKTElBEAc1aPhvixCsiUTtixOEe1HGNyGN/
n73OAEN205nlw30yA65Epco+uQHITALI5FU=
-----END CERTIFICATE-----"


# Filtere whitespace heraus und ermittle die md5-Summe
get_clean_md5sum() {
	grep -v "^$" | grep -v "^#" | tr '\n' '!' | sed 's/!$//' | tr '!' '\n' | md5sum | awk '{print $1}'
}


replace_file_safely() {
	local filename="$1"
	local tmp_filename="${filename}.tmp"
	cat >"$tmp_filename"
	mv "$tmp_filename" "$filename"
}


get_ca_version() {
	local filename="$1"
	local local_checksum
	local_checksum=$(get_clean_md5sum <"$filename")
	if [ "$local_checksum" = "$CA_2005_CHECKSUM" ]; then
		echo 2005
	elif [ "$local_checksum" = "$CA_2013_CHECKSUM" ]; then
		echo 2013
	else
		echo unbekannt
	fi
}


create_backup() {
	local filename="$1"
	local backup_filename="${filename}.backup_upgrade_ca_2005"
	cp "$filename" "$backup_filename"
}


# Filtere Kommentare heraus
NEW_CA_DATA=$(echo "$NEW_CA_DATA" | grep -v "^#" | grep -v "^$")
USER_VPN_CA_FILE="/etc/openvpn/opennet_user/opennet-ca.crt"
CA_2005_CHECKSUM="7d5759bd9aa7b4311f4b38565b7406b3"
CA_2013_CHECKSUM="9797744f561a25609a21a0766931e984"


ACTION="${1:-status}"

case "$ACTION" in
	auto|force)
		ca_version=$(get_ca_version "$USER_VPN_CA_FILE")
		if [ "$ca_version" = "2005" ]; then
			echo "Lokales CA-Zertifikat: 2005"
			echo "Installiere neues Zertifikat ..."
			echo "$NEW_CA_DATA" | replace_file_safely "$USER_VPN_CA_FILE"
			echo "Fertig!"
		elif [ "$ca_version" = "2013" ]; then
			echo "Lokales CA-Zertifikat: 2013"
			echo "Es ist keine Aktion erforderlich."
			echo "Fertig!"
		else
			echo "Unbekannte lokale CA-Zertifikate entdeckt."
			if [ "$ACTION" = "force" ]; then
				echo "'force' wurde gewaehlt - es geht weiter ..."
				echo "Erstelle Sicherheitskopie des existierenden Zertifikats ..."
				create_backup "$USER_VPN_CA_FILE"
				echo "Installiere neues Zertifikat ..."
				echo "$NEW_CA_DATA" | replace_file_safely "$USER_VPN_CA_FILE"
				echo "Fertig!"
			else
				echo "Abbruch aufgrund des unbekannten lokalen Zertifikats."
				echo "Fuehre denselben Befehl erneut mit dem Parameter 'force' anstelle von 'auto' aus, falls du das Zertifikat wirklich ueberschreiben moechtest".
			fi
		fi
		;;
	status)
		echo -n "Aktuelle CA-Version: "
		get_ca_version "$USER_VPN_CA_FILE"
		;;
	help|--help)
		echo "Syntax: $(basename "$0")  { status | install }"
		echo
		;;
	*)
		"$0" help >&2
		exit 1
		;;
esac

exit 0

