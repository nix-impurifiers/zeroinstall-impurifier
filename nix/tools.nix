# SPDX-License-Identifier: MIT
{ pkgs }:
let
  source = pkgs.fetchFromGitHub {
    owner = "0install";
    repo = "0install";
    rev = "b58af5db6afd496cfd4a5f85fb23f30ba8dfbc87";
    hash = "sha256-CxADWMYZBPobs65jeyMQjqu3zmm2PgtNgI/jUsYUp8I=";
  };
  package = pkgs.ocamlPackages.buildDunePackage {
    pname = "0install";
    version = "2.18";
    src = source;
    propagatedBuildInputs = with pkgs.ocamlPackages; [
      _0install-solver
      yojson
      xmlm
      lwt
      lwt_react
      ocurl
      sha
    ];
    nativeBuildInputs = [ pkgs.makeWrapper ];
    postInstall = ''
      mkdir -p $out/share/licenses/0install
      cp COPYING $out/share/licenses/0install/COPYING
      for program in $out/bin/*; do
        wrapProgram "$program" --prefix PATH : ${
          pkgs.lib.makeBinPath [
            pkgs.gnupg
            pkgs.gnutar
            pkgs.unzip
            pkgs.xz
            pkgs.bzip2
            pkgs.gzip
          ]
        }
      done
    '';
  };
in
{
  inherit source package;
}
