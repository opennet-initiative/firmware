# -*- coding: utf-8 -*-

import time

import onitester.uci_actions
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
            on_interfaces = [iface.name for iface in host.interfaces.values() if iface.role == "opennet"]
            for index, iface in enumerate(on_interfaces):
                net_name = "on_eth_%d" % index
                success = onitester.uci_actions.assign_interface_to_network(host, iface, net_name)
                self.assertTrue(success,
                        "Das opennet-Interface '%s' wurde nicht zum Opennet-Netzwerk hinzugefügt (Host %s)" % (iface, host))
                success = onitester.uci_actions.assign_network_to_firewall_zone(host, net_name, "opennet")
                self.assertTrue(success,
                        "Das Netzwerk '%s' wurde nicht zur Opennet-Firewall-Zone hinzugefügt (Host %s)" % (net_name, host))
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

