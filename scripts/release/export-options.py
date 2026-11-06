#!/usr/bin/env python3
"""ExportOptions.plist for mac (Developer ID) or ios (TestFlight). Usage: export-options.py mac|ios upload|export OUT"""
import plistlib
import sys

mode, destination, output = sys.argv[1:]
assert mode in ('mac', 'ios') and destination in ('upload', 'export')
options = dict(method='developer-id' if mode == 'mac' else 'app-store-connect', destination=destination,
               signingStyle='automatic', teamID='Y76K9N6M4R', manageAppVersionAndBuildNumber=False)
if mode == 'ios':
    options.update(testFlightInternalTestingOnly=True, uploadSymbols=True)
with open(output, 'wb') as f:
    plistlib.dump(options, f)
