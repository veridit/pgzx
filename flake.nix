{
  description = "Description for the project";

  inputs = {
    # Use nixpkgs 24.11 for stable packages
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-24.11";

    # Use nixpkgs unstable for PG18 (not available in 24.11)
    nixpkgs-unstable.url = "github:NixOS/nixpkgs/nixos-unstable";

    parts.url = "github:hercules-ci/flake-parts";

    zig-overlay = {
      url = "github:mitchellh/zig-overlay";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # Pin pre-commit-hooks to a version compatible with our nixpkgs
    # Using a commit from early 2024 that works with nixpkgs 24.05
    pre-commit-hooks-nix = {
      url = "github:cachix/pre-commit-hooks.nix/0db2e67ee49910adfa13010e7f012149660af7f0";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = inputs @ {
    self,
    nixpkgs,
    ...
  }: let
    zig-stable = "0.15.2";

    zig-overlay = _final: prev: let
      orig = inputs.zig-overlay.packages.${prev.system};
    in {
      zigpkgs =
        orig
        // {
          stable = orig.${zig-stable};
        };
    };
  in
    inputs.parts.lib.mkFlake {inherit inputs;} {
      debug = true;

      imports = [
        inputs.pre-commit-hooks-nix.flakeModule
        ./nix/modules/nixpkgs.nix
      ];

      flake.overlays = rec {
        default = nixpkgs.lib.composeManyExtensions [
          zigpkgs
          pgzx_scripts
        ];
        zigpkgs = zig-overlay;
        pgzx_scripts = _final: prev: {
          pgzx_scripts = self.packages.${prev.system}.pgzx_scripts;
        };
      };

      flake.templates = rec {
        default = init;
        init = {
          path = ./nix/templates/init;
          description = "Initialize postgres extension projects";
        };
      };

      systems = ["x86_64-linux" "x86_64-darwin" "aarch64-linux" "aarch64-darwin"];

      perSystem = {
        config,
        lib,
        pkgs,
        system,
        ...
      }: let
        # Import unstable nixpkgs for PG18
        pkgs-unstable = import inputs.nixpkgs-unstable {
          inherit system;
          config.allowUnfree = true;
        };
      in {
        nixpkgs = {
          config.allowBroken = true;
          overlays = [
            zig-overlay
          ];
        };

        pre-commit.pkgs = pkgs;
        pre-commit.settings = {
          hooks = {
            # editorconfig-checker.enable = true;

            # check github actions files
            actionlint.enable = true;

            # check nix files
            alejandra.enable = true;
            deadnix.enable = true;

            # check shell scripts
            shellcheck.enable = true;
            shfmt_local = {
              enable = true;
              name = "shfmt";
              description = "Shell script formatter";
              types = ["shell"];
              entry = "${pkgs.shfmt}/bin/shfmt -d -i 0 -ci -s";
            };

            # zig linters
            zigfmt = {
              enable = true;
              name = "Zig fmt";
              entry = "${pkgs.zigpkgs.stable}/bin/zig fmt --check";
              files = "\\.zig$|\\.zon$";
            };
          };
        };

        packages.pgzx_scripts = pkgs.stdenvNoCC.mkDerivation {
          name = "pgzx_scripts";
          src = ./dev/bin;
          installPhase = ''
            mkdir -p $out/bin
            cp -r $src/* $out/bin
          '';
        };

        devShells = let
          mkDevShell = postgresql: let
            devshell_nix = (import ./devshell.nix) {
              inherit pkgs lib postgresql;
            };
          in
            devshell_nix
            // {
              shellHook = ''
                ${devshell_nix.shellHook or ""}
              '';
            };

          mkShell = pkgs.mkShell;

          # On darwin we expect command line tools to be installed.
          # It is possible to install clang/gcc as nix package, but linking
          # can be quite a pain.
          # On non-darwin systems we will use the nix toolchain for now.
          useSystemCC = pkgs.stdenv.isDarwin;

          # Default shell uses PG16
          user_shell = mkDevShell pkgs.postgresql_16_jit;
        in {
          default = mkShell user_shell;

          # PostgreSQL version-specific shells
          pg16 = mkShell (mkDevShell pkgs.postgresql_16_jit);
          pg17 = mkShell (mkDevShell pkgs.postgresql_17_jit);
          # PG18 comes from nixpkgs-unstable since it's not in 24.11
          # Using non-JIT variant because postgresql_18_jit lacks dev output
          pg18 = mkShell (mkDevShell pkgs-unstable.postgresql_18);

          # Create development shell with C tools and dependencies to build Postgres locally.
          debug = mkShell (user_shell
            // {
              hardeningDisable = ["all"];

              packages =
                user_shell.packages
                ++ [
                  pkgs.flex
                  pkgs.bison
                  pkgs.meson
                  pkgs.ninja
                  pkgs.ccache
                  pkgs.pkg-config
                  pkgs.cmake

                  pkgs.icu
                  pkgs.zip
                  pkgs.readline
                  pkgs.openssl
                  pkgs.libxml2
                  pkgs.llvmPackages_17.llvm
                  pkgs.llvmPackages_17.lld
                  pkgs.llvmPackages_17.clang
                  pkgs.llvmPackages_17.clang-unwrapped
                  pkgs.lz4
                  pkgs.zstd
                  pkgs.libxslt
                  pkgs.python3
                ]
                ++ (lib.optionals (!useSystemCC) [
                  pkgs.clang
                ]);
            });
        };
      };
    };
}
