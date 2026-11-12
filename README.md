
# CachyOS Server Kernel with Native BBRv3 & x86-64-v3

[**English**](README.md) | [**Русский**](README_RU.md)

[![Build Kernel & Push to Cachix](https://github.com/lazyeel/cachyoskernel-bbr3-v3/actions/workflows/build.yml/badge.svg)](https://github.com/lazyeel/cachyoskernel-bbr3-v3/actions/workflows/build.yml)

A high-performance, server-tailored Linux kernel combining **CachyOS Server** patches with a native, upstream-adapted implementation of Google's **BBRv3** (Bottleneck Bandwidth and RTT v3) congestion control, built with **`x86-64-v3`** vector optimizations, **`PREEMPT_LAZY`** scheduling, and **300 Hz** tickrate.

Designed specifically for latency-sensitive network infrastructure (high-throughput VPN gateways, VLESS Reality/XHTTP, Hysteria 2/QUIC, reverse proxies) running concurrently with heavy background computing tasks (reverse engineering, compilation, AST indexing).

---

## Current Status & Metadata

* **Base Kernel:** `Linux 7.3.4-cachyos`
* **Target Architecture:** `x86-64-v3` (AVX, AVX2, FMA3, BMI1, BMI2)
* **Prebuilt Binary Cache:** Available via Cachix (instant deployment for NixOS)
* **Prebuilt Releases:** Available as standalone `.tar.zst` packages under [GitHub Releases](https://github.com/lazyeel/cachyoskernel-bbr3-v3/releases) for generic Linux distributions (Debian, Ubuntu, Arch, Fedora) without requiring Nix.
* **Automated CI Schedule:** Every day (`cron: '0 0 * * *'`)

---

## Key Features & Architectural Highlights

### 1. True Google BBRv3 Implementation
Upstream CachyOS 7.x kernels dropped BBRv3 algorithm integration and fell back to in-tree BBRv1. This repository re-introduces the genuine, full **Google BBRv3** code:
* Full 4-phase bandwidth probing state machine (`PROBE_BW_UP`, `PROBE_BW_DOWN`, `PROBE_BW_CRUISE`, `PROBE_BW_REFILL`).
* Adaptive upper/lower bounds (`inflight_hi`, `inflight_lo`, `bw_hi`, `bw_lo`) for bounded queueing and loss discrimination.
* Native ECN handling (L4S / AccECN / TCP Prague compatibility via `RTAX_FEATURE_ECN_LOW`).
* Fully wired with modern kernel eBPF kfuncs (`__bpf_kfunc static u32 bbr_tso_segs`) and BTF ID registration.
* Verified via `modinfo tcp_bbr` (`version: 3`, 9 Google authors) and runtime `/proc/kallsyms` (`bbr_skb_marked_lost`).

### 2. Microarchitecture Optimization (`x86-64-v3`)
Compiled with Clang and GCC optimizations targeting `x86-64-v3`:
* Native AVX2 and BMI2 hardware vectorization across all kernel subsystems: packet hashing (`jhash`, `siphash`), sk_buff copies, cryptographic primitives, and memory zeroing.
* Suitable for AMD Zen 2+ (e.g., EPYC Rome/Milan/Genoa, Ryzen 3000+) and Intel Haswell+ processors.

### 3. Latency & Scheduling: `PREEMPT_LAZY` & 300 Hz
* **`CONFIG_PREEMPT_LAZY=y`:** Eliminates the classical throughput-vs-latency dichotomy. Long-running batch compute tasks (JVM, Ghidra decompilation, compilation) run cache-warm with minimal preemption overhead, while latency-critical network packets (UDP, QUIC, TCP ACKs) trigger immediate, prioritized preemption.
* **300 Hz Tickrate (`CONFIG_HZ_300=y`):** Reduces virtualized timer interrupt overhead and KVM VM-Exits by ~40% compared to standard desktop 500/1000 Hz kernels, minimizing host CPU steal time.

### 4. Memory Management: THP `[madvise]`
* Transparent Huge Pages configured to **`madvise`** (`CONFIG_TRANSPARENT_HUGEPAGE_MADVISE=y`).
* Completely shields systems with moderate RAM and active `zram` from aggressive memory fragmentation and `khugepaged` compaction freezes, while allowing JVM applications (Ghidra, databases) to explicitly leverage 2MB pages when requested.

### 5. Automated CI/CD & Fail-Fast Protection
* Continuously built on GitHub Actions runners with 16 GB RAM and fast NVMe storage.
* Protected by an integrated compile-time guard (`FAIL-FAST GUARD`): if upstream CachyOS transitions to a new major branch (e.g., 7.4), evaluation aborts instantly before wasting build hours, preventing incompatible code from polluting the binary cache.

---

## Installation & Deployment

### Method A: Generic Linux (Debian, Ubuntu, Arch, Fedora) — No Nix Required

Download the precompiled archive directly from [GitHub Releases](https://github.com/lazyeel/cachyoskernel-bbr3-v3/releases):

```bash
# 1. Download and extract the latest release archive
curl -fsSLO https://github.com/lazyeel/cachyoskernel-bbr3-v3/releases/latest/download/linux-cachyos-server-bbr3-7.3.4-cachyos-x86_64-v3.tar.zst
tar --zstd -xf linux-cachyos-server-bbr3-*.tar.zst
cd linux-cachyos-server-bbr3-*

# 2. Run the automated installer (copies files, runs depmod, generates initramfs, updates GRUB)
sudo ./install.sh

# 3. Reboot into the new kernel
sudo reboot
```

---

### Method B: Generic Linux (Debian, Ubuntu, Fedora, Arch)

If your host runs a traditional distribution, you can install the standalone Nix package manager to fetch the prebuilt kernel binary and install it into your system `/boot` and `/lib/modules`.

#### 1. Install Nix (if not already installed)
```bash
curl -L https://nixos.org/nix/install | sh -s -- --daemon
```

#### 2. Configure Cachix & Fetch Prebuilt Kernel
```bash
# Add the binary cache
nix-env -iA cachix -f https://cachix.org/api/v1/install
cachix use cachyoskernel-bbr3-v3

# Build/fetch the kernel package (takes ~5 seconds from cache):
nix build github:lazyeel/cachyoskernel-bbr3-v3#packages.x86_64-linux.kernel --no-link --print-out-paths
```

#### 3. Install into `/boot` and `/lib/modules`
```bash
KERNEL_PATH=$(nix build github:lazyeel/cachyoskernel-bbr3-v3#packages.x86_64-linux.kernel --no-link --print-out-paths)
KERNEL_VERSION=$(ls "${KERNEL_PATH}/lib/modules")

# Copy kernel bzImage
sudo cp "${KERNEL_PATH}/bzImage" "/boot/vmlinuz-${KERNEL_VERSION}"

# Copy kernel modules
sudo cp -r "${KERNEL_PATH}/lib/modules/${KERNEL_VERSION}" "/lib/modules/"

# Generate initramfs (distribution specific):
# Debian/Ubuntu:
sudo update-initramfs -c -k "${KERNEL_VERSION}"
sudo update-grub

# Arch Linux:
# sudo mkinitcpio -k "${KERNEL_VERSION}" -g "/boot/initramfs-${KERNEL_VERSION}.img"
# sudo grub-mkconfig -o /boot/grub/grub.cfg
```

---

### Method C: NixOS (Via Cachix Binary Cache)

#### 1. Configure Inputs & Binary Cache in `flake.nix`
```nix
{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

    cachyos-bbr3-kernel = {
      url = "github:lazyeel/cachyoskernel-bbr3-v3";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = { self, nixpkgs, cachyos-bbr3-kernel, ... }@inputs: {
    nixosConfigurations.<your-hostname> = nixpkgs.lib.nixosSystem {
      system = "x86_64-linux";
      specialArgs = { inherit inputs; };
      modules = [
        ./configuration.nix
      ];
    };
  };
}
```

#### 2. Import Module in `configuration.nix`
```nix
{ config, lib, pkgs, inputs, ... }:

{
  imports = [
    # Imports the prebuilt kernel, modules, and default network sysctls:
    inputs.cachyos-bbr3-kernel.nixosModules.default
  ];

  # Explicitly trust the binary cache at the system level:
  nix.settings = {
    substituters = [
      "https://cache.nixos.org"
      "https://cachyoskernel-bbr3-v3.cachix.org"
    ];
    trusted-public-keys = [
      "cache.nixos.org-1:6NCHdD59X431o0gWypbMrAURkbJ16ZPMQFGspcDShjY="
      "cachyoskernel-bbr3-v3.cachix.org-1:Q3mylku1OfgfK2qQtLSQMOz5DmiQKQomteH7FujeqH0="
    ];
    trusted-users = [ "root" "@wheel" ];
  };
}
```

#### 3. Apply Configuration
```bash
sudo nixos-rebuild switch
sudo reboot
```

---

## Verification & Diagnostics

After rebooting into the new kernel, verify all runtime subsystems:

```bash
# 1. Kernel release check
uname -r
# Output: 7.3.4-cachyos

# 2. BBRv3 Module & Authors validation
modinfo tcp_bbr | grep -E "version|author"
# Expected output:
# version:        3
# author:         David Morley, Arjun Roy, Kevin Yang, Yousuk Seung, Priyaranjan Jha, Soheil Hassas Yeganeh, Yuchung Cheng, Neal Cardwell, Van Jacobson

# 3. Verify BBRv3 kernel symbols in runtime
sudo grep -E "bbr_skb_marked_lost|bbr_main" /proc/kallsyms

# 4. Active TCP socket telemetry
sudo ss -tin state established
# Look for bbr:(bw:...,mrtt:...,pacing_gain:...,cwnd_gain:...)
```

---

## License

* **Kernel code and BBRv3 patch:** Dual BSD/GPLv2 (following Linux Kernel and Google licenses).
* **Nix Flake & Infrastructure:** MIT License.

