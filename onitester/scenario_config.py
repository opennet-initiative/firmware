import os
import re
import sys
import ConfigParser
import subprocess

import onitester.objects


BASE_DIR = os.path.abspath(os.path.join(os.path.dirname(os.path.realpath(__file__)), os.path.pardir))
CTL_BIN = os.path.join(BASE_DIR, "bin", "te-control.sh")


def get_uplink_interface():
    """ ermittle das Netzwerk-Interface auf das die default-Route verweist """
    output = subprocess.check_output(["ip", "route", "get", "1.1.1.1"])
    first_line = output.splitlines()[0]
    regex = r" dev ([^ ]+) "
    match = re.search(regex, first_line)
    if match:
        return match.groups()[0]
    else:
        return None


def get_ctl_func(*args):
    return lambda: subprocess.check_output([CTL_BIN] + list(args))


def __get_config_file_parser(config_file):
    parser = ConfigParser.SafeConfigParser()
    if isinstance(config_file, basestring):
        parser.read(config_file)
        filename = config_file
    else:
        parser.readfp(config_file)
        filename = config_file.name
    return parser, filename


def parse_environment(host_config, net_config):
    environment = onitester.objects.Environment()
    parse_nets(net_config, environment)
    parse_hosts(host_config, environment)
    def show_status():
        print get_ctl_func("status")().strip()
    environment.status.append(show_status)
    return environment


def parse_hosts(config_file, environment):
    parser, filename = __get_config_file_parser(config_file)
    hosts = {}
    for host_name in parser.sections():
        arch = parser.get(host_name, "arch", "x86")
        version = parser.get(host_name, "version")
        try:
            management_ip = parser.get(host_name, "management_ip")
        except ConfigParser.NoOptionError:
            management_ip = None
        run_dir = os.path.join(BASE_DIR, "run", "host", host_name)
        host = onitester.objects.Host(host_name, management_ip, run_dir)
        try:
            management_network = parser.get(host_name, "management_network")
        except ConfigParser.NoOptionError:
            management_network = None
        management_network_index = None
        net_items = []
        try:
            network_string = parser.get(host_name, "networks")
        except ConfigParser.NoOptionError:
            network_string = ""
        network_interfaces = []
        for index, net in enumerate(network_string.split()):
            if len(net.split("/")) == 2:
                net_name, interface_mac = net.split("/")
                role = None
            elif len(net.split("/")) == 3:
                net_name, interface_mac, role = net.split("/")
            else:
                print >>sys.stderr, "Fehler in Konfigurationsdatei " + \
                        "'%s': fehlerhafte Netzwerk-Definition (name/MAC) fuer Host '%s': %s" % \
                        (filename, host_name, net)
                sys.exit(1)
            if not net_name in environment.nets:
                print >>sys.stderr, "Fehler in Konfigurationsdatei " + \
                        "'%s': unbekannter Netzwerk-Name bei Host '%s': %s" % \
                        (filename, host_name, net)
                sys.exit(1)
            net_items.extend([net_name, interface_mac])
            if net_name == management_network:
                management_network_index = index
            interface = onitester.objects.NetworkInterface(host,
                    "eth%d" % index, environment.nets[net_name], role)
            host.interfaces[interface.name] = interface
        try:
            host.ap_id = parser.get(host_name, "ap_id")
        except ConfigParser.NoOptionError:
            host.ap_id = None
        host.start.append(get_ctl_func("start-host", host_name, version, arch, *net_items))
        host.stop.append(get_ctl_func("stop-host", host_name))
        host.wait.append(get_ctl_func("wait-host-boot", host_name, "30"))
        if management_ip:
            if management_network_index is None:
                print >>sys.stderr, "Fehler in Konfigurationsdatei " + \
                        "'%s': Management-Netzwerk ('%s') in Host '%s' nicht gefunden" % \
                        (filename, management_network, host_name)
                sys.exit(1)
            address, netmask = onitester.utils.parse_ip(management_ip)
            host.wait.append(get_ctl_func("host-configure-management",
                    host_name, "eth%d" % management_network_index, address, netmask))
        host.run_vnc = get_ctl_func("vnc", host_name)
        environment.hosts[host_name] = host


def parse_nets(config_file, environment):
    parser, filename = __get_config_file_parser(config_file)
    for net_name in parser.sections():
        if not parser.has_option(net_name, "type"):
            print >>sys.stderr, "Fehler in Konfigurationsdatei " + \
                    "'%s': fehlende Typendefinition fuer Netz '%s'" % \
                    (filename, net_name)
            sys.exit(1)
        net_type = parser.get(net_name, "type").lower().strip()
        net = onitester.objects.Network(net_name)
        if net_type == "switch":
            net.start.append(get_ctl_func("start-net", net_name, "switch"))
        elif net_type == "capture":
            capture_interface = parser.get(net_name, "interface", get_uplink_interface())
            net.start.append(get_ctl_func("start-net", net_name, "switch"))
            net.start.append(get_ctl_func("start-net", net_name, "capture", capture_interface))
        elif net_type == "virtual":
            try:
                local_ip = parser.get(net_name, "local_ip")
            except ConfigParser.NoOptionError:
                print >>sys.stderr, "Fehler in Konfigurationsdatei " + \
                        "'%s': fehlende 'local_ip' fuer virtuelles Netz '%s'" % \
                        (filename, net_name)
                sys.exit(1)
            address, netmask = onitester.utils.parse_ip(local_ip)
            net.start.append(get_ctl_func("start-net", net_name, "virtual", address, netmask))
        else:
            print >>sys.stderr, "Fehler in Konfigurationsdatei " + \
                    "'%s': unbekannte Typendefinition fuer Netz '%s': %s" % \
                    (filename, net_name, net["type"])
            sys.exit(1)
        net.stop.append(get_ctl_func("stop-net", net_name))
        environment.nets[net_name] = net

