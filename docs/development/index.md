# Development

`buildFeed` invokes native `0install digest --algorithm=sha256new` and emits a
native `manifest-digest` element and implementation archive. `makeFeed` adds a
Nix launcher, optional offline cache, and existing `nix-root` symlink.

The launcher briefly makes its owning native cache directory writable to let
Nix register that same symlink indirectly, then restores the original mode.
The symlink target is unchanged; native `0store verify` remains valid. Root
preparation uses a temporary root during import and drops privileges to register
the lasting cache root as its owner. Never execute user application code as root.

`tests/default.nix` uses an ordinary user and real daemon. Unsigned offline import
must fail before explicit preparation. Native update/version selection,
provider feeds, host-library changes, cache verification, GC survival and closure
release after cache deletion must all pass. Keep local feed bundles outside the
Nix store in the fixture so GC tests don't accidentally retain build artifacts.

User cache ownership is central to this target. Do not reuse a global system
profile or add system account/service mutations to a native per-user feed.
Signed remote publication and GUI integration need their own coverage.
