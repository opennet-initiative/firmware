#!/usr/bin/env python

import os
import sys
import argparse


BASE_DIR = os.path.abspath(os.path.join(os.path.dirname(os.path.realpath(__file__)), os.path.pardir))
sys.path.insert(0, BASE_DIR)

import onitester.scenario_config


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Verwaltung von Hosts und Netzwerken")
    main_group = parser.add_argument_group("Allgemeines", "Allgemeine Aktionen")
    main_group.add_argument("action", metavar="action", type=str, nargs="?",
                            default="status",
                            choices=("start", "stop", "restart", "wait", "status", "vnc", "ssh", "show-uplink"),
                            help="Starten und Beenden der Testumgebung")
    main_group.add_argument("extra_args", nargs="*", default=[])
    main_group.add_argument("--host-config", type=argparse.FileType("r"),
                            default="setup.d/hosts.conf", dest="host_config",
                            help="Name der Host-Konfigurationsdatei")
    main_group.add_argument("--net-config", type=argparse.FileType("r"),
                            default="setup.d/nets.conf", dest="net_config",
                            help="Name der Netzwerk-Konfigurationsdatei")
    args = parser.parse_args()
    env = onitester.scenario_config.parse_environment(args.host_config, args.net_config)
    if args.action in ("stop", "restart"):
        env.stop()
    elif args.action in ("start", "restart"):
        env.start()
    elif args.action == "status":
        env.status()
    elif args.action == "show-uplink":
        print onitester.scenario_config.get_uplink_interface()
    elif args.action == "wait":
        if args.extra_args:
            for hostname in args.extra_args:
                env.hosts[hostname].wait()
        else:
            for host in env.hosts.values():
                host.wait()
    elif args.action in ("ssh", "vnc"):
        if not args.extra_args:
            print >>sys.stderr, "Kein Host-Name angegeben"
            sys.exit(1)
        hostname = args.extra_args[0]
        if not hostname in env.hosts:
            print >>sys.stderr, "Unbekannter Host-Name: %s" % hostname
            sys.exit(1)
        host = env.hosts[hostname]
        if args.action == "ssh":
            params = args.extra_args[1:]
            if params:
                result = host.execute(" ".join(params))
                if result.success:
                    print result.stdout
                else:
                    print >>sys.stderr, result.stderr
                    sys.exit(3)
            else:
                host.run_ssh()
        elif args.action == "vnc":
            host.run_vnc()
    else:
        print >>sys.stderr, "Unbekannte Aktion: %s" % args.action

