import re

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

    def test_20_set_opennet_id(self):
        """ Setze die Opennet-ID (nur fuer APs) """
        for self.host in self.hosts:
            # Opennet-ID festlegen, falls "AP" (laut Namen)
            ap_regex = r"^ap([0-9]\.[0-9]+)$"
            ap_match = re.search(ap_regex, self.host.name)
            if not ap_match:
                continue
            ap_id = ap_match.groups()[0]
            browser = self.host.get_browser("/cgi-bin/luci/opennet/opennet_1/funknetz")
            # Anmeldung
            result = self._login(browser)
            self.assertTrue(self._login(browser),
                    "Anmeldung schlug fehl: %s" % self.host)
            form = browser.getForm()
            form.getControl(name="form_id").value = ap_id
            form.submit()


if __name__ in ('main', '__main__'):
    import unittest
    loader = lambda cls: unittest.TestLoader().loadTestsFromTestCase(cls)
    suite = loader(BasicSetup)
    unittest.TextTestRunner(verbosity=2).run(suite)

