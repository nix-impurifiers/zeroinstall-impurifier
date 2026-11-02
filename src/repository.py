# SPDX-License-Identifier: MIT
"""Combine native implementation feeds without introducing mutable IDs."""
from pathlib import Path
import shutil
import sys
from xml.etree.ElementTree import ElementTree, parse, register_namespace

namespace = 'http://zero-install.sourceforge.net/2004/injector/interface'
register_namespace('', namespace)
root = None
versions = set()
output = Path(sys.argv[1])
output.mkdir(exist_ok=True)
base_url = sys.argv[2].rstrip('/')
for source in map(Path, sys.argv[3:]):
    feed = parse(source / 'feed.xml').getroot()
    if root is None:
        root = feed
        for implementation in root.findall('{' + namespace + '}implementation'):
            root.remove(implementation)
    if feed.find('{' + namespace + '}name').text != root.find('{' + namespace + '}name').text:
        raise ValueError('repository feeds must describe one application')
    implementation = feed.find('{' + namespace + '}implementation')
    # The first tree's nodes were detached above.
    if implementation is None:
        implementation = parse(source / 'feed.xml').getroot().find('{' + namespace + '}implementation')
    version = implementation.attrib['version']
    if version in versions:
        raise ValueError('select one transport artifact per application version')
    versions.add(version)
    archive = implementation.find('{' + namespace + '}archive')
    filename = implementation.attrib['id'] + '.tar.gz'
    shutil.copyfile(source / 'implementation.tar.gz', output / filename)
    archive.set('href', base_url + '/' + filename if base_url else filename)
    root.append(implementation)
if root is None:
    raise ValueError('repository needs at least one feed')
ElementTree(root).write(output / 'feed.xml', encoding='utf-8', xml_declaration=True)
