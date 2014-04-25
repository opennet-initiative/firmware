#!/usr/bin/env python

import os
import sys

BASE_DIR = os.path.abspath(os.path.join(os.path.dirname(os.path.realpath(__file__)), os.path.pardir))
sys.path.insert(0, BASE_DIR)

import onitester.tests.initialization
import onitester.tests.on_core


if __name__ in ('main', '__main__'):
    import unittest
    loader = lambda cls: unittest.TestLoader().loadTestsFromTestCase(cls)
    suites = []
    suites += loader(onitester.tests.initialization.BasicSetup)
    suites += loader(onitester.tests.on_core.OnCore)
    suites += loader(onitester.tests.on_ugw.OnUGW)
    all_tests = unittest.TestSuite(suites)
    unittest.TextTestRunner(verbosity=2).run(all_tests)

