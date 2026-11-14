# Build host: WSL1 (no virtualization) — resolved

> **Status: solved.** WSL2 is permanently unavailable on this machine: SVM is
> off in firmware and the owner has ruled out BIOS changes. The working local
> path is **WSL1**, which runs Linux binaries on the Windows kernel with no
> hypervisor at all. Confirmed working: `Ubuntu 24.04.5 LTS`, kernel
> `4.4.0-26100-Microsoft`, 4 CPUs, 214 GB free.
>
> Set up with `wsl1-setup.ps1` (repo root) → enable
> `Microsoft-Windows-Subsystem-Linux` → **restart** → import
> `Ubuntu-24.04-Build` from an Ubuntu Base tarball with `--version 1`.
>
> Build with:
> ```
> wsl -d Ubuntu-24.04-Build -- bash -lc \
>   'JOBS=3 bash "/mnt/c/Users/Xerxes Robb Arsolon/Desktop/Reverse/linux/scripts/build-in-wsl.sh"'
> ```
>
> The GitHub Actions workflow remains the fast fallback (real SSD, ~30 min),
> and is the only option if WSL1 is ever removed upstream. **No BIOS change is
> required or permitted.** The rest of this file is the original diagnosis.
>
> ## WSL1 gotchas that bite this build
>
> 1. **Windows PATH leaks into Linux.** WSL1 appends `C:\Program Files\...` to
>    `PATH`; Buildroot aborts with *"Your PATH contains spaces"*. Fixed by
>    `/etc/wsl.conf`:
>    ```
>    [interop]
>    appendWindowsPath = false
>    ```
>    then `wsl --terminate Ubuntu-24.04-Build`. Verify:
>    `wsl -d Ubuntu-24.04-Build -- bash -lc 'echo $PATH'` must be clean.
> 2. **`BR2_EXTERNAL` needs `external.desc`.** Without it every
>    `$(BR2_EXTERNAL_GSAT_PATH)` expands to `/board/...` and the users table
>    and post-build hook silently disappear. The file is
>    `linux/external/external.desc` (`name: GSAT`).
> 3. **Executable bits matter.** Buildroot runs hooks directly. Set them with
>    `git update-index --chmod=+x` and `chmod +x` inside WSL, because NTFS
>    does not carry POSIX modes.
> 4. **Root builds need `FORCE_UNSAFE_CONFIGURE=1`.** An imported distro runs
>    as root, and GNU tar's `configure` aborts with *"you should not run
>    configure as root"*. Exported by `build-in-wsl.sh`.

## Diagnosis (measured on this machine)

```
CPU                              AMD Ryzen 3 3200G (SVM capable)
VirtualizationFirmwareEnabled    False        <-- WSL2 blocker
HypervisorPresent                False
VirtualMachinePlatform           1 (enabled)  <-- Windows side is ready
Microsoft-Windows-Subsystem-Linux 2 (disabled)
HypervisorPlatform               2 (disabled)
RAM                              5.95 GB
```

`wsl --import` and `wsl --install` both fail with:

```
WSL2 is unable to start since virtualization is not enabled on this machine.
Error code: Wsl/Service/RegisterDistro/CreateVm/HCS/HCS_E_HYPERV_NOT_INSTALLED
```

The Windows feature is already installed. The CPU's virtualization extensions are
switched **off in firmware**, so Hyper-V cannot create the utility VM that every
WSL2 distro runs inside. No amount of `wsl` configuration fixes that from
Windows; it must be changed in the BIOS.

## Fix — enable SVM (one reboot)

1. Reboot and press **Del** at the Gigabyte splash to enter BIOS.
2. Go to **M.I.T.** → **Advanced Frequency Settings** → **Advanced CPU Settings**.
   (On some A320M-S2H V2 BIOS revisions it is **Peripherals** → **SVM Mode**.)
3. Set **SVM Mode** to **Enabled**.
4. **F10** → save and exit.
5. Back in Windows, confirm:

```powershell
(Get-CimInstance Win32_Processor).VirtualizationFirmwareEnabled   # expect True
(Get-CimInstance Win32_ComputerSystem).HypervisorPresent          # expect True
```

Then the import works:

```powershell
wsl --import Ubuntu-24.04 "$env:LOCALAPPDATA\wsl\Ubuntu-24.04" `
    "$env:TEMP\opencode\ubuntu-base-24.04.5-base-amd64.tar.gz" --version 2
wsl -d Ubuntu-24.04 -u root -- bash -lc 'cat /etc/os-release | head -2'
```

Expect `Ubuntu 24.04.5 LTS (Noble Numbat)`.

## Why not the Store distro

`wsl --install -d Ubuntu-24.04` needs the same hypervisor. It is not an
alternative path, only a different front end, and it additionally wants
elevation to touch the optional-feature state.

## Memory

5.95 GB total. Give WSL2 explicit limits so a parallel Buildroot build does not
push Windows into swap. Create `C:\Users\<you>\.wslconfig`:

```ini
[wsl2]
memory=4GB
processors=4
swap=2GB
localhostForwarding=true
```

Then `wsl --shutdown` and start the distro again.

Build with `-j4` (3300G has 4 cores); more jobs than cores on 6 GB will thrash.

## If SVM cannot be enabled

Options that do not need virtualization on this box:

1. Build on any other Linux machine, a spare laptop, or a VPS. The tree is
   self-contained: `make` needs only a Linux host with a compiler.
2. GitHub Actions `ubuntu-latest` runner: the repo builds an image in ~25 min and
   uploads `output/images/` as an artifact.
3. Cross-build on Windows with MSYS2: **not viable** — Buildroot and the kernel
   build system both assume a POSIX host, and the toolchain bootstrap fails.

The QEMU demo itself also prefers hardware virtualization, but
`qemu-system-arm` with software emulation is fine for a one-core ARMv6 guest;
it just boots slower.
