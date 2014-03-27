import time
import os
import re
import unittest
import paramiko


class OpennetTest(unittest.TestCase):
    """ Basisklasse fuer alle Opennet-relevanten Tests
    Hier koennen spezifische Einstellungen (Passwort) und Funktionen
    untergebracht werden.
    """

    username = "root"
    default_password = "admin"
    new_password = "oni-admin"
    auth_token_regex = r"(/luci/;stok=[0-9a-z]+/)"

    def _is_auth_needed(self, browser):
        return "Benutzernamen und Passwort" in browser.contents

    def _login(self, browser, passwords=None, force=False):
        if passwords is None:
            passwords = (self.default_password, self.new_password)
        if not self._is_auth_needed(browser):
            if not force:
                return True
            else:
                browser.open("/cgi-bin/luci/admin/logout")
        for password in passwords:
            form = browser.getForm()
            form.getControl(name="username").value = self.username
            form.getControl(name="password").value = password
            form.getControl(label="Anmelden").click()
            if not self._is_auth_needed(browser):
                return True
        else:
            return False

    def open_link(self, browser, url):
        """ Oeffne eine neue URL unter Beibehaltung des luci-auth-Tokens
        Beispiel-URL: http://172.16.137.11/cgi-bin/luci/;stok=1c50965d5a99cc47c507cc4e5cd207ed/opennet/opennet_2/
        """
        token_match = re.search(self.auth_token_regex, browser.url)
        if token_match:
            token = token_match.groups()[0]
            url.replace("/luci/", token)
        browser.open(url)

    def _get_ips(self, ip_version=4, with_mask=False):
        regexes = {
                4: r" inet ([0-9.]{7,15}/[0-9]+) ",
                6: r" inet ([0-9a-f:]{7,15}/[0-9]+) ",
        }
        result = self._execute("ip -%d addr show" % ip_version)
        if not result.success:
            return []
        #ips = re.findall(regexes[ip_version], " ".join(result.stdout.lines).lower())
        ips = re.findall(regexes[ip_version], str(result.stdout).lower())
        if ips:
            if with_mask:
                return ips
            else:
                return [ip.split("/")[0] for ip in ips]
        else:
            return []

    def _has_ip(self, ip):
        with_mask = "/" in ip
        ip_version = 4 if "." in ip else 6
        return ip in self._get_ips(ip_version=ip_version, with_mask=with_mask)

    def tearDown(self):
        client = self._get_ssh_client(auto_create=False)
        if client:
            client.close()

