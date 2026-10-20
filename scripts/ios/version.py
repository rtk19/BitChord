#!/usr/bin/env python3
"""Read the upstream app version without executing its Gradle build."""
from pathlib import Path
import re

source = Path(__file__).resolve().parents[2] / 'build.gradle.kts'
match = re.search(r'extra\["bitchordVersionName"\]\s*=\s*"(\d+\.\d+(?:\.\d+)?)"', source.read_text())
if match is None:
    raise SystemExit('Cannot read upstream version. Update scripts/ios/version.py before releasing.')
print(match.group(1))
