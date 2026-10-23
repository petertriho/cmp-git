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
          packages = neovim: [
            neovim
            pkgs.stylua
            pkgs.selene
            pkgs.lua-language-server
            pkgs.gnumake
            pkgs.git
          ];
          shell =
            neovim:
            pkgs.mkShell {
              packages = packages neovim;
              # scripts/nightly-cache.sh reads the store path of Neovim from here
              passthru = { inherit neovim; };
            };
        in
        {
          default = shell pkgs.neovim-unwrapped;
          # The CLIs and the servers of `make test-integration`. Forgejo is broken on aarch64-darwin, so its server
          # cases skip there.
          integration = pkgs.mkShell {
            packages =
              packages pkgs.neovim-unwrapped
              ++ [
                pkgs.curl
                pkgs.gh
                pkgs.glab
                pkgs.tea
                pkgs.forgejo-cli
                pkgs.gitea
              ]
              ++ pkgs.lib.optional (!pkgs.forgejo.meta.broken) pkgs.forgejo;
          };
          # The minimum supported version
          nvim-0_12_0 = shell (mv.fast.version "neovim-unwrapped" "0.12.0");
          # The overlay CI pushes only this output to nix-community.cachix.org. It uses the nixpkgs of the
          # overlay's dev partition, so `packages.${system}.default` is a different build that is not in the cache.
          nightly = shell neovim-nightly-overlay.checks.${system}.neovim;
        }
      );
    };
}
