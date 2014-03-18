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
            url = "/cgi-bin/luci/admin/system/admin"
            browser = self.host.get_browser(url)
            self.assertTrue(self._login(browser),
                    "Anmeldung schlug fehl: %s" % self.host)
            form = browser.getForm(name="cbi")
            form.getControl(name="cbid.system._pass.pw1").value = self.new_password
            form.getControl(name="cbid.system._pass.pw2").value = self.new_password
            form.submit(name="cbi.apply")
            self.assertTrue("erfolgreich" in browser.contents,
                    "Passwortaenderung schlug fehl: %s" % self.host)

    def test_10_transmit_ssh_key(self):
        """ Importiere den lokalen SSH-Schluessel """
        pub_key = self._get_ssh_pub_key()
        for self.host in self.hosts:
            url = "/cgi-bin/luci/admin/system/admin"
            browser = self.host.get_browser(url)
            # Anmeldung
            self.assertTrue(self._login(browser),
                    "Anmeldung schlug fehl: %s" % self.host)
            # Schluessel importieren
            form = browser.getForm(name="cbi")
            form.getControl(name="cbid.dropbear._keys._data").value = pub_key
            form.submit(name="cbi.apply")
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


if __name__ in ('main', '__main__'):
    import unittest
    loader = lambda cls: unittest.TestLoader().loadTestsFromTestCase(cls)
    suite = loader(BasicSetup)
    unittest.TextTestRunner(verbosity=2).run(suite)

