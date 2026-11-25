{
  description = "gh-ssh GitHub CLI extension";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs =
    { nixpkgs, flake-utils, ... }:
    flake-utils.lib.eachDefaultSystem (
      system:
      let
        pkgs = nixpkgs.legacyPackages.${system};
        runtimeInputs = with pkgs; [
          bash
          gh
          gum
          jq
          openssh
        ];
      in
      {
        packages.default = pkgs.stdenvNoCC.mkDerivation {
          pname = "gh-ssh";
          version = nixpkgs.lib.fileContents ./version.txt;
          src = ./.;
          nativeBuildInputs = [ pkgs.makeWrapper ];
          dontBuild = true;
          installPhase = ''
            runHook preInstall
            mkdir -p $out/libexec/gh-ssh $out/bin
            cp gh-ssh version.txt $out/libexec/gh-ssh/
            cp -r scripts $out/libexec/gh-ssh/
            chmod +x $out/libexec/gh-ssh/gh-ssh
            makeWrapper $out/libexec/gh-ssh/gh-ssh $out/bin/gh-ssh \
              --prefix PATH : ${pkgs.lib.makeBinPath runtimeInputs}
            runHook postInstall
          '';
          meta = {
            description = "Set up GitHub SSH authentication and signing keys";
            homepage = "https://github.com/gh-extensions/gh-ssh";
            license = pkgs.lib.licenses.mit;
            mainProgram = "gh-ssh";
          };
        };
        devShells.default = pkgs.mkShell {
          name = "gh-ssh";
          packages =
            runtimeInputs
            ++ (with pkgs; [
              bats
              shellcheck
            ]);
        };
      }
    );
}
