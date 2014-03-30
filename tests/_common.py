import os
import re
import unittest
import paramiko

import onitester.scenario_config


BASE_DIR = os.path.abspath(os.path.join(os.path.dirname(os.path.realpath(__file__)), os.path.pardir))

__host_cache = {}


def _get_hosts_from_configfiles(host_config_file=None, network_config_file=None):
    global __host_cache
    if host_config_file is None:
        host_config_file = os.environ.get("HOST_CONFIG_FILE", os.path.join(BASE_DIR, "setup.d", "hosts.conf"))
    if network_config_file is None:
        network_config_file = os.environ.get("HOST_CONFIG_FILE", os.path.join(BASE_DIR, "setup.d", "nets.conf"))
    cache_key = tuple((host_config_file, network_config_file))
    if not cache_key in __host_cache:
        env = onitester.scenario_config.parse_environment(host_config_file, network_config_file)
        __host_cache[cache_key] = tuple(env.hosts.values())
    return __host_cache[cache_key]


class OpennetTest(unittest.TestCase):
    """ Basisklasse fuer alle Opennet-relevanten Tests
    Hier koennen spezifische Einstellungen (Passwort) und Funktionen
    untergebracht werden.
    """

    username = "root"
    new_password = "oni-admin"
    default_password = "admin"

    def _get_ips(self, host, ip_version=4, with_mask=False):
        regexes = {
                4: r" inet ([0-9.]{7,15}/[0-9]+) ",
                6: r" inet ([0-9a-f:]{7,15}/[0-9]+) ",
        }
        result = host.execute("ip -%d addr show" % ip_version)
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

    def _has_ip(self, host, ip):
        with_mask = "/" in ip
        ip_version = 4 if "." in ip else 6
        return ip in self._get_ips(host, ip_version=ip_version, with_mask=with_mask)

    def get_hosts(self):
        for host in _get_hosts_from_configfiles():
            host.default_login_passwords = (self.new_password, self.default_password)
            yield host

