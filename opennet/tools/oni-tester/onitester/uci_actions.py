import re

from onitester.utils import log


def assign_interface_to_network(host, if_name, net_name):
    """ Zuordnung eines physischen Interfaces (z.B. eth) zu einem Netzwerk (z.B. "lan") """
    # alle Netzwerke von diesem Interface trennen
    result = host.execute("uci show network")
    regex = re.compile(r"ifname=%s" % if_name)
    for line in result.stdout.lines:
        if not regex.search(line):
            continue
        key = line.split("=")[0]
        host.execute("uci set %s=none" % key)
    # netzwerk erzeugen
    result = host.execute("uci set network.%s=interface" % net_name)
    if not result.success:
        log.warning("Anlegen des Interface schlug fehl (%s): %s" % (host, result.stderr))
        return False
    host.execute("uci set 'network.%s.ifname=%s'" % (net_name, if_name))
    if not result.success:
        log.warning("Zuordnen des Interface schlug fehl (%s): %s" % (host, result.stderr))
        return False
    host.execute("uci commit network.%s" % net_name)
    if not result.success:
        log.warning("Bestaetigung der Interface-Aenderung schlug fehl (%s): %s" % (host, result.stderr))
        return False
    return True


def assign_network_to_firewall_zone(host, net_name, fw_zone):
    """ Zuordnung eines Netzwerks (z.B. "lan") zu einer Firewall-Zone (z.B. "opennet") """
    # dieses Netzwerk von allen Zonen trennen
    result = host.execute("uci show firewall")
    regex = re.compile(r"^firewall\.zone_[a-z0-9_-]\.network=")
    for line in result.stdout.lines:
        if not regex.search(line):
            continue
        key, value = line.split("=", 1)
        if key == "firewall.zone_%s.network" % fw_zone:
            continue
        interfaces = value.split()
        # Netzwerk in der Zone? Entfernen ...
        if net_name in interfaces:
            while net_name in interfaces:
                interfaces.remove(net_name)
            if not interfaces:
                host.execute("uci del %s" % key)
            else:
                host.execute("uci set '%s=%s'" % (key, " ".join(interfaces)))
            host.execute("uci commit %s" % key)
    # Interface zur openvpn-Firewall-Zone hinzufuegen
    result = host.execute("uci get firewall.zone_%s.network" % fw_zone, quiet=True)
    if result.success and not result.stdout.is_empty():
        fw_zone_nets = result.stdout.lines[0].strip().split()
    else:
        fw_zone_nets = []
    if not net_name in fw_zone_nets:
        fw_zone_nets.append(net_name)
        result = host.execute("uci set 'firewall.zone_%s.network=%s'" % (fw_zone, " ".join(fw_zone_nets)))
        if not result.success:
            log.warning("Aktualisieren der Firewall-Zone schlug fehl (%s): %s" % (host, result.stderr))
            return False
    result = host.execute("uci commit firewall.zone_%s" % fw_zone)
    if not result.success:
        log.warning("Bestaetigen der Firewall-Aenderung schlug fehl (%s): %s" % (host, result.stderr))
        return False
    return True

