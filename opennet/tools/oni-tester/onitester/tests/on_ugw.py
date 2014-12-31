# -*- coding: utf-8 -*-

import onitester.uci_actions
from onitester.tests._common import OpennetTest

UGW_HOST = "ap1.201"


def copy_ugw_certs(host):
    for file_ext in ("crt", "csr", "key"):
        fname = "etc/openvpn/opennet_ugw/on_ugws.%s" % file_ext
        host.copy_file(fname, "/%s" % fname)


class OnUGW(OpennetTest):

    def test_10_uplink_dns(self):
        host = self.get_hosts()[UGW_HOST]
        # pruefe DNS-Verfuegbarkeit von Opennet-Hosts mit einem WAN-Interface
        # Nutzer-Hosts werden erstmal ignoriert
        result = host.get_dns_answers("on-i.de")
        self.assertTrue("46.4.52.124" in result,
                "DNS-Aufloesung von 'on-i.de' liefert ein unerwartetes Ergebnis auf Host %s: %s" % (host, result))

    def test_20_ugw_connection(self):
        host = self.get_hosts()[UGW_HOST]
        copy_ugw_certs(host)
        host.execute("/usr/sbin/on_usergateway")

