{
  # snixSrc is the *repo root* of https://git.snix.dev/snix/snix.git (the
  # directory containing default.nix, snix/, third_party/, nix/, ops/, etc.).
  # We reuse snix's own top-level default.nix so we inherit the depot's
  # readTree + crate2nix wiring instead of hand-rolling rustPlatform. This
  # keeps us on the exact Rust toolchain, nixpkgs pin, and crate overrides
  # snix upstream tests against.
  #
  # This is NOT IFD: the source is fetched at flake eval time via
  # `inputs.snix`, so importing default.nix is a plain nix eval-time import.
  snixSrc,
  symlinkJoin,
  stdenv,
  # `lib` is passed by callPackage but we only use it via `snixDepot` below;
  # keep the arg so the signature matches callPackage conventions.
  lib,
}:

let
  # Import snix's own top-level depot expression. This gives us the full
  # readTree'd attrset, including `snix.crates.workspaceMembers.<name>.build`
  # for every workspace member. snix's default.nix pins its own nixpkgs via
  # third_party/sources (niv), so we don't need to pass one in.
  #
  # We must pass `localSystem` explicitly because snix's default.nix shadows
  # `builtins.currentSystem` inside its readTree scopedArgs (making the
  # default of `localSystem ? builtins.currentSystem` throw when evaluated
  # without a pure impure context).
  snixDepot = import snixSrc {
    localSystem = stdenv.hostPlatform.system;
  };

  # Per-crate builds produced by crate2nix (via `snix.crates`). Each
  # `.build` is a derivation that installs the crate's binaries into
  # `$out/bin`. Workspace member names (Cargo package names) differ from
  # the binary names they produce:
  #
  #   snix-cli            -> `snix`            (the evaluator / CLI)
  #   snix-cli-store      -> `snix-store`      (castore + PathInfoService daemon/mount)
  #   snix-cli-nix-daemon -> `snix-nix-daemon` (Nix daemon protocol frontend)
  #   snix-cli-nar-bridge -> `snix-nar-bridge` (HTTP binary cache server)
  #
  # Selecting them individually (instead of pulling the whole workspace)
  # means Nix only realises the derivations we actually need.
  snix-cli = snixDepot.snix.crates.workspaceMembers.snix-cli.build;
  snix-store = snixDepot.snix.crates.workspaceMembers.snix-cli-store.build;
  nix-daemon = snixDepot.snix.crates.workspaceMembers.snix-cli-nix-daemon.build;
  snix-nar-bridge = snixDepot.snix.crates.workspaceMembers.snix-cli-nar-bridge.build;
in
# Combine the per-crate outputs into a single package so downstream
# consumers (systemd units in snix.nix) can reference one `pkgs.snix` and
# find all binaries under `$out/bin/`.
symlinkJoin {
  name = "snix";
  paths = [
    snix-cli
    snix-store
    nix-daemon
    snix-nar-bridge
  ];

  meta = {
    description = "Snix - Rust re-implementation of Nix (via upstream depot)";
    homepage = "https://snix.dev";
    license = lib.licenses.gpl3Only;
    platforms = lib.platforms.linux;
  };
}
