# Couti Installer storage service. GPL-3.0-or-later. No action runs without a request.
param([Parameter(Mandatory=$true)][string]$Request)
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
$job = Get-Content -LiteralPath $Request -Raw | ConvertFrom-Json
$script:bootSize = 100MB
$script:basicGuid = '{EBD0A0A2-B9E5-4433-87C0-68B6B72699C7}'
$script:efiGuid = '{C12A7328-F81F-11D2-BA4B-00A0C93EC93B}'
$script:work = Split-Path -Parent $Request
$script:installPhase = 'Checking the selected drive'

function Save-Reply($value) {
    $value | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $job.Result -Encoding UTF8
}
function Get-SelectedDisk {
    param([switch]$AcceptNewUniqueId)
    $disk = Get-Disk -Number ([int]$job.Disk.Number)
    if ($disk.IsBoot -or $disk.IsSystem -or $disk.IsOffline -or $disk.IsReadOnly -or
        $disk.Size -ne [long]$job.Disk.Size -or
        ([string]$disk.Path) -cne ([string]$job.Disk.DevicePath) -or
        (!$AcceptNewUniqueId -and ([string]$disk.UniqueId).Trim() -cne ([string]$job.Disk.UniqueId).Trim()) -or
        ([string]$disk.SerialNumber).Trim() -cne ([string]$job.Disk.Serial).Trim()) {
        throw 'The selected device changed, is unavailable, or contains the running Windows system. Refresh and select the intended drive.'
    }
    if ($disk.LogicalSectorSize -ne 512) { throw 'This installer requires a disk with 512-byte logical sectors.' }
    if ($disk.BusType -in @('Spaces','iSCSI','RAID')) { throw 'Storage Spaces, RAID and network-backed disks are not supported.' }
    # Only the explicit formatting transition may change a provider's disk ID.
    # The physical path, serial, capacity and OS-disk exclusions still must match.
    if ($AcceptNewUniqueId) { $job.Disk.UniqueId = ([string]$disk.UniqueId).Trim() }
    return $disk
}
function Get-Parts($disk) { return @(Get-CimAssociatedInstance -InputObject $disk -ResultClassName MSFT_Partition -ErrorAction Stop | Sort-Object Offset) }
function Set-InstallPhase([string]$phase) {
    $script:installPhase = $phase
    ('{0:o}  {1}' -f [DateTime]::UtcNow,$phase) | Out-Host
    @{ Phase=$phase; DiskNumber=$job.Disk.Number; TimeUtc=[DateTime]::UtcNow.ToString('o') } |
        ConvertTo-Json | Set-Content -LiteralPath (Join-Path $script:work 'install-progress.json') -Encoding UTF8
}
function Refresh-FormatDisk {
    $disk = Get-SelectedDisk -AcceptNewUniqueId
    Update-Disk -InputObject $disk | Out-Null
    return (Get-SelectedDisk -AcceptNewUniqueId)
}
function Initialize-FormatLayout([string]$style) {
    # Clear-Disk can leave removable media initialized as an empty MBR disk.
    # Always re-read its state; Initialize-Disk is valid only for RAW media.
    $disk = Get-SelectedDisk
    Set-InstallPhase 'Preparing the partition table'
    if (@(Get-Parts $disk).Count -gt 0) {
        Clear-Disk -InputObject $disk -RemoveData -RemoveOEM -Confirm:$false
    }
    $disk = Refresh-FormatDisk
    if (@(Get-Parts $disk).Count -gt 0) { throw 'The selected drive still has partitions after clearing. Partition creation stopped.' }
    if ($disk.PartitionStyle -eq 'RAW') {
        try {
            Initialize-Disk -InputObject $disk -PartitionStyle $style -Confirm:$false | Out-Null
        } catch {
            $initializationError = $_
            # A storage provider can report RAW just before returning 41001.
            # Accept that specific race only if a fresh read shows the desired style.
            $alreadyInitialized = $initializationError.FullyQualifiedErrorId -match '(^|\D)41001(\D|$)'
            if (!$alreadyInitialized -and $initializationError.Exception.PSObject.Properties['NativeErrorCode']) {
                $alreadyInitialized = $initializationError.Exception.NativeErrorCode -eq 41001
            }
            $disk = Refresh-FormatDisk
            if (!$alreadyInitialized -or [string]$disk.PartitionStyle -ne $style) { throw $initializationError }
        }
    } elseif ([string]$disk.PartitionStyle -ne $style) {
        if ($disk.PartitionStyle -notin @('MBR','GPT')) { throw 'Windows returned an unsupported partition style after clearing.' }
        # Conversion is allowed only on the empty disk from this FORMAT operation.
        Set-Disk -InputObject $disk -PartitionStyle $style | Out-Null
    }
    $disk = Refresh-FormatDisk
    if ([string]$disk.PartitionStyle -ne $style) { throw 'Windows did not prepare the requested partition style.' }
    # Some providers create an MSR during GPT initialization. It belongs to this
    # new, explicitly formatted layout; remove it before making data 1 / boot 2.
    foreach ($reserved in @(Get-Parts $disk)) {
        if ($style -eq 'GPT' -and $reserved.GptType -eq '{E3C9E316-0B5C-4DB8-817D-F92DF00215AE}') {
            Remove-Partition -InputObject $reserved -Confirm:$false
        } else { throw 'An unexpected partition appeared during initialization. Installation stopped.' }
    }
    $disk = Refresh-FormatDisk
    if (@(Get-Parts $disk).Count -ne 0) { throw 'The drive is not empty after preparing the partition table.' }
    return $disk
}
function Get-PartVolume($part) {
    return $part | Get-Volume -ErrorAction SilentlyContinue | Select-Object -First 1
}
function Get-VolumeRoot($part) {
    $vol = Get-PartVolume $part
    if (!$vol) { return $null }
    if ($vol.DriveLetter) { return ([string]$vol.DriveLetter + ':\') }
    if ($vol.Path) { return [string]$vol.Path }
    return $null
}
function Get-CoutiParts($disk) {
    if ($disk.PartitionStyle -eq 'RAW') { return }
    Load-RawAccess
    foreach ($part in (Get-Parts $disk)) {
        $vol = Get-PartVolume $part
        if (!$vol -or $vol.FileSystem -notin @('FAT','FAT32') -or $part.Size -gt 512MB) { continue }
        $root = Get-VolumeRoot $part
        if (!$root) { continue }
        # Names alone are insufficient: require the loader, config, and boot archive.
        if ([Couti.RawDisk]::FileExists($root + 'EFI\BOOT\BOOTX64.EFI') -and
            [Couti.RawDisk]::FileExists($root + 'grub\grub.cfg') -and
            ([Couti.RawDisk]::FileExists($root + 'couti\couti.cpio') -or
             [Couti.RawDisk]::FileExists($root + 'ventoy\ventoy.cpio'))) {
            [pscustomobject]@{ Part = $part; Root = $root; Volume = $vol }
        }
    }
}
function Get-Inspection($disk) {
    if ($disk.PartitionStyle -eq 'RAW') { return @{ Present=$false; RequiresFormat=$true; Details='Select Format drive to create Gabulhi and COUTI.'; Layout='Uninitialized drive - no usable partitions.' } }
    $parts = @(Get-Parts $disk)
    if ($parts.Count -eq 0) { return @{ Present=$false; RequiresFormat=$true; Details='Select Format drive to create Gabulhi and COUTI.'; Layout='No partitions - the drive has no readable data volume.' } }
    $found = @(Get-CoutiParts $disk)
    $lines = foreach ($part in $parts) {
        $vol = Get-PartVolume $part
        $label = if ($vol -and $vol.FileSystemLabel) { $vol.FileSystemLabel } else { 'Unlabeled' }
        $fs = if ($vol) { $vol.FileSystem } else { $part.Type }
        $letter = if ($part.DriveLetter) { " $($part.DriveLetter):" } else { '' }
        'Partition {0}{1}  |  {2}  |  {3}  |  {4:0.##} GB' -f $part.PartitionNumber,$letter,$label,$fs,($part.Size / 1GB)
    }
    return @{ Present = ($found.Count -gt 0); Details = ''; Layout = ($lines -join "`r`n") }
}
function Assert-Layout($disk) {
    if ($disk.PartitionStyle -notin @('MBR','GPT')) { throw 'The disk has no supported partition table. Select Format drive to initialize it explicitly.' }
    $parts = Get-Parts $disk
    if (!$parts.Count) { throw 'No existing data partition was found. Select Format drive to create the requested layout.' }
    if ($parts[0].Offset -lt 1MB) { throw 'There is not enough space before the first partition for BIOS boot. Existing data was not changed. A fresh layout requires Format drive.' }
    if ($disk.PartitionStyle -eq 'MBR') {
        if ($parts.Count -ge 4 -or @($parts | Where-Object { $_.MbrType -in @(5,15,66,133) }).Count) {
            throw 'This MBR layout has no safe primary partition slot, or uses extended/dynamic partitions. No partitions were changed.'
        }
    }
    if ($disk.PartitionStyle -eq 'GPT' -and @($parts | Where-Object { $_.GptType -in @('{5808C8AA-7E8F-42E0-85D2-E1E90434CFB3}', '{AF9B60A0-1431-4F62-BC68-3311714A69AD}') }).Count) {
        throw 'Dynamic disks are not supported.'
    }
}
function Align-Down([long]$value) { return $value - ($value % 1MB) }
function Align-Up([long]$value) { return (Align-Down ($value + 1MB - 1)) }
function Find-FreeExtent($disk) {
    $parts = Get-Parts $disk
    $end = Align-Down ([long]$disk.Size - 1MB)
    # Prefer space immediately after the largest partition; then any unused extent.
    foreach ($part in ($parts | Sort-Object Size -Descending)) {
        $start = Align-Up ([long]$part.Offset + [long]$part.Size)
        $next = $parts | Where-Object Offset -ge $start | Select-Object -First 1
        $limit = if ($next) { [long]$next.Offset } else { $end }
        if ($limit - $start -ge $script:bootSize) { return $start }
    }
    # Never consume the first MiB reserved for the partition table and BIOS loader.
    if ($parts[0].Offset - 1MB -ge $script:bootSize) { return 1MB }
    return $null
}
function Find-ShrinkPlan($disk) {
    $candidates = @()
    foreach ($part in (Get-Parts $disk)) {
        $vol = Get-PartVolume $part
        if (!$vol -or $vol.FileSystem -ne 'NTFS' -or $vol.SizeRemaining -lt $script:bootSize -or
            $part.IsBoot -or $part.IsSystem -or $part.IsReadOnly -or $part.IsHidden -or
            ($disk.PartitionStyle -eq 'GPT' -and $part.GptType -ne $script:basicGuid)) { continue }
        $candidates += [pscustomobject]@{ Part = $part; Free = [long]$vol.SizeRemaining; Volume = $vol }
    }
    # First the largest eligible partition, then others with most free space.
    $largest = $candidates | Sort-Object { $_.Part.Size } -Descending | Select-Object -First 1
    $ordered = @()
    if ($largest) {
        $ordered += $largest
        $ordered += @($candidates | Where-Object { $_.Part.PartitionNumber -ne $largest.Part.PartitionNumber } | Sort-Object Free -Descending)
    }
    foreach ($candidate in $ordered) {
        try {
            $part = $candidate.Part
            # Reject BitLocker volumes even if currently unlocked; never shrink encrypted data automatically.
            $encryptionVolume = Get-CimInstance -Namespace 'root/CIMV2/Security/MicrosoftVolumeEncryption' -ClassName Win32_EncryptableVolume -ErrorAction SilentlyContinue |
                Where-Object { $_.DeviceID -eq $candidate.Volume.Path }
            if ($encryptionVolume) {
                $conversion = Invoke-CimMethod -InputObject $encryptionVolume -MethodName GetConversionStatus
                if ($conversion.ReturnValue -ne 0 -or $conversion.ConversionStatus -ne 0) { continue }
            }
            $supported = Get-PartitionSupportedSize -DiskNumber $disk.Number -PartitionNumber $part.PartitionNumber
            $size = Align-Down ([long]$part.Size - $script:bootSize)
            if ($size -ge $supported.SizeMin -and $size -gt 0) {
                return [pscustomobject]@{ Part = $part; NewSize = $size; Offset = ([long]$part.Offset + $size) }
            }
        } catch { Write-Output "Partition $($candidate.Part.PartitionNumber) cannot be shrunk safely: $($_.Exception.Message)" | Out-Host }
    }
    throw 'No suitable free extent or safely shrinkable NTFS partition was found on this drive. Existing files and labels were not changed. Free space inside exFAT/FAT32 cannot be shrunk by Windows. Formatting is never selected automatically.'
}
function Mount-Boot($part) {
    $mount = Join-Path $script:work ('mount-' + [guid]::NewGuid().ToString('N'))
    [void](New-Item -ItemType Directory -Path $mount)
    Add-PartitionAccessPath -DiskNumber $part.DiskNumber -PartitionNumber $part.PartitionNumber -AccessPath ($mount + '\') | Out-Null
    return ($mount + '\')
}
function Unmount-Boot($part, $mount) {
    Remove-PartitionAccessPath -DiskNumber $part.DiskNumber -PartitionNumber $part.PartitionNumber -AccessPath $mount -ErrorAction SilentlyContinue
}
function Load-RawAccess {
    if ('Couti.RawDisk' -as [type]) { return }
    Add-Type -TypeDefinition @'
using System;
using System.IO;
using System.Collections.Generic;
using System.ComponentModel;
using System.Runtime.InteropServices;
using Microsoft.Win32.SafeHandles;
namespace Couti {
 public static class RawDisk {
  [DllImport("kernel32.dll", CharSet=CharSet.Unicode, SetLastError=true)] static extern uint GetFileAttributes(string path);
  public static bool FileExists(string path) { uint a=GetFileAttributes(path); return a!=0xFFFFFFFF && (a&16)==0; }
  [DllImport("kernel32.dll", CharSet=CharSet.Unicode, SetLastError=true)] static extern SafeFileHandle CreateFile(string n, uint a, uint s, IntPtr sec, uint c, uint f, IntPtr t);
  [DllImport("kernel32.dll", SetLastError=true)] static extern bool DeviceIoControl(SafeFileHandle h, uint c, IntPtr i, uint il, IntPtr o, uint ol, out uint done, IntPtr ov);
  static FileStream Open(int disk, bool write) {
   var h = CreateFile(@"\\.\PhysicalDrive" + disk, write ? 0xC0000000u : 0x80000000u, 3, IntPtr.Zero, 3, 0, IntPtr.Zero);
   if(h.IsInvalid) throw new Win32Exception(Marshal.GetLastWin32Error());
   return new FileStream(h, write ? FileAccess.ReadWrite : FileAccess.Read, 4096, false);
  }
  public static byte[] Read(int disk, long offset, int count) {
   using(var f=Open(disk,false)) { f.Position=offset; var b=new byte[count]; int pos=0,n; while(pos<count && (n=f.Read(b,pos,count-pos))>0)pos+=n; if(pos!=count)throw new IOException("Incomplete disk read"); return b; }
  }
  public static void Bootstrap(int disk, string[] volumes, byte[] mbr, byte[] core, bool gpt) {
   if(mbr.Length!=512 || core.Length<1048576-512)throw new IOException("Invalid boot payload length");
   var locks=new List<SafeFileHandle>(); uint done;
   try {
    foreach(string v in volumes) {
     var h=CreateFile(v.TrimEnd('\\'),0xC0000000u,3,IntPtr.Zero,3,0,IntPtr.Zero);
     if(h.IsInvalid)throw new Win32Exception(Marshal.GetLastWin32Error());
     locks.Add(h);
     if(!DeviceIoControl(h,0x00090018,IntPtr.Zero,0,IntPtr.Zero,0,out done,IntPtr.Zero))throw new IOException("Could not lock a selected-drive volume. Close programs using this drive and retry.");
    }
    using(var f=Open(disk,true)) {
     var sector=new byte[512]; if(f.Read(sector,0,512)!=512)throw new IOException("Could not read MBR");
     Buffer.BlockCopy(mbr,0,sector,0,440); // keep the disk signature and all partition entries
     int start=gpt?34:1;
     f.Position=start*512; f.Write(core,0,1048576-start*512); f.Flush(true);
     f.Position=0; f.Write(sector,0,512); f.Flush(true);
    }
   } finally { foreach(var h in locks) { DeviceIoControl(h,0x0009001C,IntPtr.Zero,0,IntPtr.Zero,0,out done,IntPtr.Zero); h.Dispose(); } }
  }
 }
}
'@
}
function Backup-Boot($disk) {
    Load-RawAccess
    $bytes = [Couti.RawDisk]::Read($disk.Number, 0, 1MB)
    $path = Join-Path $script:work 'original-first-mib.bin'
    [IO.File]::WriteAllBytes($path, $bytes)
    $disk | Select-Object Number,UniqueId,SerialNumber,Size,PartitionStyle | ConvertTo-Json | Set-Content (Join-Path $script:work 'device-before.json')
    if ($disk.PartitionStyle -ne 'RAW') { Get-Parts $disk | Select-Object PartitionNumber,Offset,Size,Guid,GptType,MbrType | ConvertTo-Json | Set-Content (Join-Path $script:work 'partitions-before.json') }
    return $path
}
function Volume-Handles($disk) {
    return @((Get-Parts $disk | Get-Volume -ErrorAction SilentlyContinue | Where-Object Path | Select-Object -ExpandProperty Path -Unique))
}
function Install-Couti {
    $disk = Get-SelectedDisk
    if (@(Get-CoutiParts $disk).Count -and !$job.Format) { throw 'Couti is already present. Remove it first, or explicitly select Format drive.' }
    if ($job.Format -and $job.Confirmation -cne 'FORMAT') { throw 'Formatting requires the exact confirmation FORMAT.' }
    $package = [IO.Path]::GetFullPath([string]$job.Package)
    $packageDrive = [IO.Path]::GetPathRoot($package).TrimEnd('\').TrimEnd(':')
    if ($packageDrive.Length -eq 1 -and @(Get-Partition -DriveLetter $packageDrive -ErrorAction SilentlyContinue | Where-Object DiskNumber -eq $disk.Number).Count) {
        throw 'Extract and run the installer from your computer, not from the drive being installed.'
    }
    $payload = Join-Path $package 'boot-files'
    foreach ($required in @('grub\grub.cfg','couti\couti.cpio','EFI\BOOT\BOOTX64.EFI')) {
        if (!(Test-Path -LiteralPath (Join-Path $payload $required))) { throw 'Boot files are missing. Extract the entire installer ZIP before running Couti Installer.' }
    }
    $mbr = [IO.File]::ReadAllBytes((Join-Path $package 'boot\boot.img'))
    $core = [IO.File]::ReadAllBytes((Join-Path $package 'boot\core.img'))
    if ($mbr.Length -ne 512 -or $core.Length -ne (1MB - 512)) { throw 'Boot payload size is invalid. Re-extract the package.' }
    $payloadBytes = (Get-ChildItem -LiteralPath $payload -Recurse -File | Measure-Object Length -Sum).Sum
    $helperPath = Join-Path $package 'USB-FILES\ventoy\ventoy_vhdboot.img'
    if (Test-Path -LiteralPath $helperPath) { $payloadBytes += (Get-Item -LiteralPath $helperPath).Length }
    if ($payloadBytes -gt ($script:bootSize - 8MB)) { throw 'Boot files exceed the available space in the 100 MB partition.' }
    if ($disk.Size -lt ($script:bootSize + 66MB)) { throw 'This drive is too small for the requested layout.' }
    $plan = $null; $offset = $null
    if (!$job.Format) {
        Assert-Layout $disk
        $offset = Find-FreeExtent $disk
        if ($null -eq $offset) { $plan = Find-ShrinkPlan $disk; $offset = $plan.Offset }
    }
    $backup = Backup-Boot $disk
    if (!$job.Format -and $disk.PartitionStyle -eq 'GPT') {
        $header = [Couti.RawDisk]::Read($disk.Number,512,512)
        if ([BitConverter]::ToUInt64($header,72) -ne 2 -or [BitConverter]::ToUInt32($header,80) -ne 128 -or [BitConverter]::ToUInt32($header,84) -ne 128) { throw 'This GPT layout uses a nonstandard table size. No partitions were changed.' }
    }
    $disk = Get-SelectedDisk
    $boot = $null; $mount = $null; $shrunk = $false; $installed = $false; $bootstrapStarted = $false; $formatStarted = $false; $dataFormatted = $false
    try {
        if ($job.Format) {
            $style = if ($disk.PartitionStyle -eq 'GPT' -or $disk.Size -gt 2TB) { 'GPT' } else { 'MBR' }
            $formatStarted = $true
            $disk = Initialize-FormatLayout $style
            $offset = Align-Down ([long]$disk.Size - $script:bootSize - 1MB)
            $dataSize = $offset - 1MB
            Set-InstallPhase 'Creating the Gabulhi data partition'
            $partitionArgs = @{ DiskNumber=$disk.Number; Offset=1MB; Size=$dataSize }
            if ($style -eq 'GPT') { $partitionArgs.GptType=$script:basicGuid } else { $partitionArgs.MbrType='IFS'; $partitionArgs.IsActive=$true }
            $data = New-Partition @partitionArgs
            Set-InstallPhase 'Formatting Gabulhi as NTFS'
            Format-Volume -Partition $data -FileSystem NTFS -NewFileSystemLabel 'Gabulhi' -Force -Confirm:$false | Out-Null
            $dataFormatted = $true
            Add-PartitionAccessPath -DiskNumber $disk.Number -PartitionNumber $data.PartitionNumber -AssignDriveLetter | Out-Null
        } elseif ($plan) {
            Set-InstallPhase 'Shrinking the selected data partition'
            Resize-Partition -DiskNumber $disk.Number -PartitionNumber $plan.Part.PartitionNumber -Size $plan.NewSize -Confirm:$false
            $shrunk = $true
        }
        $disk = Get-SelectedDisk
        Set-InstallPhase 'Creating the COUTI boot partition'
        $partitionArgs = @{ DiskNumber=$disk.Number; Offset=[long]$offset; Size=$script:bootSize; Alignment=1MB }
        if ($disk.PartitionStyle -eq 'GPT') { $partitionArgs.GptType=$script:basicGuid } else { $partitionArgs.MbrType='FAT32' }
        $boot = New-Partition @partitionArgs
        if ($disk.PartitionStyle -eq 'MBR' -and !(Get-Parts $disk | Where-Object IsActive)) { Set-Partition -DiskNumber $disk.Number -PartitionNumber $boot.PartitionNumber -IsActive $true }
        Set-InstallPhase 'Formatting COUTI as FAT32'
        Format-Volume -Partition $boot -FileSystem FAT32 -AllocationUnitSize 512 -NewFileSystemLabel 'COUTI' -Force -Confirm:$false | Out-Null
        $mount = Mount-Boot $boot
        Set-InstallPhase 'Copying the Couti boot files'
        # Explicit root contents: never delete or overwrite anything on a data partition.
        Get-ChildItem -LiteralPath $payload -Force | Copy-Item -Destination $mount -Recurse -Force
        Copy-Item -LiteralPath $backup -Destination (Join-Path $mount 'couti\original-first-mib.bin')
        $record = @{ Schema=1; DiskId=$disk.UniqueId; DiskSize=[long]$disk.Size; BootOffset=[long]$boot.Offset; BootSize=[long]$boot.Size; BootPartition=[int]$boot.PartitionNumber; Formatted=[bool]$job.Format; OriginalStyle=[string]$job.Disk.Style }
        $record | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $mount 'couti\install.json') -Encoding UTF8
        # Retain the VHD helper on the boot partition, so existing data files need not be changed.
        $helper = Join-Path $package 'USB-FILES\ventoy\ventoy_vhdboot.img'
        if (Test-Path -LiteralPath $helper) { Copy-Item -LiteralPath $helper -Destination (Join-Path $mount 'couti\couti_vhdboot.img') }
        Unmount-Boot $boot $mount; $mount=$null
        if ($disk.PartitionStyle -eq 'GPT') { Set-Partition -DiskNumber $disk.Number -PartitionNumber $boot.PartitionNumber -GptType $script:efiGuid }
        $disk = Get-SelectedDisk
        if ($disk.PartitionStyle -eq 'GPT') { $mbr[92]=0x22; $core[500]=35 }
        $uuid = [guid]::NewGuid().ToByteArray()
        [Array]::Copy($uuid,0,$mbr,0x180,16)
        $bootstrapStarted = $true
        Set-InstallPhase 'Writing the BIOS boot loader'
        [Couti.RawDisk]::Bootstrap($disk.Number, (Volume-Handles $disk), $mbr, $core, ($disk.PartitionStyle -eq 'GPT'))
        $installed = $true
        Set-InstallPhase 'Installation complete'
        return 'Couti installed. The boot partition is COUTI (100 MB FAT32). ' + $(if ($job.Format) { 'The data partition is Gabulhi (NTFS).' } else { 'Existing data labels and files were preserved.' }) + "`r`nBoot backups and operation logs: $script:work"
    } catch {
        $failure = $_
        $failure | Format-List * -Force | Out-String -Width 240 | Set-Content -LiteralPath (Join-Path $script:work 'storage-error.txt') -Encoding UTF8
        $reason = 'Installation stopped while ' + $script:installPhase.ToLowerInvariant() + ":`r`n" + $failure.Exception.Message
        # Roll back only objects created by this invocation, using recorded identity and offsets.
        if (!$installed -and !$job.Format) {
            try {
                $disk = Get-SelectedDisk
                if ($mount -and $boot) { Unmount-Boot $boot $mount; $mount=$null }
                if ($bootstrapStarted) {
                    $saved = [IO.File]::ReadAllBytes($backup)
                    $savedMbr = New-Object byte[] 512; [Array]::Copy($saved,0,$savedMbr,0,512)
                    $savedCore = New-Object byte[] (1MB-512)
                    $start = if ($disk.PartitionStyle -eq 'GPT') { 34*512 } else { 512 }
                    [Array]::Copy($saved,$start,$savedCore,0,1MB-$start)
                    [Couti.RawDisk]::Bootstrap($disk.Number,(Volume-Handles $disk),$savedMbr,$savedCore,($disk.PartitionStyle -eq 'GPT'))
                }
                if ($boot) {
                    $current = Get-Partition -DiskNumber $disk.Number -PartitionNumber $boot.PartitionNumber
                    if ($current.Offset -ne $boot.Offset -or $current.Size -ne $script:bootSize) { throw 'Partition identity changed during rollback.' }
                    Remove-Partition -InputObject $current -Confirm:$false
                }
                if ($shrunk) { Resize-Partition -DiskNumber $disk.Number -PartitionNumber $plan.Part.PartitionNumber -Size $plan.Part.Size -Confirm:$false }
            } catch { $reason += "`r`nAutomatic rollback could not complete: $($_.Exception.Message). Backups: $script:work" }
        }
        if ($formatStarted) {
            if ($dataFormatted) {
                $reason += "`r`nGabulhi was formatted, but Couti installation did not finish."
            } else {
                $reason += "`r`nFormatting did not finish. The drive may have no readable data partition."
            }
            $reason += "`r`nThe previous partition layout has not been restored."
        }
        $reason += "`r`nDetails and boot metadata backup: $script:work"
        throw $reason
    } finally { if ($mount -and $boot) { Unmount-Boot $boot $mount } }
}
function Remove-Couti {
    $disk = Get-SelectedDisk
    $found = @(Get-CoutiParts $disk)
    if ($found.Count -ne 1) { throw 'A single Couti boot partition could not be identified. No partitions were removed.' }
    $item = $found[0]; $boot=$item.Part; $mount=Mount-Boot $boot
    $saved=$null; $record=$null
    try {
        $recordPath=Join-Path $mount 'couti\install.json'
        $backupPath=Join-Path $mount 'couti\original-first-mib.bin'
        if ((Test-Path -LiteralPath $recordPath) -and (Test-Path -LiteralPath $backupPath)) {
            $record=Get-Content -LiteralPath $recordPath -Raw | ConvertFrom-Json
            if ($record.DiskId -ne $disk.UniqueId -or $record.BootOffset -ne $boot.Offset -or $record.BootSize -ne $boot.Size) { throw 'The installation record does not match this partition. Nothing was removed.' }
            $saved=[IO.File]::ReadAllBytes($backupPath)
            if ($saved.Length -ne 1MB) { throw 'The original boot backup is incomplete.' }
        }
    } finally { Unmount-Boot $boot $mount }
    $backup=Backup-Boot $disk
    $current=[IO.File]::ReadAllBytes($backup)
    $expected=[IO.File]::ReadAllBytes((Join-Path $job.Package 'boot\boot.img'))
    foreach ($index in @(0..47) + @(400..415)) {
        if ($current[$index] -ne $expected[$index]) { throw 'The disk boot code does not match Couti. Removal stopped to preserve the other boot loader.' }
    }
    $mbr=New-Object byte[] 512; [Array]::Copy($current,0,$mbr,0,512)
    $core=New-Object byte[] (1MB-512)
    $start=if ($disk.PartitionStyle -eq 'GPT') { 34*512 } else { 512 }
    # Old installations cannot restore a boot loader that was never backed up.
    # Clear only Couti's bootstrap; preserve every partition entry and data volume.
    if ($saved -and !$record.Formatted -and $record.OriginalStyle -eq $disk.PartitionStyle) {
        [Array]::Copy($saved,0,$mbr,0,440)
        [Array]::Copy($saved,$start,$core,0,1MB-$start)
    } else {
        [Array]::Clear($mbr,0,440)
    }
    $disk=Get-SelectedDisk
    [Couti.RawDisk]::Bootstrap($disk.Number,(Volume-Handles $disk),$mbr,$core,($disk.PartitionStyle -eq 'GPT'))
    $currentPart=Get-Partition -DiskNumber $disk.Number -PartitionNumber $boot.PartitionNumber
    if ($currentPart.Offset -ne $boot.Offset -or $currentPart.Size -ne $boot.Size) { throw 'Partition identity changed; removal stopped.' }
    Remove-Partition -InputObject $currentPart -Confirm:$false
    return "Couti removed. Data partitions and their labels were preserved. The boot partition's space is now unallocated.`r`nBoot backups and operation logs: $script:work"
}

try {
    Import-Module Storage -ErrorAction Stop
    switch ([string]$job.Operation) {
        'List' {
            $disks=@(Get-Disk | Where-Object { !$_.IsBoot -and !$_.IsSystem -and !$_.IsOffline -and !$_.IsReadOnly -and $_.Size -ge 256MB -and $_.BusType -notin @('Spaces','iSCSI','RAID') } | ForEach-Object {
                @{ Number=[int]$_.Number; Name=[string]$_.FriendlyName; UniqueId=([string]$_.UniqueId).Trim(); Serial=([string]$_.SerialNumber).Trim(); Size=[long]$_.Size; Style=[string]$_.PartitionStyle; DevicePath=[string]$_.Path }
            })
            Save-Reply @{ Ok=$true; Disks=$disks }
        }
        'Inspect' { $disk=Get-SelectedDisk; Save-Reply @{ Ok=$true; Inspection=(Get-Inspection $disk) } }
        'Install' { Save-Reply @{ Ok=$true; Message=(Install-Couti) } }
        'Remove' { Save-Reply @{ Ok=$true; Message=(Remove-Couti) } }
        default { throw 'Unknown installer operation.' }
    }
} catch {
    $_ | Format-List * -Force | Out-String -Width 240 | Set-Content -LiteralPath (Join-Path $script:work 'operation-error.txt') -Encoding UTF8
    Save-Reply @{ Ok=$false; Message=$_.Exception.Message }
    exit 1
}
