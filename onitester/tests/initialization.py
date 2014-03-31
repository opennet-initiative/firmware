# -*- coding: utf-8 -*-

import onitester.uci_actions
from onitester.tests._common import OpennetTest


class BasicSetup(OpennetTest):
    """ Grundlegende Konfiguration der Router """

    def test_01_connect(self):
        """ Pruefe die Erreichbarkeit """
        for host in self.get_hosts():
            host.open_url("/")
            self.assertIsNotNone(host.browser, "Keine Verbindung mit Host %s" % host)
            self.assertTrue("Opennet" in host.browser.contents,
                    "Kein 'OpenWrt'-Webinterface gefunden: %s" % host)
            self.assertTrue("Graphen" in host.browser.contents,
                    "Keine deutschsprachige Web-Oberflaeche: %s" % host)

    def test_05_password(self):
        """ Setze das root-Passwort """
        for host in self.get_hosts():
            host.open_url("/cgi-bin/luci/admin/system/admin")
            self.assertTrue(host.web_login(),
                    "Anmeldung schlug fehl: %s" % host)
            form = host.browser.getForm(name="cbi")
            form.getControl(name="cbid.system._pass.pw1").value = self.new_password
            form.getControl(name="cbid.system._pass.pw2").value = self.new_password
            form.getControl(name="cbi.apply").click()
            self.assertTrue("erfolgreich" in host.browser.contents,
                    "Passwortaenderung schlug fehl: %s" % host)
            login_old_pw = host.web_login([self.default_password], force=True)
            self.assertFalse(login_old_pw, "Anmeldung mit altem Passwort " + \
                    "ist immer noch moeglich: %s" % host)

    def test_10_transmit_ssh_key(self):
        """ Importiere den lokalen SSH-Schluessel """
        for host in self.get_hosts():
            pub_key = host._get_ssh_pub_key()
            host.open_url("/cgi-bin/luci/admin/system/admin")
            # Anmeldung
            self.assertTrue(host.web_login(),
                    "Anmeldung schlug fehl: %s" % host)
            # Schluessel importieren
            form = host.browser.getForm(name="cbi")
            form.getControl(name="cbid.dropbear._keys._data").value = pub_key
            form.getControl(name="cbi.apply").click()
            self.assertTrue(pub_key in host.browser.contents,
                    "SSH-Schluessel wurde nicht gespeichert: %s" % host)
            # Verbindungsaufbau
            result = host.execute("pwd")
            self.assertTrue(result.success and result.stdout.contains_line("/root"),
                    "Verbindungsaufbau via ssh schlug fehl: %s" % host)

    def test_15_configure_lan_wan(self):
        """ Konfigurieren von LAN- und WAN-Schnittstellen """
        for host in self.get_hosts():
            for if_name, net in host.networks.iteritems():
                if not net.traffic in ("local", "wan"):
                    continue
                success = onitester.uci_actions.assign_interface_to_network(host, if_name, net.name)
                self.assertTrue(success,
                        "Das opennet-Interface '%s' wurde nicht zum %s-Netzwerk hinzugefügt (Host %s)" % (if_name, net.traffic, host))
                success = onitester.uci_actions.assign_network_to_firewall_zone(host, net.name, net.traffic)
                zone = {"lan": "local", "wan": "wan"}[net.traffic]
                self.assertTrue(success,
                        "Das Netzwerk '%s' wurde nicht zur %s-Firewall-Zone hinzugefügt (Host %s)" % (net.name, zone, host))

