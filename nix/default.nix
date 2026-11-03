# SPDX-License-Identifier: MIT
{
  pkgs,
  coreSrc,
  sourceInfo ? { },
}:
let
  inherit (pkgs) lib;
  core = import (coreSrc + "/nix") {
    inherit pkgs;
    namespace = "zeroinstall-impurifier";
  };
  package = pkgs.writeShellApplication {
    name = "zeroinstall-impurifier";
    runtimeInputs = [
      tools.package
      pkgs.nix
      pkgs.python3
      pkgs.util-linux
    ];
    text = ''
      if [ "$#" -eq 0 ]; then
        echo 'usage: zeroinstall-impurifier prepare IMPLEMENTATION | prune' >&2
        exit 2
      fi
      impurifier_action=$1
      shift
      case "$impurifier_action" in
        prepare) exec python3 ${../src/prepare.py} "$@" ;;
        prune) [ "$#" -eq 0 ]; exec python3 ${../src/prune.py} ;;
        *) echo 'usage: zeroinstall-impurifier prepare IMPLEMENTATION | prune' >&2; exit 2 ;;
      esac
    '';
  };
  tools = import ./tools.nix { inherit pkgs; };
  buildFeed =
    {
      name,
      version,
      payload,
      command,
      dependencies ? [ ],
      archiveURL ? null,
      description ? "Nix projected application",
      architecture ? "Linux-x86_64",
      includeHelpers ? true,
    }:
    assert lib.assertMsg (
      builtins.match "[A-Za-z0-9_./+-]+" command != null
      && !(lib.hasPrefix "/" command)
      && !(lib.elem ".." (lib.splitString "/" command))
    ) "feed command must remain inside the implementation";
    assert lib.assertMsg (
      builtins.match "[A-Za-z0-9_*]+-[A-Za-z0-9_*]+" architecture != null
    ) "invalid Zero Install architecture";
    pkgs.runCommand "${name}-${version}-zeroinstall"
      {
        nativeBuildInputs = [
          tools.package
          pkgs.python3
          pkgs.gnutar
          pkgs.gzip
        ];
        __structuredAttrs = true;
        unsafeDiscardReferences.out = true;
        passthru = { inherit name version; };
      }
      ''
        mkdir -p "$out" root
        cp -r ${payload}/. root/
        chmod -R u+w root
        find root -exec touch -h -d @1 {} +
        0install digest --algorithm=sha256new root > "$out/digest"
        tar --sort=name --mtime=@1 --owner=0 --group=0 --numeric-owner -C root -cf - . | gzip -n > "$out/implementation.tar.gz"
        ${lib.optionalString includeHelpers ''
          cp ${../src/prepare.py} "$out/prepare.py"
          cp ${../src/prune.py} "$out/prune.py"
        ''}
        python3 ${../src/feed.py} "$out" ${
          pkgs.writeText "feed.json" (
            builtins.toJSON {
              inherit
                name
                version
                command
                description
                dependencies
                archiveURL
                architecture
                ;
            }
          )
        }
      '';
  makeFeed =
    {
      pkg,
      program ? pkg.meta.mainProgram or pkg.pname,
      offline ? false,
      hardware ? null,
      bundledNixStore ? null,
      bundledNixNotices ? [ ],
      nixProvider ? null,
      pythonProvider ? null,
      archiveURL ? null,
    }:
    assert lib.assertMsg (
      builtins.match "[A-Za-z0-9_.+-]+" program != null
      && !(lib.elem program [
        "."
        ".."
      ])
    ) "invalid Nix program name";
    assert lib.assertMsg (
      hardware == null || lib.elem program (hardware.programs or [ ])
    ) "hardware programs must include the selected feed command";
    buildFeed {
      inherit archiveURL;
      name = pkg.pname;
      inherit (pkg) version;
      command = "launch.py";
      dependencies =
        lib.optional (nixProvider != null) {
          interface = nixProvider;
          executable = "nix-store";
        }
        ++ lib.optional (pythonProvider != null) {
          interface = pythonProvider;
          executable = "python3";
        };
      payload = pkgs.runCommand "zeroinstall-nix-implementation" { } ''
        mkdir -p $out
        ${lib.optionalString (bundledNixStore != null) ''
          cp ${
            core.makeRuntimeTree { inherit bundledNixStore bundledNixNotices; }
          }/usr/lib/zeroinstall-impurifier/nix-store $out/nix-store
          mkdir -p $out/share/licenses/bundled-nix
          cp -r ${
            core.makeRuntimeTree { inherit bundledNixStore bundledNixNotices; }
          }/usr/share/licenses/zeroinstall-impurifier/bundled-nix/. $out/share/licenses/bundled-nix/
        ''}
        install -m755 ${../src/launch.py} $out/launch.py
        cp ${coreSrc}/src/engine.py $out/engine.py
        cp ${../LICENSE} $out/LICENSE
        cp ${
          pkgs.writeText "application.json" (
            builtins.toJSON {
              inherit program offline;
              hardware = if hardware == null then null else { preload = [ ]; } // hardware;
              name = pkg.pname;
              version = pkg.version;
              installable = toString pkg;
            }
          )
        } $out/application.json
        ln -s ${pkg} $out/nix-root
        ${lib.optionalString offline "cp -r ${core.offlineCache pkg} $out/cache"}
      '';
    };
in
{
  inherit
    tools
    package
    buildFeed
    makeFeed
    ;
  makeRepository =
    {
      feeds,
      archiveBaseURL ? "",
    }:
    pkgs.runCommand "zeroinstall-feed-repository"
      {
        nativeBuildInputs = [ pkgs.python3 ];
        __structuredAttrs = true;
        unsafeDiscardReferences.out = true;
      }
      ''
        python3 ${../src/repository.py} "$out" ${lib.escapeShellArg archiveBaseURL} ${lib.escapeShellArgs (map toString feeds)}
      '';
  makeNativeFeed = args: buildFeed (args // { includeHelpers = false; });
  makeNetFeed = args: makeFeed (args // { offline = false; });
  makeOfflineFeed = args: makeFeed (args // { offline = true; });
  makePackage = args: {
    net = makeFeed (args // { offline = false; });
    offline = makeFeed (args // { offline = true; });
  };
}
