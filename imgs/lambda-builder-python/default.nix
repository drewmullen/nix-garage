{ system ? builtins.currentSystem }:
let
  nwi = import ../../nwi.nix;
  pkgs = import ../../pin { snapshot = "nixos-20-03_0"; };
  lib = pkgs.lib;
  script = pkgs.writeScriptBin "lambda-build" ( builtins.readFile  ./scripts/lambda-build.sh );
  contents = with pkgs; [ cacert coreutils curl bash wget zip unzip awscli which utillinux script importedPythonPkgs ];
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
  runAsRoot = ''
      #!${pkgs.runtimeShell}
      # ci breaks if it doesnt find a linux release file
      echo "ID=alpine" > /etc/os-release
  '';
  config = {
    Env = [
      "PATH=/bin/"
      "SSL_CERT_FILE=/etc/ssl/certs/ca-bundle.crt"
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
