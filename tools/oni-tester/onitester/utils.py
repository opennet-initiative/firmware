import os
import sys
import ipcalc
import logging


logging.basicConfig()
log = logging


def paramiko_shell(chan):
    """ Diese Funktion ist noch nicht wirklich nutzbar. Irgendwie laeuft der Terminal nicht."""
    import socket
    import termios
    import tty
    import select
    def transmit_bytes():
        try:
            x = chan.recv(1024)
            if len(x) == 0:
                print '%s*** EOF ***' % os.linesep
                return False
            sys.stdout.write(x)
            sys.stdout.flush()
        except socket.timeout:
            pass
        return True
    def receive_bytes():
        x = os.read(sys.stdin.fileno(), 1)
        if len(x) == 0:
            return False
        chan.send(x)
        return True
    oldtty = termios.tcgetattr(sys.stdin)
    try:
        tty.setraw(sys.stdin.fileno())
        tty.setcbreak(sys.stdin.fileno())
        chan.settimeout(0.0)
        while True:
            r, w, e = select.select([chan, sys.stdin], [], [])
            if chan in r and not transmit_bytes():
                break
            if sys.stdin in r and not receive_bytes():
                break
    finally:
        termios.tcsetattr(sys.stdin, termios.TCSADRAIN, oldtty)


def parse_ip(ip_string):
    ip = ipcalc.Network(ip_string)
    address = str(ip.to_ipv4())
    netmask = str(ip.netmask())
    return address, netmask


class TextResult(object):

    def __init__(self, file_obj):
        self.lines = []
        while True:
            line = file_obj.readline()
            if not line:
                break
            # Zeilenumbruch entfernen
            self.lines.append(line[:-1])

    def is_empty(self):
        return len(self.lines) == 0

    def contains(self, token):
        for line in self.lines:
            if token in line:
                return True
        return False

    def contains_line(self, line):
        return line in self.lines

    def __contains__(self, text):
        return self.contains(text)

    def __str__(self):
        return os.linesep.join(self.lines)


class ExecResult(object):

    def __init__(self, cmdline, exit_code, stdout_obj, stderr_obj, quiet=False):
        self.exit_code = exit_code
        self.success = self.exit_code == 0
        self.stdout = TextResult(stdout_obj)
        self.stderr = TextResult(stderr_obj)
        if quiet:
            # inhibit error handling
            pass
        elif not self.stderr.is_empty():
            # success with error output
            if self.success:
                prefix = "Warning"
                reporter = log.warning
            else:
                prefix = "Error"
                reporter = log.error
            reporter("%s: command execution ('%s') error output: %s" % (prefix, cmdline, self.stderr))
        elif not self.success:
            # failure without error output
            log.error("Command ('%s') failed with exitcode %d" % (cmdline, self.exit_code))
        else:
            # everything went fine
            pass

    def __contains__(self, text):
        return text in self.stdout

    def __str__(self):
        return "ExecResult(stdout_bytes=%d, stderr='%s', exit_code=%d)" % \
                (len(str(self.stdout)), self.stderr, self.exit_code)

