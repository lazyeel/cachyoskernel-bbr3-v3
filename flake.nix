{
  description = "Automated CachyOS Server Kernel with BBRv3, x86-64-v3, and PREEMPT_LAZY";

  nixConfig = {
    extra-substituters = [ "https://cachyoskernel-bbr3-v3.cachix.org" ];
    extra-trusted-public-keys = [ "cachyoskernel-bbr3-v3.cachix.org-1:Q3mylku1OfgfK2qQtLSQMOz5DmiQKQomteH7FujeqH0=" ];
  };

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    nix-cachyos-kernel = {
      url = "github:xddxdd/nix-cachyos-kernel";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = { self, nixpkgs, nix-cachyos-kernel, ... }:
    let
      system = "x86_64-linux";
      pkgs = import nixpkgs {
        inherit system;
        overlays = [ nix-cachyos-kernel.overlays.default ];
      };

      rawKernelVersion = pkgs.cachyosKernels.linux-cachyos-server.version;
      kernelSeries = pkgs.lib.versions.majorMinor rawKernelVersion;

      supportedSeries = "7.3";

      _guard = assert pkgs.lib.assertMsg (kernelSeries == supportedSeries) ''
        ════════════════════════════
        FAIL-FAST GUARD: Kernel versioning error:
        CachyOS upstream has updated to branch: ${kernelSeries}
        The file src/tcp_bbr.c in the repository is only verified for branch: ${supportedSeries}

        The build was halted to prevent pushing an incompatible kernel to the binary cache.
        Actions:
        1. Obtain the adapted tcp_bbr.c for the ${kernelSeries} branch (e.g., from XanMod).
        2. Replace src/tcp_bbr.c in the repository with it.
        3. Change supportedSeries = "${kernelSeries}" in flake.nix.
        ════════════════════════════
      ''; true;

      customKernel = assert _guard; pkgs.cachyosKernels.linux-cachyos-server.override {
        processorOpt = "x86_64-v3";
        bbr3 = true;
        hzTicks = "300";
        preemptType = "lazy";
        cpusched = "bore";
        hugepage = "madvise";
        lto = "none";
        ccHarder = true;

        postPatch = ''
          chmod +w net/ipv4/tcp_bbr.c
          cp -f ${./src/tcp_bbr.c} net/ipv4/tcp_bbr.c
        '';

        structuredExtraConfig = with pkgs.lib.kernel; {
          TCP_CONG_BBR = yes;
          DEFAULT_BBR = yes;
          DEFAULT_TCP_CONG = freeform "bbr";
          NET_SCH_FQ = yes;
        };
      };

      kernelPackages = pkgs.linuxKernel.packagesFor customKernel;
    in
    {
      packages.${system} = {
        default = kernelPackages.kernel;
        kernel = kernelPackages.kernel;
        inherit kernelPackages;
      };

      nixosModules.default = { config, pkgs, lib, ... }: {
        boot.kernelPackages = self.packages.${system}.kernelPackages;
        boot.kernelModules = [ "tcp_bbr" ];

        boot.kernel.sysctl = {
          "net.core.default_qdisc" = "fq";
          "net.ipv4.tcp_congestion_control" = "bbr";
        };
      };
    };
}
