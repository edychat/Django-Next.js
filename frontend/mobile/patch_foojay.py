#!/usr/bin/env python3
"""
Patch foojay-resolver-convention to 1.0.0 in a Gradle settings file.
Usage: python3 patch_foojay.py <settings_file>

React Native 0.83 ships foojay-resolver-convention:0.5.0 which crashes on
Gradle 9 with "IBM_SEMERU field not found". Version 1.0.0 (May 2025) fixes it.
"""
import re
import sys

if len(sys.argv) < 2:
    sys.exit(1)

f = sys.argv[1]
try:
    txt = open(f).read()
except OSError:
    sys.exit(1)

# Pattern 1: id("...foojay...").version("x.y.z")
p1 = r'id\("org\.gradle\.toolchains\.foojay-resolver-convention"\)\.version\("[^"]*"\)'
r1 = 'id("org.gradle.toolchains.foojay-resolver-convention").version("1.0.0")'

# Pattern 2: id("...foojay...") version "x.y.z"
p2 = r'id\("org\.gradle\.toolchains\.foojay-resolver-convention"\) version "[^"]*"'
r2 = 'id("org.gradle.toolchains.foojay-resolver-convention") version "1.0.0"'

patched = re.sub(p2, r2, re.sub(p1, r1, txt))
if patched != txt:
    open(f, "w").write(patched)
    sys.exit(0)
sys.exit(0)
