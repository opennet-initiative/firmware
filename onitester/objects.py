import os
import sys
import paramiko
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
        self.start = CommandQueue()
        self.stop = CommandQueue()


class Host(object):

    username = "root"


    def __init__(self, name, ip, run_dir):
        self.name = name
        self.address, self.netmask = onitester.utils.parse_ip(ip)
        self._run_dir = run_dir
        self._url_prefix = "http://%s/" % self.address
        self.start = CommandQueue()
        self.stop = CommandQueue()
        self.wait = CommandQueue()

    def get_browser(self, url=None):
        if url is None:
            url = self.get_url()
        elif url.startswith("/"):
            url = self.get_url(url)
        try:
            browser = Browser()
            # verwende deutschsprachiges Interface
            browser.addHeader("Accept-Language", "de-DE,de")
            browser.open(url)
            return browser
        except IOError:
            return None

    def get_url(self, path=""):
        return "%s/%s" % (self._url_prefix.rstrip("/"), path.lstrip("/"))

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

