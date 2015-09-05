[TOC]

Policy Routing {#policy-routing}
==============

Wir verwenden für IPv4-Verkehr das Policy Routing, um Ziel-Routen abhängig von der Paketherkunft auszuwählen.


Integration in Firmware
-----------------------

Nach dem Booten und bei jeder Änderung (up/down) von Netzwerk-Schnittstellen wird die Funktion *initialize_olsrd_policy_routing* ausgeführt. Diese Funktion enthält die folgenden Schritte:

1. Routing-Tabellen anlegen, falls sie noch fehlen (*/etc/iproute2/rt_tables*)
2. alle alten Regeln löschen (*ip rule del ...*)
3. neue Regeln erstellen


Policy-Routing im Opennet
-------------------------

Die folgende Regenreihenfolge definiert den Paketfluss im Opennet. Die erste passende Regel wird verwendet.

Regel                                                | Erklärung
---------------------------------------------------- | ----------
from all iif $ON-FREE-INTERFACE lookup on-tunnel     | Verkehr von Hotspot-Nutzenden darf ausschließlich ins Internet gehen
from all iif $ON-MESH-INTERFACE lookup olsrd         | Verkehr aus dem Opennet-Mesh sollte vorrangig über das olsr-Routing gelenkt werden, damit lokale Netzwerk-Interfaces keinen Einfluss auf vorbeifließenden Verkehr haben
from all iif $ON-MESH-INTERFACE lookup olsrd-default | die default-Tabelle wird aktuell nicht genutzt - inhaltlich ist sie vergleichbar mit *olsrd* (siehe oben)
from all to $NOT-MESH-NETWORK lookup main            | Pakete mit Ziel-IPs, die zu einem der nicht-Mesh-Interfaces gehören, werden durch die main-Tabelle geroutet. Somit dominieren die lokalen Interfaces für Verkehr, der nicht aus einem Mesh-Interface kam (dieser wurde oben bereits behandelt).
from all lookup olsrd                                | der übrige Verkehr (keine lokale Ziel-Adresse, nicht aus dem Mesh kommend; also überwiegend Verkehr aus der LAN-Zone) wird ins Mesh geroutet, falls es passt
from all lookup olsrd-default                        | ebenso
from all lookup main                                 | der verbliebene Verkehr fließt beispielsweise in die default-Route (lokaler Uplink)
from all lookup default                              | Rückfall-Option, falls es keine default-Route in der main-Tabelle gibt
from all lookup on-tunnel                            | zweite Rückfall-Option: falls es keine lokalen default-Routen gibt, wird der Tunnel verwendet
