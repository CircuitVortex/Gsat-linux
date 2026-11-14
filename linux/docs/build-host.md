# Build host: why WSL2 can't start, and the fix

> **Status: local WSL2 route abandoned.** Enabling SVM requires a BIOS setting
> change, which the machine's owner has explicitly declined. No firmware or
> BIOS settings are to be modified. The supported path is the GitHub Actions
> workflow in `.github/workflows/build-gsat-linux.yml`, which needs no
> virtualization and no BIOS access. The rest of this file is kept as a record
> of the diagnosis only — do not act on the BIOS section.

## Diagnosis (measured on this machine)

```
CPU                              AMD Ryzen 3 3200G (SVM capable)
VirtualizationFirmwareEnabled    False        <-- blocker
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
