#!/usr/bin/env python3
"""Extract one version's section from CHANGELOG.md, for use as GitHub
Release notes / the Teams notification body.

Usage: extract_changelog.py 1.0.0 > release_notes.md
"""
import re
import sys


def main():
    if len(sys.argv) != 2:
        print("Usage: extract_changelog.py <version>", file=sys.stderr)
        sys.exit(1)

    version = sys.argv[1]
    text = open("CHANGELOG.md", encoding="utf-8").read()
    pattern = rf"^## \[{re.escape(version)}\][^\n]*\n(.*?)(?=\n## \[|\Z)"
    match = re.search(pattern, text, re.S | re.M)
    if not match:
        print(f"_No CHANGELOG.md entry found for version {version}._")
        return
    print(match.group(1).strip())


if __name__ == "__main__":
    main()
