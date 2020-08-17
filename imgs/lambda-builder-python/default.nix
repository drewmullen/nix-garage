{ system ? builtins.currentSystem }:
let
  nwi = import ../../nwi.nix;
  pkgs = import ../../pin { snapshot = "nixos-20-03_0"; };
  lib = pkgs.lib;
  script = pkgs.writeScriptBin "lambda-build" ( builtins.readFile  ./scripts/lambda-build.sh );
  contents = with pkgs; [ coreutils bash wget zip unzip awscli which utillinux script importedPythonPkgs ];
  importedPythonPkgs = with pkgs; python38.withPackages (pythonPkgs: with pythonPkgs; [
    # other python packages you want
    pip
    setuptools
  ]);
in
pkgs.dockerTools.buildImage {
  inherit contents;
  #name = "nebulaworks/lambda-build-python";
  name = "drewmullen/lambda-build-python";
  tag = "latest";
  config = {
    Env = [
      "PATH=/bin/"
    ];
    Labels = {
      "com.nebulaworks.packages" = lib.strings.concatStringsSep "," (lib.lists.naturalSort (lib.lists.forEach contents (x: lib.strings.getName x + ":" + lib.strings.getVersion x)));
      "org.opencontainers.image.authors" = nwi.company;
      "org.opencontainers.image.source" = nwi.source;
    };
    EntryPoint = [ "bash" ];
    WorkingDir = "/";
  };
}
