# SPDX-License-Identifier: MIT
{ pkgs, impurifier }:
let
  feed =
    version:
    impurifier.makeNativeFeed {
      name = "native-proof";
      inherit version;
      command = "proof";
      payload = pkgs.pkgsStatic.stdenv.mkDerivation {
        name = "native-zeroinstall-${version}";
        dontUnpack = true;
        buildPhase = ''
          cat > proof.c <<'C'
          #include <stdio.h>
          int main(void) { puts("native-proof-${version}"); return 0; }
          C
          $CC proof.c -o proof
        '';
        installPhase = "mkdir -p $out; cp proof $out/";
      };
    };
in
pkgs.testers.runNixOSTest {
  name = "zeroinstall-native-payload";
  requiredFeatures.kvm = false;
  requiredFeatures.devnet = false;
  nodes.machine = { lib, ... }: {
    virtualisation.qemu.package = lib.mkForce pkgs.qemu;
    virtualisation.qemu.forceAccel = false;
    environment.systemPackages = [ impurifier.tools.package ];
    users.users.consumer.isNormalUser = true;
  };
  testScript = ''
    start_all()
    machine.wait_for_unit("multi-user.target")
    machine.succeed("mkdir -p /srv/native/cache; chown -R consumer:users /srv/native")
    machine.succeed("cp -r ${feed "1"} /home/consumer/feed1; cp -r ${feed "2"} /home/consumer/feed2; chown -R consumer:users /home/consumer/feed*")
    def native(command):
        import shlex
        return "su - consumer -c " + shlex.quote("export XDG_CACHE_HOME=/srv/native/cache; " + command)
    paths = []
    for version in [1, 2]:
        base = "/home/consumer/feed" + str(version)
        digest = machine.succeed("cat " + base + "/digest").strip()
        machine.succeed(native("0store add " + digest + " " + base + "/implementation.tar.gz"))
        machine.succeed(native("0install --offline --console run " + base + "/feed.xml") + " | grep '^native-proof-" + str(version) + "$'")
        implementation = machine.succeed(native("0store find " + digest)).strip()
        assert implementation.startswith("/srv/native/")
        machine.succeed("chroot /srv/native " + implementation.removeprefix("/srv/native") + "/proof | grep '^native-proof-" + str(version) + "$'")
        machine.succeed(native("0store verify " + digest))
        machine.succeed("test ! -e /srv/native/nix && test ! -e " + base + "/prepare.py")
        paths.append(implementation)
    machine.succeed("chmod -R u+w " + paths[0] + "; rm -rf " + paths[0])
    machine.fail(native("0store find $(cat /home/consumer/feed1/digest)"))
    machine.succeed(native("0install --offline --console run /home/consumer/feed2/feed.xml") + " | grep '^native-proof-2$'")
    machine.succeed("chmod -R u+w " + paths[1] + "; rm -rf " + paths[1])
    machine.fail(native("0store find $(cat /home/consumer/feed2/digest)"))
  '';
}
