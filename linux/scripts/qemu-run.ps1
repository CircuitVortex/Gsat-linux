# Boot the built image under QEMU on Windows (requires QEMU for Windows on PATH).
$ErrorActionPreference = 'Stop'
$here = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
$img  = Join-Path $here 'output\images'

foreach ($f in 'zImage', 'versatile-pb.dtb', 'rootfs.ext2') {
    if (-not (Test-Path (Join-Path $img $f))) {
        throw "missing $img\$f - build it first (make / buildroot)"
    }
}

$qemu = (Get-Command qemu-system-arm -ErrorAction SilentlyContinue).Source
if (-not $qemu) { throw 'qemu-system-arm not found on PATH' }

& $qemu -M versatilepb -cpu arm1176 -m 256M `
    -kernel (Join-Path $img 'zImage') `
    -dtb (Join-Path $img 'versatile-pb.dtb') `
    -drive "file=$(Join-Path $img 'rootfs.ext2'),if=scsi,format=raw" `
    -append 'rootwait root=/dev/sda rw console=ttyAMA0,115200' `
    -net nic,model=rtl8139 -net user,hostfwd=tcp::2222-:22 `
    -nographic
