import time

from onitester.tests._common import OpennetTest


class OnCore(OpennetTest):

    def test_05_on_core_settings(self):
        """ Pruefe die on-core-Einstellungen """
        for host in self.get_hosts():
            result = host.execute("uci show on-core")
            self.assertTrue(result.success and not result.stdout.is_empty(),
                    "Die uci-Einstellungen fuer on-core fehlen: %s" % host)
            result = host.execute("grep -qi opennet /etc/banner")
            self.assertTrue(result.success, "Die Datei /etc/banner " + \
                    "enthaelt keinen Text 'opennet': %s" % host)

    def test_10_enable_opennet_interfaces(self):
        """ Konfiguriere die Opennet-Netzwerk-Interfaces (nur fuer APs) """
        for host in self.get_hosts():
            if not host.ap_id:
                continue
            # Leider ist es nicht leicht, die javascript-basierte Interface-Auswahl zu simulieren.
            # Also stattdessen der Weg ueber uci.
            on_interfaces = [iface for iface, net in host.networks.iteritems() if net.is_opennet]
            for index, iface in enumerate(on_interfaces):
                # alle Netzwerke von diesem Interface trennen
                result = host.execute("uci show network | grep 'ifname=%s$'" % iface)
                for line in result.stdout.lines:
                    key = line.split("=")[0]
                    host.execute("uci set %s=none" % key)
                # olsr-Interface setzen (falls es noch nicht existiert)
                net_name = "on_eth_%d" % index
                result = host.execute("uci set network.%s=interface" % net_name)
                self.assertTrue(result.success,
                        "Anlegen des Interface schlug fehl (%s): %s" % (host, result.stderr))
                host.execute("uci set network.%s.ifname=%s" % (net_name, iface))
                self.assertTrue(result.success,
                        "Zuordnen des Interface schlug fehl (%s): %s" % (host, result.stderr))
                host.execute("uci commit network.%s" % net_name)
                self.assertTrue(result.success,
                        "Bestaetigung der Interface-Aenderung schlug fehl (%s): %s" % (host, result.stderr))
                # Interface zur openvpn-Firewall-Zone hinzufuegen
                fw_opennet_nets = host.execute("uci get firewall.zone_opennet.network").stdout.lines[0].strip().split()
                self.assertTrue(result.success,
                        "Auslesen der Firewall schlug fehl (%s): %s" % (host, result.stderr))
                if not net_name in fw_opennet_nets:
                    fw_opennet_nets += net_name
                    host.execute("uci set firewall.zone_opennet.network=%s" % " ".join(fw_opennet_nets))
                    self.assertTrue(result.success,
                            "Aktualisieren der Firewall-Zone schlug fehl (%s): %s" % (host, result.stderr))
                    host.execute("uci commit firewall.zone_opennet")
                    self.assertTrue(result.success,
                            "Bestaetigen der Firewall-Aenderung schlug fehl (%s): %s" % (host, result.stderr))
                result = host.execute("uci show network | grep -q 'on_eth_.\.ifname=%s$'" % iface)
                # irgendetwas muss ja auch getestet werden ...
                self.assertTrue(result.success,
                        "Das Opennet-Interface wurde nicht via uci erzeugt: %s" % host)
            # konfigurieren!
            result = host.execute("/etc/init.d/network restart")
            self.assertTrue(result.success, "Die Netzwerk-Konfiguration schlug fehl (%s): %s" % (host, result.stderr))


    def test_15_set_opennet_id(self):
        """ Setze die Opennet-ID (nur fuer APs) """
        for host in self.get_hosts():
            # Opennet-ID festlegen, falls "AP" (laut Namen)
            if not host.ap_id:
                continue
            host.open_url("/cgi-bin/luci/opennet/opennet_1/funknetz")
            # Anmeldung
            result = host.web_login()
            self.assertTrue(host.web_login(),
                    "Anmeldung schlug fehl: %s" % host)
            form = host.browser.getForm(action="/funknetz")
            form.getControl(name="form_id").value = host.ap_id
            form.submit()
            time.sleep(2)
            # TODO: der erforderliche network-Restart duerfte ein Bug sein
            result = host.execute("/etc/init.d/network restart")
            # verify the new IP
            for attempt in range(8):
                if self._has_ip(host, "192.168.%s" % host.ap_id):
                    break
                time.sleep(1)
            else:
                # keine passende IP gefunden
                ips = " ".join(self._get_ips(host, ip_version=4))
                self.assertTrue(False, "Die neue Opennet-IP wurde nicht " + \
                        "konfiguriert. Derzeit sind lediglich folgende IPs " + \
                        "auf %s gesetzt: %s" % (host, ips))

