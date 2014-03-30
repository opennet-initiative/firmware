import os
import re
import sys
import time
import paramiko
import mechanize
from zope.testbrowser.browser import Browser

import onitester.utils


class CommandQueue(list):

    def __call__(self, force=True):
        result = True
        for command in self:
            result = bool(command()) and result
            if not result and not force:
                print >>sys.stderr, "CommandQueue: nicht alle Kommandos wurden ausgefuehrt"
                return False
        return result


class Environment(object):

    def __init__(self):
        self.hosts = {}
        self.nets = {}
        self.status = CommandQueue()

    def start(self):
        for item in self.nets.values() + self.hosts.values():
            item.start()

    def stop(self):
        for item in self.hosts.values() + self.nets.values():
            item.stop()


class Network(object):

    def __init__(self, name):
        self.name = name
        self.address = None
        self.netmask = None
        self.start = CommandQueue()
        self.stop = CommandQueue()

    def set_ip(self, ip):
        self.address, self.netmask = onitester.utils.parse_ip(ip)


class Host(object):

    username = "root"
    auth_token_regex = r"(/luci/;stok=[0-9a-z]+/)"
    default_password = "admin"

    def __init__(self, name, ip, run_dir):
        self.name = name
        self.address, self.netmask = onitester.utils.parse_ip(ip)
        self._run_dir = run_dir
        self._url_prefix = "http://%s/" % self.address
        self.networks = {}
        self.default_login_passwords = [self.default_password]
        self.browser = self.__get_browser()
        self.start = CommandQueue()
        self.stop = CommandQueue()
        self.wait = CommandQueue()

    def __get_browser(self, url=None):
        browser = Browser()
        # verwende deutschsprachiges Interface
        browser.addHeader("Accept-Language", "de-DE,de")
        return browser

    def _get_url(self, path=""):
        return "%s/%s" % (self._url_prefix.rstrip("/"), path.lstrip("/"))

    def _is_auth_needed(self):
        try:
            return "Benutzernamen und Passwort" in self.browser.contents
        except mechanize.BrowserStateError:
            return True

    def __del__(self):
        client = self._get_ssh_client(auto_create=False)
        if client:
            client.close()

    def open_url(self, url):
        """ Oeffne eine neue URL unter Beibehaltung des luci-auth-Tokens
        Beispiel-URL: http://172.16.137.11/cgi-bin/luci/;stok=1c50965d5a99cc47c507cc4e5cd207ed/opennet/opennet_2/
        """
        try:
            token_match = re.search(self.auth_token_regex, self.browser.url)
        except mechanize.BrowserStateError:
            token_match = None
            # erste Verbindung oeffnen
            self.browser.open(self._get_url("/"))
        if token_match:
            token = token_match.groups()[0]
            url.replace("/luci/", token)
        self.browser.open(url)

    def import_ssh_key(self):
        pub_key = self._get_ssh_pub_key()
        self.open_url("/cgi-bin/luci/admin/system/admin")
        assert self.web_login(), "Anmeldung schlug fehl: %s" % self.host
        # Schluessel importieren
        form = self.browser.getForm(name="cbi")
        form.getControl(name="cbid.dropbear._keys._data").value = pub_key
        form.getControl(name="cbi.apply").click()
        assert pub_key in self.browser.contents, \
                "SSH-Schluessel wurde nicht gespeichert: %s" % self
        # Verbindungsaufbau
        result = self.execute("pwd")
        assert result.success and result.stdout.contains_line("/root"), \
                "Verbindungsaufbau via ssh schlug fehl: %s" % self.host

    def web_login(self, passwords=None, force=False):
        if passwords is None:
            passwords = self.default_login_passwords
        if not self._is_auth_needed():
            if not force:
                return True
            else:
                self.browser.open("/cgi-bin/luci/admin/logout")
        for password in passwords:
            form = self.browser.getForm()
            form.getControl(name="username").value = self.username
            form.getControl(name="password").value = password
            form.getControl(label="Anmelden").click()
            if not self._is_auth_needed():
                return True
        else:
            return False

    def __str__(self):
        return "%s<%s>" % (self.name, self.address)

    def _get_ssh_key_filename(self, public=True):
        suffix = "pub" if public else "sec"
        return os.path.join(self._run_dir, "ssh_key.%s" % suffix)

    def _get_ssh_pub_key(self):
        keyfile_secret = self._get_ssh_key_filename(public=False)
        keyfile_public = self._get_ssh_key_filename(public=True)
        if not os.path.exists(keyfile_secret) or not os.path.exists(keyfile_public):
            key = paramiko.RSAKey.generate(4096)
            key.write_private_key_file(keyfile_secret)
            file(keyfile_public, "w").write("ssh-rsa " + key.get_base64())
        return file(keyfile_public, "r").read()

    def _get_ssh_client(self, auto_create=True):
        if not getattr(self, "_ssh_clients", None):
            self._ssh_clients = {}
        if self.address in self._ssh_clients:
            return self._ssh_clients[self.address]
        if not auto_create:
            return None
        client = paramiko.SSHClient()
        sec_keyfile = self._get_ssh_key_filename(public=False)
        if not os.path.exists(sec_keyfile):
            # trigger a key generation
            self._get_ssh_pub_key()
        # die Schluessel der virtualisierten APs sind uns egal
        class IgnoreKeysPolicy(paramiko.MissingHostKeyPolicy):
            missing_host_key = lambda *args: True
        client.set_missing_host_key_policy(IgnoreKeysPolicy())
        # Verbindungsaufbau
        client.connect(self.address, username=self.username,
                key_filename=[sec_keyfile], allow_agent=False,
                look_for_keys=False)
        self._ssh_clients[self.address] = client
        return client

    def execute(self, command, input_data=None):
        client = self._get_ssh_client()
        transport = client.get_transport()
        channel = transport.open_channel("session")
        channel.exec_command(command)
        while input_data:
            count = channel.send(input_data)
            if count > 0:
                input_data = input_data[count:]
        while not channel.exit_status_ready():
            time.sleep(0.1)
        return onitester.utils.ExecResult(channel.recv_exit_status(), channel.makefile(),
                channel.makefile_stderr())

    def run_ssh(self):
        client = self._get_ssh_client()
        transport = client.get_transport()
        channel = transport.open_channel("session")
        onitester.utils.paramiko_shell(channel)

