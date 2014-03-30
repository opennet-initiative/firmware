#!/usr/bin/env python

import os
import sys

BASE_DIR = os.path.abspath(os.path.join(os.path.dirname(os.path.realpath(__file__)), os.path.pardir))
sys.path.insert(0, BASE_DIR)
sys.path.insert(0, os.path.join(BASE_DIR, "tests"))

import initialization


if __name__ in ('main', '__main__'):
    import unittest
    loader = lambda cls: unittest.TestLoader().loadTestsFromTestCase(cls)
    suite = loader(initialization.BasicSetup)
    unittest.TextTestRunner(verbosity=2).run(suite)

