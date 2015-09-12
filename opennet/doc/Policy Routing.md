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


Policy Routing im Opennet
-------------------------

Die folgende Reihenfolge der Regeln definiert den Paketfluss im Opennet. Die erste passende Regel wird verwendet.

Für den historischen Vergleich dokumentieren wir hier alle im Zeitverlauf verwendeten Routing-Flüsse.


Firmware v0.5 und später
^^^^^^^^^^^^^^^^^^^^^^^^

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

Kurz zusammengefasst sollen die obigen Regeln folgende Logik ausdrücken:
1. Pakete aus dem Hotspot-Interface: Tunnel-Tabelle
2. Pakete aus Mesh-Interfaces: olsrd-Tabelle
3. Ziel-IPs die zu lokalen Interfaces gehören: main-Tabelle
4. alle: olsrd-Tabelle
5. alle: main-Tabelle
6. alle: Tunnel-Tabelle


Firmware vor v0.5
^^^^^^^^^^^^^^^^^

Vorbemerkung: beim Booten werden in die main-Tabelle *throw*-Regeln eingefügt, die alle IP-Bereiche von lokal vorhandenen olsr-Netzwerkschnittstellen umfassen.

Regel                                                | Erklärung
---------------------------------------------------- | ----------
from $NOT-MESH-NETWORK lookup main                   | Pakete mit Quell-IPs aus lokalen nicht-olsr-Mesh-Interfaces werden entsprechend lokaler Regeln zugestellt (lokale Interfaces und auch default-Route); die zuvor erwähnten *throw*-Regeln verhindern, dass Ziel-IPs aus mesh-Netzwerkbereichen betroffen sind
from all $ROUTER-PAKETE lookup main                  | dasselbe gilt für Pakete, die der Router selbst erzeugt
from all lookup default                              | falls es eine default-Regel gibt (typischerweise nicht vorhanden), dann wir sie auf alle Pakete angewandt
from $NOT-MESH-NETWORK lookup tun                    | die verbliebenen Pakete mit Quell-IPs aus lokalen nicht-olsr-Mesh-Interfaces werden über den Internet-Tunnel geleitet (typischerweise Pakete ins Internet)
from all $ROUTER-PAKETE lookup tun                   | dasselbe gilt für Pakete, die der Router selbst erzeugt
from all lookup olsrd                                | alle verbliebenen Pakete werden via olsr geroutet
from all lookup olsrd-default                        | diese Tabelle ist meist leer
from all lookup main                                 | alles andere wird lokal zugestellt

Kurz zusammengefasst sollen die obigen Regeln folgende Logik ausdrücken:
1. Pakete aus dem LAN und aus dem Router: main-Tabelle
2. alle: default-Tabelle (die ist üblicherweise leer)
3. Pakete aus dem LAN, Hotspot und aus dem Router: Tunnel-Tabelle
4. alle: olsrd-Tabelle
5. alle: main-Tabelle
