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

      customKernel = pkgs.cachyosKernels.linux-cachyos-server.override {
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
          "net.core.rmem_max" = 67108864;
          "net.core.wmem_max" = 67108864;
          "net.ipv4.tcp_rmem" = "4096 87380 33554432";
          "net.ipv4.tcp_wmem" = "4096 65536 33554432";
          "net.ipv4.udp_rmem_min" = 16384;
          "net.ipv4.udp_wmem_min" = 16384;
          "net.core.netdev_max_backlog" = 100000;
          "net.core.somaxconn" = 65535;
          "kernel.yama.ptrace_scope" = 0;
        };
      };
    };
}
