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
    new_password = "oni-admin"
    default_password = "admin"

    def _get_ips(self, ip_version=4, with_mask=False):
        regexes = {
                4: r" inet ([0-9.]{7,15}/[0-9]+) ",
                6: r" inet ([0-9a-f:]{7,15}/[0-9]+) ",
        }
        result = self._execute("ip -%d addr show" % ip_version)
        if not result.success:
            return []
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

