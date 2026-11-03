# SPDX-License-Identifier: MIT
{
  pkgs,
  impurifier,
  tools,
  coreSrc,
  bundled ? false,
}:
let
  feed = impurifier.buildFeed {
    name = "native-marker";
    version = "1";
    command = "hello";
    payload = pkgs.runCommand "zeroinstall-native-payload" { } ''
      mkdir -p $out
      printf '#!/bin/sh\necho native\n' > $out/hello
      chmod 755 $out/hello
    '';
  };
  tool =
    pkgs.runCommand "zeroinstall-tool-1"
      {
        pname = "zeroinstall-tool";
        version = "1";
      }
      ''
        mkdir -p $out/bin
        printf '#!${pkgs.busybox}/bin/sh\necho impurified\n' > $out/bin/zeroinstall-tool
        chmod 755 $out/bin/zeroinstall-tool
      '';
  application = impurifier.makeOfflineFeed {
    pkg = tool;
    nixProvider = "/home/consumer/nix-provider.xml";
    pythonProvider = "/home/consumer/python-provider.xml";
  };
  tool2 = tool.overrideAttrs (old: {
    name = "zeroinstall-tool-2";
    version = "2";
    buildCommand = builtins.replaceStrings [ "echo impurified" ] [ "echo upgraded" ] old.buildCommand;
  });
  netApplication = impurifier.makeNetFeed {
    pkg = tool;
    nixProvider = "/home/consumer/nix-provider.xml";
    pythonProvider = "/home/consumer/python-provider.xml";
  };
  application2 = impurifier.makeOfflineFeed { pkg = tool2; };
  repository = impurifier.makeRepository {
    feeds = [
      application
      application2
    ];
  };
  fixture = import (coreSrc + "/tests/hardware-fixture.nix") { inherit pkgs; };
  hardware = impurifier.makeOfflineFeed {
    pkg = fixture.tool // {
      pname = "hardware_tool";
    };
    program = "hardware-tool";
    inherit (fixture) hardware;
  };
in
{
  native-payload-vm = import ./native-payload-vm.nix { inherit pkgs impurifier; };
  native-feed = feed;
  native-vm = pkgs.testers.runNixOSTest {
    name = "zeroinstall-native-contract";
    requiredFeatures = {
      kvm = false;
      devnet = false;
    };
    nodes.machine = { lib, ... }: {
      virtualisation.qemu.package = lib.mkForce pkgs.qemu;
      virtualisation.qemu.forceAccel = false;
      environment.systemPackages = [
        impurifier.package
        tools.package
        pkgs.nix
        pkgs.python3
      ];
      nix.settings.substituters = lib.mkForce [ ];
      systemd.tmpfiles.rules = [ "L+ /usr/bin/env - - - - ${pkgs.coreutils}/bin/env" ];
      system.activationScripts.bundledClientPath = {
        deps = [ "users" ];
        text = pkgs.lib.optionalString bundled ''
          mkdir -p /home/consumer
          cat > /home/consumer/.bash_profile <<'PROFILE'
          export PATH=${
            pkgs.buildEnv {
              name = "zeroinstall-no-external-nix";
              paths = [
                tools.package
                pkgs.python3
                pkgs.coreutils
                impurifier.package
              ];
            }
          }/bin
          PROFILE
          chown consumer:users /home/consumer/.bash_profile
        '';
      };
      users.users.consumer = {
        isNormalUser = true;
      };
    };
    testScript = ''
      start_all()
      machine.wait_for_unit("multi-user.target")
      ${pkgs.lib.optionalString bundled ''machine.fail("su - consumer -c 'command -v nix-store'")''}
      machine.succeed("printf '%s' '<interface xmlns=\"http://zero-install.sourceforge.net/2004/injector/interface\"><name>Nix provider</name><summary>Preinstalled native Nix fixture</summary><implementation id=\"host-nix\" local-path=\"/\" version=\"2.34\"><command name=\"run\" path=\"run/current-system/sw/bin/nix-store\"/></implementation></interface>' > /home/consumer/nix-provider.xml")
      machine.succeed("printf '%s' '<interface xmlns=\"http://zero-install.sourceforge.net/2004/injector/interface\"><name>Python provider</name><summary>Preinstalled native Python fixture</summary><implementation id=\"host-python\" local-path=\"/\" version=\"3.14\"><command name=\"run\" path=\"run/current-system/sw/bin/python3\"/></implementation></interface>' > /home/consumer/python-provider.xml")
      machine.succeed("cp -r ${feed} /home/consumer/native; cp -r ${application} /home/consumer/application; cp -r ${netApplication} /home/consumer/net; cp -r ${application2} /home/consumer/application2; cp -r ${repository} /home/consumer/repository; cp -r ${hardware} /home/consumer/hardware; chown -R consumer:users /home/consumer/native /home/consumer/application /home/consumer/net /home/consumer/application2 /home/consumer/repository /home/consumer/hardware")
      machine.succeed("su - consumer -c '0store add $(cat /home/consumer/native/digest) /home/consumer/native/implementation.tar.gz'")
      machine.succeed("su - consumer -c '0install --offline --console run /home/consumer/native/feed.xml' | grep '^native$'")
      machine.succeed("test ! -e ${builtins.unsafeDiscardStringContext (toString tool)}")
      machine.succeed("su - consumer -c '0store add $(cat /home/consumer/net/digest) /home/consumer/net/implementation.tar.gz'")
      machine.fail("su - consumer -c '0install --offline --console run /home/consumer/net/feed.xml' > /tmp/net-failure.log 2>&1")
      machine.succeed("su - consumer -c '0store add $(cat /home/consumer/application/digest) /home/consumer/application/implementation.tar.gz'")
      machine.fail("su - consumer -c '0install --offline --console run /home/consumer/application/feed.xml' > /tmp/untrusted-offline.log 2>&1")
      machine.succeed("grep 'untrusted substituter' /tmp/untrusted-offline.log")
      implementation = machine.succeed("su - consumer -c '0store find $(cat /home/consumer/application/digest)'").strip()
      machine.succeed("zeroinstall-impurifier prepare " + implementation)
      machine.succeed("su - consumer -c '0install --offline --console run --version=1 /home/consumer/application/feed.xml' | grep '^impurified$'")
      machine.succeed("su - consumer -c '0store verify $(cat /home/consumer/application/digest)'")
      assert machine.succeed("su - consumer -c '0install --offline --console run --version=1 /home/consumer/application/feed.xml'").strip() == "impurified"
      machine.succeed("su - consumer -c '0install --offline --console run /home/consumer/net/feed.xml' | grep '^impurified$'")
      machine.succeed("su - consumer -c '0install --offline --console add impurified /home/consumer/application/feed.xml; 0install --offline --console run impurified' | grep '^impurified$'")
      machine.succeed("su - consumer -c '0store add $(cat /home/consumer/application2/digest) /home/consumer/application2/implementation.tar.gz'")
      implementation2 = machine.succeed("su - consumer -c '0store find $(cat /home/consumer/application2/digest)'").strip()
      machine.succeed("zeroinstall-impurifier prepare " + implementation2)
      machine.succeed("cp /home/consumer/repository/feed.xml /home/consumer/application/feed.xml; chown consumer:users /home/consumer/application/feed.xml")
      machine.succeed("su - consumer -c '0install --offline --console update impurified; 0install --offline --console run impurified' | grep '^upgraded$'")
      machine.succeed("su - consumer -c '0install --offline --console update --version=1 impurified; 0install --offline --console run impurified' | grep '^impurified$'")
      machine.succeed("mkdir -p /usr/lib; cp ${fixture.driver "1"}/usr/lib/libimpurifier-driver.so.1 /usr/lib/")
      machine.succeed("su - consumer -c '0store add $(cat /home/consumer/hardware/digest) /home/consumer/hardware/implementation.tar.gz'")
      hardware_implementation = machine.succeed("su - consumer -c '0store find $(cat /home/consumer/hardware/digest)'").strip()
      machine.succeed("zeroinstall-impurifier prepare " + hardware_implementation)
      machine.succeed("su - consumer -c '0install --offline --console run /home/consumer/hardware/feed.xml' | grep '^1$'")
      machine.succeed("cp ${fixture.driver "2"}/usr/lib/libimpurifier-driver.so.1 /usr/lib/")
      machine.succeed("su - consumer -c '0install --offline --console run /home/consumer/hardware/feed.xml' | grep '^2$'")
      machine.succeed("su - consumer -c '0store verify $(cat /home/consumer/hardware/digest)'")
      machine.succeed("nix-collect-garbage")
      machine.succeed("su - consumer -c '0install --offline --console run --version=1 /home/consumer/application/feed.xml' | grep '^impurified$'")
      machine.succeed("su - consumer -c '0install --console destroy impurified'")
      machine.fail("su - consumer -c '0install --offline --console run impurified'")
      machine.succeed("su - consumer -c '0store verify $(cat /home/consumer/native/digest)'")
      machine.succeed("test ! -e /opt/nix/profile")
      machine.succeed("su - consumer -c 'chmod -R u+w /home/consumer/.cache/0install.net/implementations; rm -rf /home/consumer/.cache/0install.net/implementations; zeroinstall-impurifier prune'")
      machine.succeed("nix-collect-garbage")
      machine.succeed("test ! -e ${builtins.unsafeDiscardStringContext (toString tool)}; test ! -e ${builtins.unsafeDiscardStringContext (toString tool2)}; test ! -e ${builtins.unsafeDiscardStringContext (toString fixture.tool)}")

    '';
  };
}
