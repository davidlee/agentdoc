{
  description = "agentdoc";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
    jailed-agents.url = "github:davidlee/nix-config?dir=flakes/pub";
    spec-driver.url = "github:davidlee/spec-driver";
    rust-overlay.url = "github:oxalica/rust-overlay";
  };

  outputs = {
    nixpkgs,
    flake-utils,
    jailed-agents,
    spec-driver,
    rust-overlay,
    ...
  }:
    flake-utils.lib.eachDefaultSystem (system: let
      overlays = [rust-overlay.overlays.default];
      pkgs = import nixpkgs {inherit system overlays;};
      inherit (pkgs) lib stdenv;
      isLinux = stdenv.isLinux;

      jailLib =
        if isLinux
        then jailed-agents.lib.${system}.jailed-agents
        else {};

      spec-driver-pkg = spec-driver.packages.${system}.default;

      projectPkgs = with pkgs;
        [
          just
          rust-bin.stable.latest.default
          nodejs_latest
          stdenv.cc
          stdenv.cc.cc.lib
        ]
        ++ [spec-driver-pkg];

      jailEnvOptions = with jailLib.combinators; [
        (set-env "LD_LIBRARY_PATH" "${lib.makeLibraryPath [pkgs.stdenv.cc.cc.lib]}")
      ];

      jailedAgents = lib.optionalAttrs isLinux {
        jailed-pi-raw = jailLib.makeJailedPi {
          profile = "specDev";
          allowSelfAsSubagent = true;
          maxSubagentDepth = 2;
          extraPkgs = projectPkgs;
          extraOptions = jailEnvOptions;
        };
        jailed-pi-research-raw = jailLib.makeJailedPi {
          name = "pi-research";
          profile = "research";
          extraPkgs = projectPkgs;
          extraOptions = jailEnvOptions;
        };
        jailed-opencode = jailLib.makeJailedOpencode {
          profile = "specDev";
          extraPkgs = projectPkgs;
          extraOptions = jailEnvOptions;
        };
      };

      jailPkgs = lib.optionalAttrs isLinux {
        jailed-pi = pkgs.writeShellScriptBin "jailed-pi" ''
          ${lib.getExe' spec-driver-pkg "spec-driver"} admin preboot "$PWD" >/dev/null 2>&1
          exec ${lib.getExe' jailedAgents.jailed-pi-raw "jailed-pi"} "$@"
        '';
        jailed-pi-research = pkgs.writeShellScriptBin "jailed-pi-research" ''
          ${lib.getExe' spec-driver-pkg "spec-driver"} admin preboot "$PWD" >/dev/null 2>&1
          exec ${lib.getExe' jailedAgents.jailed-pi-research-raw "jailed-pi"} "$@"
        '';
        jailed-opencode = pkgs.writeShellScriptBin "jailed-opencode" ''
          ${lib.getExe' spec-driver-pkg "spec-driver"} admin preboot "$PWD" >/dev/null 2>&1
          exec ${lib.getExe' jailedAgents.jailed-opencode "jailed-opencode"} "$@"
        '';
      };
    in {
      packages = jailPkgs;

      devShells.default = pkgs.mkShell {
        packages =
          projectPkgs
          ++ lib.optionals isLinux (lib.attrValues jailPkgs);

        env.LD_LIBRARY_PATH = lib.makeLibraryPath [pkgs.stdenv.cc.cc.lib];
      };
    });
}
