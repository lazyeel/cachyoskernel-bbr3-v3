
# Ядро CachyOS Server с поддержкой BBRv3 и x86-64-v3

[**English**](README.md) | [**Русский**](README_RU.md)

[![Build Kernel & Push to Cachix](https://github.com/lazyeel/cachyoskernel-bbr3-v3/actions/workflows/build.yml/badge.svg)](https://github.com/lazyeel/cachyoskernel-bbr3-v3/actions/workflows/build.yml)

Высокопроизводительное серверное ядро Linux, объединяющее набор серверных патчей **CachyOS Server** с нативной, адаптированной под апстрим реализацией алгоритма **BBRv3** от Google, векторными оптимизациями под набор инструкций **`x86-64-v3`**, планировщиком **`PREEMPT_LAZY`** и серверным тикрейтом **300 Гц**.

Спроектировано специально для чувствительной к сетевым задержкам инфраструктуры (высокоскоростные VPN-ноды, VLESS Reality/XHTTP, Hysteria 2/QUIC, реверс-прокси), работающей параллельно с тяжелыми вычислительными нагрузками (реверс-инжиниринг, компиляция, построение AST-графов).

---

## Текущий статус и метаданные

* **Базовое ядро:** `Linux 7.3.4-cachyos`
* **Целевая микроархитектура:** `x86-64-v3` (AVX, AVX2, FMA3, BMI1, BMI2)
* **Бинарный кэш:** Доступен публично на Cachix (мгновенное скачивание для NixOS)
* **Готовые релизы:** Доступны в виде самостоятельных архивов `.tar.zst` в разделе [GitHub Releases](https://github.com/lazyeel/cachyoskernel-bbr3-v3/releases) для любых классических дистрибутивов Linux (Debian, Ubuntu, Arch, Fedora) без необходимости устанавливать Nix.
* **Расписание автоматической сборки в CI:** Ежедневно (`cron: '0 0 * * *'`)

---

## Ключевые особенности и архитектурные решения

### 1. Настоящая реализация Google BBRv3
В официальных ядрах CachyOS 7.x алгоритм BBRv3 был исключен с возвратом к BBRv1. Данный репозиторий возвращает подлинную, полную реализацию **Google BBRv3**:
* Полноценная 4-фазная машина состояний зондирования полосы (`PROBE_BW_UP`, `PROBE_BW_DOWN`, `PROBE_BW_CRUISE`, `PROBE_BW_REFILL`).
* Адаптивные динамические границы (`inflight_hi`, `inflight_lo`, `bw_hi`, `bw_lo`) для контроля задержек очереди и дискриминации потерь пакетов.
* Полная поддержка ECN (совместимость с L4S / AccECN / TCP Prague через макрос `RTAX_FEATURE_ECN_LOW`).
* Нативная интеграция с подсистемой eBPF kfuncs (`__bpf_kfunc static u32 bbr_tso_segs`) и регистрацией идентификаторов в BTF.
* Верифицировано через `modinfo tcp_bbr` (`version: 3`, 9 авторов Google) и таблицу символов рантайма `/proc/kallsyms` (`bbr_skb_marked_lost`).

### 2. Оптимизация под микроархитектуру (`x86-64-v3`)
Скомпилировано компиляторами Clang и GCC с таргетом `x86-64-v3`:
* Аппаратная векторизация AVX2 и быстрые битовые операции BMI2 задействованы во всех подсистемах ядра: хэширование сетевых пакетов (`jhash`, `siphash`), манипуляции буферами sk_buff, криптографические примитивы и обнуление страниц памяти.
* Оптимально для процессоров AMD Zen 2+ (EPYC Rome/Milan/Genoa, Ryzen 3000+) и Intel Haswell+.

### 3. Диспетчеризация и задержки: `PREEMPT_LAZY` и 300 Гц
* **`CONFIG_PREEMPT_LAZY=y`:** Устраняет классический конфликт между пропускной способностью и отзывчивостью. Длительные вычислительные задачи (JVM, декомпилятор Ghidra, компиляция) исполняются с горячим кэшем без холостых прерываний, а чувствительные к задержкам сетевые пакеты (UDP, QUIC, TCP ACK) вызывают немедленное приоритетное вытеснение.
* **Тикрейт 300 Гц (`CONFIG_HZ_300=y`):** Снижает частоту таймерных прерываний и количество выходов из виртуальной машины в гипервизор (KVM VM-Exits) примерно на 40% по сравнению со стандартными десктопными ядрами (500/1000 Гц), сокращая накладные расходы хоста и CPU steal time.

### 4. Управление памятью: THP `[madvise]`
* Режим Transparent Huge Pages переключен в **`madvise`** (`CONFIG_TRANSPARENT_HUGEPAGE_MADVISE=y`).
* Полностью защищает серверы с небольшим объёмом памяти и активным `zram` от катастрофической фрагментации страниц и пауз фонового компактора `khugepaged`, позволяя тяжелым Java-приложениям (Ghidra, базы данных) адресно выделять 2-мегабайтные страницы по запросу.

### 5. Автоматизация CI/CD и защита Fail-Fast
* Сборка выполняется на раннерах GitHub Actions с 16 ГБ RAM и быстрыми накопителями NVMe.
* Защищено встроенным ассертом этапа evaluation (`FAIL-FAST GUARD`): при переходе апстрима CachyOS на новую мажорную ветку (например, 7.4) вычисление мгновенно прерывается до начала сборки, защищая кэш от несовместимых бинарников.

---

## Установка и развёртывание

### Вариант А: Классический Linux (Debian, Ubuntu, Arch, Fedora) — без Nix

Скачайте скомпилированный архив напрямую из раздела [GitHub Releases](https://github.com/lazyeel/cachyoskernel-bbr3-v3/releases):

```bash
# 1. Скачиваем и распаковываем архив последнего релиза
curl -fsSLO https://github.com/lazyeel/cachyoskernel-bbr3-v3/releases/latest/download/linux-cachyos-server-bbr3-7.3.4-cachyos-x86_64-v3.tar.zst
tar --zstd -xf linux-cachyos-server-bbr3-*.tar.zst
cd linux-cachyos-server-bbr3-*

# 2. Запускаем автоматический установщик (копирует ядро, запускает depmod, собирает initramfs и обновляет GRUB)
sudo ./install.sh

# 3. Перезагрузка в новое ядро
sudo reboot
```

---

### Вариант Б: Классический Linux (Debian, Ubuntu, Fedora, Arch)

Если хост работает под управлением стандартного дистрибутива, вы можете использовать автономный пакетный менеджер Nix для получения готового бинарника ядра с последующей интеграцией в `/boot` и `/lib/modules`.

#### 1. Установка Nix (если не установлен)
```bash
curl -L https://nixos.org/nix/install | sh -s -- --daemon
```

#### 2. Подключение Cachix и скачивание готового ядра
```bash
# Установка утилиты cachix
nix-env -iA cachix -f https://cachix.org/api/v1/install
cachix use cachyoskernel-bbr3-v3

# Скачивание готового пакета ядра (занимает ~5 секунд из кэша):
nix build github:lazyeel/cachyoskernel-bbr3-v3#packages.x86_64-linux.kernel --no-link --print-out-paths
```

#### 3. Копирование в `/boot` и `/lib/modules`
```bash
KERNEL_PATH=$(nix build github:lazyeel/cachyoskernel-bbr3-v3#packages.x86_64-linux.kernel --no-link --print-out-paths)
KERNEL_VERSION=$(ls "${KERNEL_PATH}/lib/modules")

# Копируем образ ядра bzImage
sudo cp "${KERNEL_PATH}/bzImage" "/boot/vmlinuz-${KERNEL_VERSION}"

# Копируем дерево модулей
sudo cp -r "${KERNEL_PATH}/lib/modules/${KERNEL_VERSION}" "/lib/modules/"

# Генерация initramfs (в зависимости от дистрибутива):
# Debian/Ubuntu:
sudo update-initramfs -c -k "${KERNEL_VERSION}"
sudo update-grub

# Arch Linux:
# sudo mkinitcpio -k "${KERNEL_VERSION}" -g "/boot/initramfs-${KERNEL_VERSION}.img"
# sudo grub-mkconfig -o /boot/grub/grub.cfg
```

---

### Вариант В: NixOS (Через бинарный кэш Cachix)

#### 1. Подключение входных параметров в `flake.nix`
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
    nixosConfigurations.<имя-хоста> = nixpkgs.lib.nixosSystem {
      system = "x86_64-linux";
      specialArgs = { inherit inputs; };
      modules = [
        ./configuration.nix
      ];
    };
  };
}
```

#### 2. Подключение модуля в `configuration.nix`
```nix
{ config, lib, pkgs, inputs, ... }:

{
  imports = [
    # Подключает готовое ядро, модули и базовые параметры sysctl:
    inputs.cachyos-bbr3-kernel.nixosModules.default
  ];

  # Явное доверие к бинарному кэшу на уровне системы:
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

#### 3. Применение конфигурации
```bash
sudo nixos-rebuild switch
sudo reboot
```

---

## Диагностика и проверка

После загрузки в новое ядро проверьте работу подсистем в рантайме:

```bash
# 1. Проверка версии ядра
uname -r
# Вывод: 7.3.4-cachyos

# 2. Проверка модуля и авторов BBRv3
modinfo tcp_bbr | grep -E "version|author"
# Ожидаемый вывод:
# version:        3
# author:         David Morley, Arjun Roy, Kevin Yang, Yousuk Seung, Priyaranjan Jha, Soheil Hassas Yeganeh, Yuchung Cheng, Neal Cardwell, Van Jacobson

# 3. Проверка активных символов BBRv3 в таблице ядра
sudo grep -E "bbr_skb_marked_lost|bbr_main" /proc/kallsyms

# 4. Телеметрия активных сокетов
sudo ss -tin state established
# В блоке bbr:(...) должны присутствовать параметры minrtt, pacing_gain, cwnd_gain
```

---

## Лицензия

* **Код ядра и патч BBRv3:** Dual BSD/GPLv2 (в соответствии с лицензиями ядра Linux и компании Google).
* **Конфигурация Nix Flake и инфраструктура:** MIT License.

