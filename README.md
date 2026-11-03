# zeroinstall-impurifier

Generate native Zero Install feeds and content-addressed implementation archives
for Nix applications. Applications run as the user; this backend uses the native
Zero Install cache and app registry.

```nix
let
  impurifier = inputs.zeroinstall-impurifier.lib.zeroinstall-impurifier { inherit pkgs; };
in impurifier.makePackage { pkg = pkgs.hello; }
```

`makePackage` returns `net` and `offline`. `makeNetFeed` and `makeOfflineFeed`
select one. Copy the output bundle to a persistent directory outside the Nix
store before registering a local feed:

```sh
0store add "$(cat bundle/digest)" bundle/implementation.tar.gz
0install add hello "$PWD/bundle/feed.xml"
0install run hello
```

A working Nix provider and Python 3 are required. Optional `nixProvider` and
`pythonProvider` arguments name native Zero Install provider-feed URIs. The feed
uses `requires` and `executable-in-path` bindings so the native solver selects
those providers. Without these arguments, the launcher uses host tools on PATH.
Providing or installing Nix itself remains deferred work.

Net implementations use the host Nix configuration and trusted caches. An
unsigned offline cache cannot be imported by an untrusted daemon client. Install
the helper package exported as this flake's default package, then prepare the
already-imported native implementation explicitly:

```sh
implementation=$(0store find "$(cat bundle/digest)")
sudo "$(command -v zeroinstall-impurifier)" prepare "$implementation"
0install run hello
```

Preparation verifies the native implementation digest, imports its bundled Nix
closure, and registers its existing `nix-root` symlink as the owning user's GC
root. It changes no daemon trust settings and executes no application code as
root. Later launches stay unprivileged. Removing the native cache entry removes
the application root naturally.

`hardware` accepts the shared engine's explicit library/program/preload mapping.
Each launch captures the current host libraries as immutable Nix objects. Run
`zeroinstall-impurifier prune` after deleting obsolete native cache entries to
release their retained library snapshots. This does not claim compatibility
with a particular GPU kernel ABI.

`makeRepository { feeds = [ version1 version2 ]; }` combines one chosen transport
per version into a native feed. Keep its local URI stable and use ordinary
`0install update`, version constraints, and `0install destroy`. Destroying an app
keeps cached implementations according to native Zero Install policy. For web
publication, set `archiveURL` on a single feed or `archiveBaseURL` on a repository;
feed signing and trust remain native publisher policy.

Accounts, host configuration, system services, and global profile composition
are outside this per-user application's activation contract. The VM tests use
the real headless Zero Install 2.18 client, real Nix daemon, provider feeds,
native update/version selection, host-library capture, cache verification and GC.
Original code is MIT licensed; see [THIRD_PARTY.md](THIRD_PARTY.md).

## Native implementations and bundled clients

`makeNativeFeed { name; version; payload; command; dependencies?; architecture?; ... }`
emits a native feed and implementation archive without Nix launchers, provider
requirements or helper scripts. The producer supplies a runnable implementation
tree; this does not relocate binaries. The architecture string defaults to
`Linux-x86_64` and can describe another producer target. Native Zero Install owns
its content-addressed cache. The VM selects and verifies two native versions,
executes their static binaries in a root without `/nix`, and checks independent
cache eviction.

Nix-backed `makeFeed` accepts `bundledNixStore` and `bundledNixNotices` for a static
ELF client with upstream notices. Leave `nixProvider` unset when a native provider
feed is unnecessary. Compatible external clients take precedence; explicit
`IMPURIFIER_NIX_STORE` disables fallback and failed mutations are never retried
through another client. Python remains required. A separate bundled-client VM
repeats the original feed lifecycle suite without external Nix on the user's PATH.
Trusted root preparation never executes a client from a user-owned cache. The
Nix provider/installer remains deferred.
