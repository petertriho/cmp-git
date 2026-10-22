{
  description = "Development shells for cmp-git";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    multiverse.url = "github:fzakaria/nixpkgs-multiverse";
    # No `follows` on its inputs, so the builds match nix-community.cachix.org
    neovim-nightly-overlay.url = "github:nix-community/neovim-nightly-overlay";
  };

  outputs =
    {
      nixpkgs,
      multiverse,
      neovim-nightly-overlay,
      ...
    }:
    let
      # The systems that the multiverse fast path publishes store paths for
      systems = [
        "x86_64-linux"
        "aarch64-linux"
        "aarch64-darwin"
      ];
      forAllSystems = f: nixpkgs.lib.genAttrs systems (system: f system nixpkgs.legacyPackages.${system});
    in
    {
      devShells = forAllSystems (
        system: pkgs:
        let
          mv = multiverse.multiverse.${system};
          shell =
            neovim:
            pkgs.mkShell {
              packages = [
                neovim
                pkgs.stylua
                pkgs.selene
                pkgs.lua-language-server
                pkgs.gnumake
                pkgs.git
              ];
              # scripts/nightly-cache.sh reads the store path of Neovim from here
              passthru = { inherit neovim; };
            };
        in
        {
          default = shell pkgs.neovim-unwrapped;
          # The minimum supported version
          nvim-0_12_0 = shell (mv.fast.version "neovim-unwrapped" "0.12.0");
          # The overlay CI pushes only this output to nix-community.cachix.org. It uses the nixpkgs of the
          # overlay's dev partition, so `packages.${system}.default` is a different build that is not in the cache.
          nightly = shell neovim-nightly-overlay.checks.${system}.neovim;
        }
      );
    };
}
