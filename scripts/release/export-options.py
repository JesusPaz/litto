#!/usr/bin/env python3
"""ExportOptions.plist for mac (Developer ID), macstore (Mac App Store) or ios (App Store / TestFlight).
Usage: export-options.py mac|macstore|ios upload|export OUT [--internal]
--internal limits an iPhone upload to internal TestFlight testers; such builds cannot go to App Review."""
import plistlib
import sys

args = [a for a in sys.argv[1:] if a != '--internal']
internal = '--internal' in sys.argv[1:]
mode, destination, output = args
assert mode in ('mac', 'macstore', 'ios') and destination in ('upload', 'export')
options = dict(method='developer-id' if mode == 'mac' else 'app-store-connect', destination=destination,
               signingStyle='automatic', teamID='Y76K9N6M4R', manageAppVersionAndBuildNumber=False)
if mode == 'ios':
    options.update(testFlightInternalTestingOnly=internal, uploadSymbols=True)
if mode == 'macstore':
    options.update(uploadSymbols=True)
with open(output, 'wb') as f:
    plistlib.dump(options, f)
