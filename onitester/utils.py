import sys
import ipcalc


def paramiko_shell(chan):
    import socket
    import termios
    import tty
    import select
    oldtty = termios.tcgetattr(sys.stdin)
    try:
        tty.setraw(sys.stdin.fileno())
        tty.setcbreak(sys.stdin.fileno())
        chan.settimeout(0.0)
        while True:
            r, w, e = select.select([chan, sys.stdin], [], [])
            if chan in r:
                try:
                    x = chan.recv(1024)
                    if len(x) == 0:
                        print '%s*** EOF ***' % os.linesep
                        break
                    sys.stdout.write(x)
                    sys.stdout.flush()
                except socket.timeout:
                    pass
            if sys.stdin in r:
                x = sys.stdin.read(1)
                if len(x) == 0:
                    break
                chan.send(x)
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

    def __init__(self, exit_code, stdout_obj, stderr_obj):
        self.exit_code = exit_code
        self.success = self.exit_code == 0
        self.stdout = TextResult(stdout_obj)
        self.stderr = TextResult(stderr_obj)

    def __contains__(self, text):
        return text in self.stdout

    def __str__(self):
        return "ExecResult(stdout_bytes=%d, stderr='%s', exit_code=%d)" % \
                (len(str(self.stdout)), self.stderr, self.exit_code)

