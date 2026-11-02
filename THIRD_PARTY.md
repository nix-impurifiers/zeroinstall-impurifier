# Third-party software

Original emitter, launcher, preparation helper, cache-root integration, and tests
are MIT licensed. The shared `impurifier` engine is also MIT licensed; the native
implementation archive includes the original license notice.

The native Zero Install client is upstream 0install/0install revision
`b58af5db6afd496cfd4a5f85fb23f30ba8dfbc87` (2.18), licensed LGPL-2.1. Its original
COPYING is installed under `share/licenses/0install/COPYING`. The client is built
with its upstream OCaml solver and networking libraries. No package-manager
operations or digest verification are replaced with simulations.

The test fixture's host Nix/Python provider feeds describe tools actually
preinstalled in the VM. They do not claim to install a new Nix daemon or create
an upstream distribution package.
