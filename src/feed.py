# SPDX-License-Identifier: MIT
"""Serialize a native Zero Install feed for a content-addressed implementation."""
import json
from pathlib import Path
import sys
from xml.etree.ElementTree import Element, SubElement, ElementTree, register_namespace

root = Path(sys.argv[1])
spec = json.loads(Path(sys.argv[2]).read_text())
namespace = 'http://zero-install.sourceforge.net/2004/injector/interface'
register_namespace('', namespace)
def tag(name):
    return '{' + namespace + '}' + name
feed = Element(tag('interface'))
SubElement(feed, tag('name')).text = spec['name']
SubElement(feed, tag('summary')).text = spec['description']
implementation = SubElement(feed, tag('implementation'), {
    'id': root.joinpath('digest').read_text().strip(),
    'version': spec['version'], 'arch': spec['architecture'],
    'released': '2026-11-02', 'stability': 'stable',
})
algorithm, digest = root.joinpath('digest').read_text().strip().split('_', 1)
SubElement(implementation, tag('manifest-digest'), {algorithm: digest})
for dependency in spec.get('dependencies', []):
    requirement = SubElement(implementation, tag('requires'), {'interface': dependency['interface']})
    SubElement(requirement, tag('executable-in-path'), {'name': dependency['executable'], 'command': dependency.get('command', 'run')})
SubElement(implementation, tag('command'), {'name': 'run', 'path': spec['command']})
SubElement(implementation, tag('archive'), {
    'href': spec.get('archiveURL') or 'implementation.tar.gz',
    'size': str(root.joinpath('implementation.tar.gz').stat().st_size),
    'type': 'application/x-compressed-tar',
})
ElementTree(feed).write(root / 'feed.xml', encoding='utf-8', xml_declaration=True)
