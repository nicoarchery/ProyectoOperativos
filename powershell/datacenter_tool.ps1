#Requires -Version 5.1

$ScriptVersion = "1.0.0"


# --- Helpers -----------------------------------------------------------------

function Format-Bytes {
    param([long]$Bytes)
    if ($Bytes -ge 1GB) { return "{0:N2} GB" -f ($Bytes / 1GB) }
    return "{0:N2} MB" -f ($Bytes / 1MB)
}

function ConvertFrom-DmtfDate {
    param([string]$Dmtf)
    if ([string]::IsNullOrWhiteSpace($Dmtf) -or $Dmtf -eq '0') { return $null }
    try {
        return [System.Management.ManagementDateTimeConverter]::ToDateTime($Dmtf)
    }
    catch { return $null }
}

function Get-UserRid {
    param([string]$Sid)
    return [int]($Sid.Split('-')[-1])
}


# --- Menu --------------------------------------------------------------------

function Show-Menu {
    Clear-Host
    $border = "=" * 48
    $half   = "-" * 48
    Write-Host $border
    Write-Host " Data Center Administration Tool - PowerShell v$ScriptVersion"
    Write-Host $border
    Write-Host " 1. Usuarios del sistema y ultimo login"
    Write-Host " 2. Filesystems / Discos conectados"
    Write-Host " 3. Archivos mas grandes en un filesystem"
    Write-Host " 4. Memoria libre y swap"
    Write-Host " 5. Backup de directorio a USB"
    Write-Host $half
    Write-Host " 0. Salir"
    Write-Host $border
    Write-Host ""
}


# --- Opcion 1: Usuarios y ultimo login ---------------------------------------

function Invoke-Option1 {
    Write-Host ("=" * 48)
    Write-Host " USUARIOS DEL SISTEMA Y ULTIMO LOGIN"
    Write-Host ("=" * 48)
    Write-Host ("{0,-25} {1,-22}" -f "USUARIO", "ULTIMO LOGIN")
    Write-Host ("-" * 48)

    try {
        $loginProfiles = @{}
        Get-CimInstance -ClassName Win32_NetworkLoginProfile -ErrorAction SilentlyContinue |
            ForEach-Object { $loginProfiles[$_.Name] = $_.LastLogon }

        $users = Get-CimInstance -ClassName Win32_UserAccount -Filter "LocalAccount=True" -ErrorAction SilentlyContinue

        foreach ($u in $users) {
            $rid = Get-UserRid $u.SID
            if ($rid -lt 1000 -or $rid -ge 65534) { continue }

            $lastLogonStr = "Nunca ingreso"
            if ($loginProfiles.ContainsKey($u.Name)) {
                $lastLogon = ConvertFrom-DmtfDate $loginProfiles[$u.Name]
                if ($lastLogon) {
                    $lastLogonStr = $lastLogon.ToString("yyyy-MM-dd HH:mm:ss")
                }
            }

            Write-Host ("{0,-25} {1,-22}" -f $u.Name, $lastLogonStr)
        }
    }
    catch {
        Write-Host "Error: $($_.Exception.Message)" -ForegroundColor Red
    }

    Write-Host ("-" * 48)
    Write-Host ""
}


# --- Opcion 2: Filesystems / Discos ------------------------------------------

function Invoke-Option2 {
    Write-Host ("=" * 48)
    Write-Host " FILESYSTEMS / DISCOS CONECTADOS"
    Write-Host ("=" * 48)

    try {
        $allDisks = Get-CimInstance -ClassName Win32_LogicalDisk -ErrorAction Stop |
            Where-Object { $_.DriveType -eq 2 -or $_.DriveType -eq 3 } |
            Sort-Object DeviceID

        Write-Host ""
        Write-Host " (*) Discos locales y extraibles:"
        Write-Host ("{0,-12} {1,-22} {2,-22} {3}" -f "DISCO", "TAMANO", "ESPACIO LIBRE", "TIPO")
        Write-Host ("-" * 72)

        foreach ($d in $allDisks) {
            $size  = if ($d.Size)  { Format-Bytes $d.Size }  else { "N/A" }
            $free  = if ($d.FreeSpace) { Format-Bytes $d.FreeSpace } else { "N/A" }
            $tipo  = if ($d.DriveType -eq 2) { "USB/Removable" } else { "Local" }

            Write-Host ("{0,-12} {1,-22} {2,-22} {3}" -f "$($d.DeviceID)\", $size, $free, $tipo)
        }

        Write-Host ""
        Write-Host " (*) Unidades de red:"

        $netDrives = Get-CimInstance -ClassName Win32_LogicalDisk -Filter "DriveType=4" -ErrorAction SilentlyContinue
        if ($netDrives) {
            Write-Host ("{0,-12} {1,-22} {2,-22} {3}" -f "DISCO", "TAMANO", "ESPACIO LIBRE", "RUTA")
            Write-Host ("-" * 72)
            foreach ($d in $netDrives) {
                $size  = if ($d.Size)  { Format-Bytes $d.Size }  else { "N/A" }
                $free  = if ($d.FreeSpace) { Format-Bytes $d.FreeSpace } else { "N/A" }
                $path  = if ($d.ProviderName) { $d.ProviderName } else { "-" }
                Write-Host ("{0,-12} {1,-22} {2,-22} {3}" -f "$($d.DeviceID)\", $size, $free, $path)
            }
        }
        else {
            Write-Host "  (ninguna)"
        }
    }
    catch {
        Write-Host "Error: $($_.Exception.Message)" -ForegroundColor Red
    }

    Write-Host ("-" * 48)
    Write-Host ""
}


# --- Opcion 3: 10 archivos mas grandes ---------------------------------------

function Invoke-Option3 {
    Write-Host ("=" * 48)
    Write-Host " 10 ARCHIVOS MAS GRANDES"
    Write-Host ("=" * 48)

    $target = Read-Host "Ingrese el punto de montaje o directorio a analizar"
    if ([string]::IsNullOrWhiteSpace($target)) {
        Write-Host "Error: debe ingresar una ruta." -ForegroundColor Red
        Write-Host ""
        return
    }

    if (-not (Test-Path -LiteralPath $target -PathType Container)) {
        Write-Host "Error: '$target' no existe o no es un directorio." -ForegroundColor Red
        Write-Host ""
        return
    }

    $target = [System.IO.Path]::GetFullPath($target)
    Write-Host ""
    Write-Host "Buscando archivos en: $target"
    Write-Host "Esto puede tardar si el filesystem contiene muchos archivos."
    Write-Host ""

    Write-Host ("{0,-6} {1,-22} {2}" -f "No.", "TAMANO", "RUTA COMPLETA")
    Write-Host ("-" * 80)

    try {
        $files = Get-ChildItem -LiteralPath $target -Recurse -File -ErrorAction SilentlyContinue |
            Sort-Object Length -Descending |
            Select-Object -First 10

        if (-not $files) {
            Write-Host "No se encontraron archivos regulares en la ruta indicada."
        }
        else {
            $count = 0
            foreach ($f in $files) {
                $count++
                Write-Host ("{0,-6} {1,-22} {2}" -f $count, (Format-Bytes $f.Length), $f.FullName)
            }
        }
    }
    catch {
        Write-Host "Error al buscar archivos: $($_.Exception.Message)" -ForegroundColor Red
    }

    Write-Host ("-" * 48)
    Write-Host ""
}


# --- Opcion 4: Memoria libre y swap ------------------------------------------

function Invoke-Option4 {
    Write-Host ("=" * 48)
    Write-Host " MEMORIA LIBRE Y SWAP"
    Write-Host ("=" * 48)

    try {
        $os = Get-CimInstance -ClassName Win32_OperatingSystem -ErrorAction Stop

        $totalMem  = [long]$os.TotalVisibleMemorySize * 1KB
        $freeMem   = [long]$os.FreePhysicalMemory   * 1KB
        $usedMem   = $totalMem - $freeMem
        $usedMemPct = if ($totalMem -gt 0) { [math]::Round(($usedMem / $totalMem) * 100, 1) } else { 0 }

        Write-Host ""
        Write-Host " MEMORIA RAM"
        Write-Host "  Total:  $(Format-Bytes $totalMem)"
        Write-Host "  Libre:  $(Format-Bytes $freeMem)"
        Write-Host ("  Usado:  {0}  ({1,5:N1}%)" -f (Format-Bytes $usedMem), $usedMemPct)

        Write-Host ""
        Write-Host " SWAP (Archivo de paginacion)"
        $pageFiles = Get-CimInstance -ClassName Win32_PageFileUsage -ErrorAction Stop
        if (-not $pageFiles -or ($pageFiles -isnot [array] -and $pageFiles.AllocatedBaseSize -le 0) -or ($pageFiles -is [array] -and ($pageFiles | Measure-Object AllocatedBaseSize -Sum).Sum -le 0)) {
            Write-Host "  No hay archivo de paginacion configurado."
        }
        else {
            if ($pageFiles -is [array]) {
                $totalSwap = ($pageFiles | Measure-Object AllocatedBaseSize -Sum).Sum * 1MB
                $usedSwap  = ($pageFiles | Measure-Object CurrentUsage -Sum).Sum * 1MB
            }
            else {
                $totalSwap = $pageFiles.AllocatedBaseSize * 1MB
                $usedSwap  = $pageFiles.CurrentUsage * 1MB
            }
            $freeSwap = $totalSwap - $usedSwap
            $usedSwapPct = if ($totalSwap -gt 0) { [math]::Round(($usedSwap / $totalSwap) * 100, 1) } else { 0 }
            Write-Host "  Total:  $(Format-Bytes $totalSwap)"
            Write-Host "  Libre:  $(Format-Bytes $freeSwap)"
            Write-Host ("  Usado:  {0}  ({1,5:N1}%)" -f (Format-Bytes $usedSwap), $usedSwapPct)

            Write-Host ""
            Write-Host " DETALLE ADICIONAL"
            foreach ($pf in @($pageFiles)) {
                Write-Host ("  {0,-40} Inicial: {1,8:N0} MB  Uso actual: {2,8:N0} MB" -f $pf.Name, $pf.AllocatedBaseSize, $pf.CurrentUsage)
            }
        }
    }
    catch {
        Write-Host "Error: $($_.Exception.Message)" -ForegroundColor Red
    }

    Write-Host ("-" * 48)
    Write-Host ""
}


# --- Opcion 5: Backup a USB --------------------------------------------------

function Get-UsbMountPoints {
    $result = [System.Collections.ArrayList]@()
    $seen = @{}

    # 1) Get-Disk (requiere admin)
    $usbDisks = Get-Disk -ErrorAction SilentlyContinue | Where-Object BusType -eq 'USB'
    foreach ($disk in $usbDisks) {
        $partitions = $disk | Get-Partition -ErrorAction SilentlyContinue
        foreach ($part in $partitions) {
            $volume = $part | Get-Volume -ErrorAction SilentlyContinue
            if ($volume.DriveLetter -and $volume.Size -gt 0) {
                $letter = "$($volume.DriveLetter)"
                if (-not $seen.ContainsKey($letter)) {
                    $seen[$letter] = $true
                    $null = $result.Add([PSCustomObject]@{
                        MountPoint  = "$($letter):\"
                        DiskNumber  = $disk.Number
                        SizeBytes   = $volume.Size
                        SizeStr     = Format-Bytes $volume.Size
                        DriveLetter = $letter
                    })
                }
            }
        }
    }

    # 2) Win32_LogicalDisk DriveType=2 (Removable) — metodo mas confiable sin admin
    $removable = Get-CimInstance -ClassName Win32_LogicalDisk -Filter "DriveType=2" -ErrorAction SilentlyContinue |
        Where-Object { $_.Size -and $_.Size -gt 0 }
    foreach ($d in $removable) {
        $letter = $d.DeviceID.TrimEnd(':')
        if (-not $seen.ContainsKey($letter)) {
            $seen[$letter] = $true
            $null = $result.Add([PSCustomObject]@{
                MountPoint  = "$($d.DeviceID)\"
                DiskNumber  = -1
                SizeBytes   = $d.Size
                SizeStr     = Format-Bytes $d.Size
                DriveLetter = $letter
            })
        }
    }

    # 3) Win32_DiskDrive con InterfaceType='USB' via CIM association (USB HDDs DriveType=3)
    $usbDrives = Get-CimInstance -ClassName Win32_DiskDrive -ErrorAction SilentlyContinue |
        Where-Object { $_.InterfaceType -eq 'USB' }

    foreach ($drive in $usbDrives) {
        $parts = Get-CimAssociatedInstance -InputObject $drive -Association Win32_DiskDriveToDiskPartition -ErrorAction SilentlyContinue
        foreach ($part in $parts) {
            $logs = Get-CimAssociatedInstance -InputObject $part -Association Win32_LogicalDiskToPartition -ErrorAction SilentlyContinue
            foreach ($ld in $logs) {
                if ($ld.Size -and $ld.Size -gt 0) {
                    $letter = $ld.DeviceID.TrimEnd(':')
                    if (-not $seen.ContainsKey($letter)) {
                        $seen[$letter] = $true
                        $null = $result.Add([PSCustomObject]@{
                            MountPoint  = "$($ld.DeviceID)\"
                            DiskNumber  = $drive.Index
                            SizeBytes   = $ld.Size
                            SizeStr     = Format-Bytes $ld.Size
                            DriveLetter = $letter
                        })
                    }
                }
            }
        }
    }

    return $result.ToArray()
}

function Select-UsbMount {
    $script:SelectedUsbMount  = $null
    $script:SelectedUsbDevice = $null
    $script:SelectedUsbSize   = $null

    $usbEntries = Get-UsbMountPoints

    if (-not $usbEntries) {
        Write-Host "Error: no se encontraron dispositivos USB montados." -ForegroundColor Red
        Write-Host "Conecte una memoria USB antes de ejecutar el backup." -ForegroundColor Red
        return $false
    }

    if ($usbEntries -isnot [array]) { $usbEntries = @($usbEntries) }

    if ($usbEntries.Count -eq 1) {
        $script:SelectedUsbMount  = $usbEntries[0].MountPoint
        $script:SelectedUsbDevice = "Disco $($usbEntries[0].DiskNumber)"
        $script:SelectedUsbSize   = $usbEntries[0].SizeStr
        Write-Host ("USB detectada automaticamente: {0} ({1}, {2})" -f $SelectedUsbMount, $SelectedUsbDevice, $SelectedUsbSize)
        return $true
    }

    Write-Host "Dispositivos USB disponibles:"
    for ($i = 0; $i -lt $usbEntries.Count; $i++) {
        Write-Host (" {0}. {1} (Disco {2}, {3})" -f ($i + 1), $usbEntries[$i].MountPoint, $usbEntries[$i].DiskNumber, $usbEntries[$i].SizeStr)
    }

    $choice = Read-Host ("Seleccione el destino [1-{0}]" -f $usbEntries.Count)
    $parsedValue = 0
    $parsed = [int]::TryParse($choice, [ref]$parsedValue)
    $index = if ($parsed) { $parsedValue - 1 } else { -1 }

    if ($index -lt 0 -or $index -ge $usbEntries.Count) {
        Write-Host "Error: seleccion invalida." -ForegroundColor Red
        return $false
    }

    $script:SelectedUsbMount  = $usbEntries[$index].MountPoint
    $script:SelectedUsbDevice = "Disco $($usbEntries[$index].DiskNumber)"
    $script:SelectedUsbSize   = $usbEntries[$index].SizeStr
    return $true
}

function Invoke-Option5 {
    Write-Host ("=" * 48)
    Write-Host " BACKUP A USB CON CATALOGO CSV"
    Write-Host ("=" * 48)

    if (-not (Select-UsbMount)) {
        Write-Host ""
        return
    }

    Write-Host ""
    $sourceDir = Read-Host "Ingrese el directorio origen a respaldar"

    if ([string]::IsNullOrWhiteSpace($sourceDir)) {
        Write-Host "Error: debe ingresar un directorio origen." -ForegroundColor Red
        Write-Host ""
        return
    }

    if (-not (Test-Path -LiteralPath $sourceDir -PathType Container)) {
        Write-Host "Error: '$sourceDir' no existe o no es un directorio." -ForegroundColor Red
        Write-Host ""
        return
    }

    $sourceDir = [System.IO.Path]::GetFullPath($sourceDir)

    if (-not (Test-Path -LiteralPath $SelectedUsbMount -PathType Container)) {
        Write-Host "Error: el montaje USB detectado no es una ruta valida." -ForegroundColor Red
        Write-Host ""
        return
    }

    if ($SelectedUsbMount.StartsWith($sourceDir, [StringComparison]::OrdinalIgnoreCase)) {
        Write-Host "Error: la USB destino esta dentro del directorio origen." -ForegroundColor Red
        Write-Host "Eso produciria copias recursivas. Seleccione un origen que no contenga la USB." -ForegroundColor Red
        Write-Host ""
        return
    }

    $baseName   = Split-Path -Leaf $sourceDir
    $timestamp  = Get-Date -Format "yyyyMMdd_HHmmss"
    $backupRoot = Join-Path $SelectedUsbMount "backup_${baseName}_${timestamp}"
    $backupData = Join-Path $backupRoot $baseName
    $catalogFile = Join-Path $backupRoot "catalogo_${baseName}_${timestamp}.csv"

    try {
        $null = New-Item -ItemType Directory -Path $backupData -ErrorAction Stop
    }
    catch {
        Write-Host "Error: no se pudo crear el directorio de backup en la USB." -ForegroundColor Red
        Write-Host ""
        return
    }

    Write-Host ""
    Write-Host "Copiando archivos..."
    try {
        Get-ChildItem -LiteralPath $sourceDir | Copy-Item -Destination $backupData -Recurse -Container -ErrorAction Stop
    }
    catch {
        Write-Host "Error: fallo la copia de archivos: $($_.Exception.Message)" -ForegroundColor Red
        Write-Host ""
        return
    }

    Write-Host "Generando catalogo CSV..."
    try {
        $catalog = Get-ChildItem -LiteralPath $sourceDir -Recurse -File -ErrorAction SilentlyContinue |
            ForEach-Object {
                [PSCustomObject]@{
                    archivo              = $_.FullName.Substring($sourceDir.Length).TrimStart('\')
                    ultima_modificacion  = $_.LastWriteTime.ToString("yyyy-MM-dd HH:mm:ss")
                }
            } |
            Sort-Object archivo
        $catalog | Export-Csv -LiteralPath $catalogFile -Encoding UTF8 -NoTypeInformation -Delimiter ','
    }
    catch {
        Write-Host "Error: no se pudo generar el catalogo: $($_.Exception.Message)" -ForegroundColor Red
        Write-Host ""
        return
    }

    Write-Host ""
    Write-Host "Backup completado correctamente."
    Write-Host ("USB destino:       {0} ({1})" -f $SelectedUsbMount, $SelectedUsbDevice)
    Write-Host ("Directorio backup: {0}" -f $backupRoot)
    Write-Host ("Archivos copiados: {0}" -f $backupData)
    Write-Host ("Catalogo CSV:      {0}" -f $catalogFile)
    Write-Host ""
}


# --- Main --------------------------------------------------------------------

function Main {
    do {
        Show-Menu
        $opcion = Read-Host " Seleccione una opcion [0-5]"
        Write-Host ""

        switch ($opcion) {
            '1' { Invoke-Option1 }
            '2' { Invoke-Option2 }
            '3' { Invoke-Option3 }
            '4' { Invoke-Option4 }
            '5' { Invoke-Option5 }
            '0' {
                Write-Host "Saliendo..."
                return
            }
            default {
                Write-Host "Opcion invalida. Intente de nuevo."
                Write-Host ""
            }
        }

        if ($opcion -ne '0') {
            $null = Read-Host "Presione Enter para continuar..."
        }
    } while ($opcion -ne '0')
}


# --- Entry point -------------------------------------------------------------

Main