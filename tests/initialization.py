import re
import time

import _common


class BasicSetup(_common.AllHostsTest):
    """ Grundlegende Konfiguration der Router """

    def test_01_connect(self):
        """ Pruefe die Erreichbarkeit """
        for host in self.hosts:
            browser = host.get_browser()
            self.assertIsNotNone(browser, "Keine Verbindung mit Host %s" % host)
            self.assertTrue("Opennet" in browser.contents,
                    "Kein 'OpenWrt'-Webinterface gefunden: %s" % host)
            self.assertTrue("Graphen" in browser.contents,
                    "Keine deutschsprachige Web-Oberflaeche: %s" % host)

    def test_05_password(self):
        """ Setze das root-Passwort """
        for self.host in self.hosts:
            browser = self.host.get_browser("/cgi-bin/luci/admin/system/admin")
            self.assertTrue(self._login(browser),
                    "Anmeldung schlug fehl: %s" % self.host)
            form = browser.getForm(name="cbi")
            form.getControl(name="cbid.system._pass.pw1").value = self.new_password
            form.getControl(name="cbid.system._pass.pw2").value = self.new_password
            form.getControl(name="cbi.apply").click()
            self.assertTrue("erfolgreich" in browser.contents,
                    "Passwortaenderung schlug fehl: %s" % self.host)
            login_old_pw = self._login(browser, [self.default_password], force=True)
            self.assertFalse(login_old_pw, "Anmeldung mit altem Passwort " + \
                    "ist immer noch moeglich: %s" % self.host)

    def test_10_transmit_ssh_key(self):
        """ Importiere den lokalen SSH-Schluessel """
        pub_key = self._get_ssh_pub_key()
        for self.host in self.hosts:
            browser = self.host.get_browser("/cgi-bin/luci/admin/system/admin")
            # Anmeldung
            self.assertTrue(self._login(browser),
                    "Anmeldung schlug fehl: %s" % self.host)
            # Schluessel importieren
            form = browser.getForm(name="cbi")
            form.getControl(name="cbid.dropbear._keys._data").value = pub_key
            form.getControl(name="cbi.apply").click()
            self.assertTrue(pub_key in browser.contents,
                    "SSH-Schluessel wurde nicht gespeichert: %s" % self.host)
            # Verbindungsaufbau
            result = self._execute("pwd")
            self.assertTrue(result.success and result.stdout.contains_line("/root"),
                    "Verbindungsaufbau via ssh schlug fehl: %s" % self.host)

    def test_15_on_core_settings(self):
        """ Pruefe die on-core-Einstellungen """
        for self.host in self.hosts:
            result = self._execute("uci show on-core")
            self.assertTrue(result.success and not result.stdout.is_empty(),
                    "Die uci-Einstellungen fuer on-core fehlen: %s" % self.host)
            result = self._execute("grep -qi opennet /etc/banner")
            self.assertTrue(result.success, "Die Datei /etc/banner " + \
                    "enthaelt keinen Text 'opennet': %s" % self.host)

    def test_20_enable_opennet_interfaces(self):
        """ Konfiguriere die Opennet-Netzwerk-Interfaces (nur fuer APs) """
        for self.host in self.hosts:
            if not self.host.get_opennet_ap_id():
                continue
            interface_dict = {
                    "ap1.201": ("eth0", ),
                    "ap1.202": ("eth0", "eth1"),
                    "ap1.203": ("eth0", ),
            }
            # Leider ist es nicht leicht, die javascript-basierte Interface-Auswahl zu simulieren.
            # Also stattdessen der Weg ueber uci.
            for index, iface in enumerate(interface_dict[self.host.name]):
                # alle Netzwerke von diesem Interface trennen
                result = self._execute("uci show network | grep 'ifname=%s$'" % iface)
                for line in result.stdout.lines:
                    key = line.split("=")[0]
                    self._execute("uci set %s=none" % key)
                # olsr-Interface setzen (falls es noch nicht existiert)
                net_name = "on_eth_%d" % index
                result = self._execute("uci set network.%s=interface" % net_name)
                self.assertTrue(result.success,
                        "Anlegen des Interface schlug fehl (%s): %s" % (self. host, result.stderr))
                self._execute("uci set network.%s.ifname=%s" % (net_name, iface))
                self.assertTrue(result.success,
                        "Zuordnen des Interface schlug fehl (%s): %s" % (self. host, result.stderr))
                self._execute("uci commit network.%s" % net_name)
                self.assertTrue(result.success,
                        "Bestaetigung der Interface-Aenderung schlug fehl (%s): %s" % (self. host, result.stderr))
                # Interface zur openvpn-Firewall-Zone hinzufuegen
                fw_opennet_nets = self._execute("uci get firewall.zone_opennet.network").stdout.lines[0].strip().split()
                self.assertTrue(result.success,
                        "Auslesen der Firewall schlug fehl (%s): %s" % (self. host, result.stderr))
                if not net_name in fw_opennet_nets:
                    fw_opennet_nets += net_name
                    self._execute("uci set firewall.zone_opennet.network=%s" % " ".join(fw_opennet_nets))
                    self.assertTrue(result.success,
                            "Aktualisieren der Firewall-Zone schlug fehl (%s): %s" % (self. host, result.stderr))
                    self._execute("uci commit firewall.zone_opennet")
                    self.assertTrue(result.success,
                            "Bestaetigen der Firewall-Aenderung schlug fehl (%s): %s" % (self. host, result.stderr))
                result = self._execute("uci show network | grep -q 'on_eth_.\.ifname=%s$'" % iface)
                # irgendetwas muss ja auch getestet werden ...
                self.assertTrue(result.success,
                        "Das Opennet-Interface wurde nicht via uci erzeugt: %s" % self.host)
            # konfigurieren!
            result = self._execute("/etc/init.d/network restart")
            self.assertTrue(result.success, "Die Netzwerk-Konfiguration schlug fehl (%s): %s" % (self.host, result.stderr))


    def test_25_set_opennet_id(self):
        """ Setze die Opennet-ID (nur fuer APs) """
        for self.host in self.hosts:
            # Opennet-ID festlegen, falls "AP" (laut Namen)
            ap_id = self.host.get_opennet_ap_id()
            if not ap_id:
                continue
            browser = self.host.get_browser("/cgi-bin/luci/opennet/opennet_1/funknetz")
            # Anmeldung
            result = self._login(browser)
            self.assertTrue(self._login(browser),
                    "Anmeldung schlug fehl: %s" % self.host)
            form = browser.getForm(action="/funknetz")
            form.getControl(name="form_id").value = ap_id
            form.submit()
            time.sleep(2)
            # TODO: der erforderliche network-Restart duerfte ein Bug sein
            result = self._execute("/etc/init.d/network restart")
            # verify the new IP
            for attempt in range(8):
                if self._has_ip("192.168.%s" % ap_id):
                    break
                time.sleep(1)
            else:
                # keine passende IP gefunden
                ips = " ".join(self._get_ips(ip_version=4))
                self.assertTrue(False, "Die neue Opennet-IP wurde nicht " + \
                        "konfiguriert. Derzeit sind lediglich folgende IPs " + \
                        "auf %s gesetzt: %s" % (self.host, ips))


if __name__ in ('main', '__main__'):
    import unittest
    loader = lambda cls: unittest.TestLoader().loadTestsFromTestCase(cls)
    suite = loader(BasicSetup)
    unittest.TextTestRunner(verbosity=2).run(suite)

