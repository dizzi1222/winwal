# ============================================
# Script: Pywal-Wallpaper-Manager.ps1
# VERSIÓN CORREGIDA - Maneja rutas con corchetes
# ============================================
# En la primera línea de WalManager.psm1 (IGNORAR AVISOS)
$PSDefaultParameterValues['*:WarningAction'] = 'SilentlyContinue'

# O específico para Import-Module:
$PSDefaultParameterValues['Import-Module:WarningAction'] = 'SilentlyContinue'

function Get-CurrentWallpaper {
  <#
    .SYNOPSIS
    Obtiene la ruta del wallpaper actual de Windows
    #>

  try {
    # Ruta del registro donde Windows guarda el wallpaper actual
    $RegPath = "HKCU:\Control Panel\Desktop"
    $WallpaperPath = (Get-ItemProperty -Path $RegPath -Name Wallpaper).Wallpaper

    # DEBUG: Mostrar ruta exacta del registro
    Write-Host "🔍 Ruta del registro: $WallpaperPath" -ForegroundColor Cyan

    # 1. Intentar la ruta tal cual
    if (Test-Path -LiteralPath $WallpaperPath) {
      Write-Host "✅ Archivo encontrado: $WallpaperPath" -ForegroundColor Green
      return $WallpaperPath
    }

    # 2. Convertir barras / a \ si es necesario
    $FixedPath = $WallpaperPath -replace '/', '\'
    if ($FixedPath -ne $WallpaperPath -and (Test-Path -LiteralPath $FixedPath)) {
      Write-Host "✅ Archivo encontrado (barra fija): $FixedPath" -ForegroundColor Green
      return $FixedPath
    }

    # 3. Si la ruta tiene corchetes, intentar sin problemas de comodines
    if ($WallpaperPath -match '\[.*\]') {
      Write-Host "⚠️  Ruta contiene corchetes, usando método especial..." -ForegroundColor Yellow

      # Extraer directorio y archivo
      $ParentDir = Split-Path $WallpaperPath -Parent
      $FileName = Split-Path $WallpaperPath -Leaf

      Write-Host "📁 Directorio padre: $ParentDir" -ForegroundColor Magenta
      Write-Host "📄 Nombre archivo: $FileName" -ForegroundColor Magenta

      # Intentar acceder al directorio padre (puede fallar por corchetes)
      try {
        # Primero intentar con -LiteralPath
        if (Test-Path -LiteralPath $ParentDir) {
          # Buscar el archivo en el directorio
          $FoundFile = Get-ChildItem -LiteralPath $ParentDir -Filter $FileName -ErrorAction SilentlyContinue
          if ($FoundFile) {
            Write-Host "✅ Archivo encontrado via búsqueda: $($FoundFile.FullName)" -ForegroundColor Green
            return $FoundFile.FullName
          }
        }

        # Si falla, intentar buscar recursivamente desde una ruta superior
        $DriveRoot = Split-Path $ParentDir -Qualifier
        $SearchPath = $DriveRoot + "\"

        Write-Host "🔍 Búsqueda profunda desde: $SearchPath" -ForegroundColor Cyan

        # Buscar el archivo por nombre (sin considerar directorio exacto)
        $DeepSearch = Get-ChildItem -Path $SearchPath -Filter $FileName -Recurse -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($DeepSearch) {
          Write-Host "✅ Archivo encontrado via búsqueda profunda: $($DeepSearch.FullName)" -ForegroundColor Green
          return $DeepSearch.FullName
        }
      }
      catch {
        Write-Host "❌ Error en búsqueda especial: $_" -ForegroundColor Red
      }
    }

    # 4. Último intento: usar la API de Windows para obtener el wallpaper
    Write-Host "🔄 Intentando método alternativo..." -ForegroundColor Cyan
    try {
      Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;
public class WallpaperAPI {
    [DllImport("user32.dll", CharSet = CharSet.Auto)]
    private static extern int SystemParametersInfo(int uAction, int uParam, System.Text.StringBuilder lpvParam, int fuWinIni);

    public static string GetCurrentWallpaper() {
        System.Text.StringBuilder wallpaperPath = new System.Text.StringBuilder(260);
        SystemParametersInfo(0x0073, 260, wallpaperPath, 0);
        return wallpaperPath.ToString();
    }
}
"@
      $ApiPath = [WallpaperAPI]::GetCurrentWallpaper()
      if ($ApiPath -and $ApiPath -ne "" -and (Test-Path -LiteralPath $ApiPath)) {
        Write-Host "✅ Archivo encontrado via API: $ApiPath" -ForegroundColor Green
        return $ApiPath
      }
    }
    catch {
      Write-Host "⚠️  API falló: $_" -ForegroundColor Yellow
    }

    Write-Host "❌ No se pudo encontrar el archivo del wallpaper" -ForegroundColor Red
    Write-Host "💡 Tip: Intenta establecer el wallpaper de nuevo desde Windows o usar rutas sin corchetes" -ForegroundColor Yellow

    # Devolver la ruta del registro de todas formas (para uso con comillas)
    if ($WallpaperPath) {
      Write-Host "📝 Ruta disponible (puede usarse con comillas): `"$WallpaperPath`"" -ForegroundColor Magenta
      return "`"$WallpaperPath`""
    }

    return $null
  }
  catch {
    Write-Host "❌ Error al obtener el wallpaper actual: $_" -ForegroundColor Red
    return $null
  }
}

function Update-WalFromCurrentWallpaper {
  <#
    .SYNOPSIS
    Genera colores de pywal usando el wallpaper actual
    .PARAMETER Backend
    Backend a usar para generar colores (colorthief, colorz, etc.)
    .PARAMETER y
    Ejecutar automáticamente sin confirmación
    #>

  param(
    [string]$Backend = "colorthief",
    [switch]$y  # ← NUEVO: acepta -y para modo automático
  )

  Write-Host "`n🔍 Detectando wallpaper actual..." -ForegroundColor Cyan

  $CurrentWallpaper = Get-CurrentWallpaper

  if ($CurrentWallpaper) {
    Write-Host "📁 Wallpaper encontrado:" -ForegroundColor Green
    Write-Host "   $CurrentWallpaper`n" -ForegroundColor Yellow

    # Mostrar preview de la imagen (solo nombre del archivo)
    $FileName = Split-Path $CurrentWallpaper -Leaf
    Write-Host "🖼️  Archivo: $FileName" -ForegroundColor Magenta

    # SI -y está presente, saltar confirmación
    if ($y) {
      Write-Host "🤖 Modo automático (sin confirmación)" -ForegroundColor Cyan
      $Confirm = "S"
    }
    else {
      # Preguntar confirmación normal
      $Confirm = Read-Host "`n¿Generar colores con este wallpaper? (S/n)"
    }

    if ($Confirm -eq "" -or $Confirm -eq "S" -or $Confirm -eq "s") {
      Write-Host "`n🎨 Generando colores con backend: $Backend..." -ForegroundColor Cyan

      # Usar la ruta con comillas si es necesario
      $WalPath = $CurrentWallpaper
      if ($CurrentWallpaper -notlike '"*"') {
        $WalPath = "`"$CurrentWallpaper`""
      }

      # Ejecutar wal directamente
      Write-Host "▶️  Ejecutando: wal -i $WalPath --backend $Backend" -ForegroundColor DarkGray

      # Ejecutar el comando
      $Result = Invoke-Expression "wal -i $WalPath --backend $Backend 2>&1"

      if ($LASTEXITCODE -eq 0) {
        Write-Host "`n✅ Colores generados exitosamente!" -ForegroundColor Green
        Write-Host "📂 Ubicación: $HOME\.cache\wal\" -ForegroundColor Yellow

        # Mostrar los colores generados
        Show-WalColors
      }
      else {
        Write-Host "`n❌ Error al generar colores:" -ForegroundColor Red
        Write-Host $Result -ForegroundColor Red
      }
    }
    else {
      Write-Host "`n❌ Operación cancelada." -ForegroundColor Red
    }
  }
  else {
    Write-Host "`n❌ No se pudo detectar el wallpaper actual." -ForegroundColor Red
    Write-Host "💡 Usa: wal -i `"ruta/completa/imagen.png`" --backend colorthief" -ForegroundColor Yellow
  }
}

function Show-WalColors {
  <#
    .SYNOPSIS
    Muestra los colores generados por pywal
    #>

  $ColorsFile = "$HOME\.cache\wal\colors.json"

  if (Test-Path $ColorsFile) {
    Write-Host "`n🎨 Colores generados:" -ForegroundColor Cyan
    Write-Host "─────────────────────" -ForegroundColor DarkGray

    try {
      $ColorsJson = Get-Content $ColorsFile | ConvertFrom-Json

      # Mostrar colores principales
      Write-Host "background : $($ColorsJson.colors.color0)" -ForegroundColor White
      Write-Host "foreground : $($ColorsJson.colors.color7)" -ForegroundColor White

      # Mostrar paleta completa
      Write-Host "`n🎨 Paleta completa:" -ForegroundColor Cyan
      for ($i = 0; $i -le 15; $i++) {
        $colorKey = "color" + $i
        if ($ColorsJson.colors.$colorKey) {
          $colorValue = $ColorsJson.colors.$colorKey
          Write-Host "color$i : $colorValue" -ForegroundColor White
        }
      }
    }
    catch {
      # Fallback al archivo vim si json falla
      $VimColorsFile = "$HOME\.cache\wal\colors-wal.vim"
      if (Test-Path $VimColorsFile) {
        $Colors = Get-Content $VimColorsFile | Select-String 'let (background|foreground|color\d+) = "(#[0-9A-Fa-f]{6})"'

        foreach ($Line in ipairs($Colors)) {
          if ($Line -match 'let (\w+) = "(#[0-9A-Fa-f]{6})"') {
            $ColorName = $Matches[1]
            $ColorHex = $Matches[2]
            Write-Host "$ColorName : $ColorHex" -ForegroundColor White
          }
        }
      }
    }

    Write-Host "─────────────────────`n" -ForegroundColor DarkGray
  }
  else {
    Write-Host "⚠️  No se encontró el archivo de colores." -ForegroundColor Yellow
    Write-Host "💡 Genera colores primero con: uwal" -ForegroundColor Cyan
  }
}

function Set-WallpaperFromArts {
  <#
    .SYNOPSIS
    Elige una imagen de tu carpeta ARTS con paginación
    #>

  param(
    [int]$Page = 1,
    [int]$PageSize = 20
  )

  # Ruta de ARTS
  $ArtsPath = "I:\Mi unidad\Mi unidad\`[Imagenes`]\`[ARTS`]"

  if (-not (Test-Path -LiteralPath $ArtsPath)) {
    Write-Host "❌ Error: No se encontró la carpeta ARTS." -ForegroundColor Red
    return
  }

  Write-Host "✅ Carpeta encontrada: $ArtsPath`n" -ForegroundColor Green

  # Obtener todas las imágenes
  Write-Host "🖼️  Buscando imágenes en ARTS..." -ForegroundColor Cyan
  $AllImages = @(Get-ChildItem -LiteralPath $ArtsPath -Include *.jpg, *.png, *.jpeg, *.bmp, *.webp -Recurse |
    Where-Object { $_.Name -notmatch 'thumb|icon|small' })

  if ($AllImages.Count -eq 0) {
    Write-Host "⚠️  No se encontraron imágenes en la carpeta." -ForegroundColor Yellow
    return
  }

  # Calcular páginas
  $TotalPages = [Math]::Ceiling($AllImages.Count / $PageSize)
  if ($Page -lt 1 -or $Page -gt $TotalPages) {
    $Page = 1
  }

  $StartIndex = ($Page - 1) * $PageSize
  $EndIndex = [Math]::Min($StartIndex + $PageSize - 1, $AllImages.Count - 1)
  $PageImages = $AllImages[$StartIndex..$EndIndex]

  # Mostrar página
  Write-Host "─────────────────────────────────" -ForegroundColor DarkGray
  Write-Host "🖼️  Página $Page de $TotalPages ($($AllImages.Count) imágenes totales)" -ForegroundColor Cyan
  Write-Host "📄 Mostrando imágenes $($StartIndex + 1)-$($EndIndex + 1)" -ForegroundColor Magenta

  for ($i = 0; $i -lt $PageImages.Count; $i++) {
    $img = $PageImages[$i]
    $globalIndex = $StartIndex + $i
    $sizeMB = [Math]::Round($img.Length / 1MB, 2)
    Write-Host "[$globalIndex] $($img.Name) ($sizeMB MB)" -ForegroundColor White
  }

  Write-Host "─────────────────────────────────" -ForegroundColor DarkGray
  Write-Host "📖 Comandos de navegación:" -ForegroundColor Yellow
  Write-Host "   n = Siguiente página    p = Página anterior" -ForegroundColor Gray
  Write-Host "   número = Seleccionar    q = Cancelar" -ForegroundColor Gray
  Write-Host "─────────────────────────────────`n" -ForegroundColor DarkGray

  $Selection = Read-Host "Selección"

  switch ($Selection) {
    "n" {
      if ($Page -lt $TotalPages) {
        Set-WallpaperFromArts -Page ($Page + 1) -PageSize $PageSize
      }
      else {
        Write-Host "📘 Ya estás en la última página" -ForegroundColor Cyan
        Set-WallpaperFromArts -Page $Page -PageSize $PageSize
      }
      return
    }
    "p" {
      if ($Page -gt 1) {
        Set-WallpaperFromArts -Page ($Page - 1) -PageSize $PageSize
      }
      else {
        Write-Host "📘 Ya estás en la primera página" -ForegroundColor Cyan
        Set-WallpaperFromArts -Page $Page -PageSize $PageSize
      }
      return
    }
    "q" {
      Write-Host "❌ Operación cancelada.`n" -ForegroundColor Red
      return
    }
    default {
      if ($Selection -match '^\d+$' -and [int]$Selection -lt $AllImages.Count) {
        $SelectedImage = $AllImages[[int]$Selection].FullName
        Process-SelectedImage -ImagePath $SelectedImage
      }
      else {
        Write-Host "❌ Selección inválida. Intenta de nuevo." -ForegroundColor Red
        Set-WallpaperFromArts -Page $Page -PageSize $PageSize
      }
    }
  }
}

function Process-SelectedImage {
  param([string]$ImagePath)

  Write-Host "`n🎨 Procesando: $(Split-Path $ImagePath -Leaf)" -ForegroundColor Cyan

  # 1. Establecer como wallpaper
  Write-Host "🖼️  Estableciendo como wallpaper..." -ForegroundColor Cyan
  try {
    Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;
public class Wallpaper {
    [DllImport("user32.dll", CharSet = CharSet.Auto)]
    public static extern int SystemParametersInfo(int uAction, int uParam, string lpvParam, int fuWinIni);
}
"@
    [Wallpaper]::SystemParametersInfo(0x0014, 0, $ImagePath, 0x01 -bor 0x02)
    Write-Host "✅ Wallpaper establecido" -ForegroundColor Green
  }
  catch {
    Write-Host "⚠️  No se pudo establecer wallpaper: $_" -ForegroundColor Yellow
  }

  # 2. Generar colores con pywal
  Write-Host "🎨 Generando colores con pywal..." -ForegroundColor Cyan
  $QuotedPath = "`"$ImagePath`""
  $Result = Invoke-Expression "wal -i $QuotedPath --backend colorthief 2>&1"

  if ($LASTEXITCODE -eq 0) {
    Write-Host "✅ Wallpaper y colores actualizados!`n" -ForegroundColor Green
    Show-WalColors
  }
  else {
    Write-Host "❌ Error al generar colores:" -ForegroundColor Red
    Write-Host $Result -ForegroundColor Red
  }
}

function swal-search {
  <#
    .SYNOPSIS
    Buscar imágenes por nombre y establecer como wallpaper
    #>

  param([string]$SearchTerm)

  if (-not $SearchTerm) {
    $SearchTerm = Read-Host "🔍 Buscar imágenes por nombre"
  }

  $ArtsPath = "I:\Mi unidad\Mi unidad\`[Imagenes`]\`[ARTS`]"
  $Images = Get-ChildItem -LiteralPath $ArtsPath -Recurse -Include *.jpg, *.png, *.jpeg, *.bmp, *.webp |
  Where-Object { $_.Name -match [regex]::Escape($SearchTerm) } |
  Select-Object -First 50

  if ($Images.Count -eq 0) {
    Write-Host "❌ No se encontraron imágenes con: $SearchTerm" -ForegroundColor Red
    return
  }

  Write-Host "🔍 Resultados para: $SearchTerm ($($Images.Count) encontradas)" -ForegroundColor Cyan

  for ($i = 0; $i -lt $Images.Count; $i++) {
    $img = $Images[$i]
    $sizeMB = [Math]::Round($img.Length / 1MB, 2)
    Write-Host "[$i] $($img.Name) ($sizeMB MB)" -ForegroundColor White
  }

  $Selection = Read-Host "`nSelecciona número (o 'q' para cancelar)"

  if ($Selection -match '^\d+$' -and [int]$Selection -lt $Images.Count) {
    Process-SelectedImage -ImagePath $Images[[int]$Selection].FullName
  }
}

function Update-WalTheme {
  <#
    .SYNOPSIS
    Función de compatibilidad - usa wal directamente
    #>
  param(
    [string]$Image,
    [string]$Backend = "colorthief"
  )

  if ($Image) {
    $QuotedPath = "`"$Image`""
    Invoke-Expression "wal -i $QuotedPath --backend $Backend"
  }
  else {
    Write-Host "❌ Error: No se especificó imagen" -ForegroundColor Red
  }
}

# ============================================
# ALIAS Y EXPORTS
# ============================================

# Alias más cortos
Set-Alias -Name sws -Value swal-search
Set-Alias -Name gwp -Value Get-CurrentWallpaper
Set-Alias -Name uwal -Value Update-WalFromCurrentWallpaper
Set-Alias -Name swal -Value Set-WallpaperFromArts
Set-Alias -Name cwal -Value Show-WalColors

# ============================================
# MENÚ PRINCIPAL
# ============================================

function Show-WalHelp {
  Write-Host "Comandos disponibles:" -ForegroundColor Green
  Write-Host "  gwp   - Get Wallpaper Path (ver ruta actual)" -ForegroundColor White
  Write-Host "  wal   - Comando wal directo (ej: wal -i imagen.png)" -ForegroundColor White
  Write-Host "  uwal  - Update Wal (usar fondo actual)" -ForegroundColor White
  Write-Host "  swal  - Set Wallpaper from ARTS (elegir de carpeta)" -ForegroundColor White
  Write-Host "  cwal  - Show Colors (ver colores generados)" -ForegroundColor White
  Write-Host "  sws   - Buscar imágenes por nombre`n" -ForegroundColor White

  Write-Host "Ejemplos:" -ForegroundColor Green
  Write-Host "  uwal                    # Usar fondo actual" -ForegroundColor DarkGray
  Write-Host "  wal -i imagen.png       # Generar colores de imagen" -ForegroundColor DarkGray
  Write-Host "  swal                    # Elegir imagen de ARTS" -ForegroundColor DarkGray
  Write-Host "  sws berserk             # Buscar imágenes con 'berserk'`n" -ForegroundColor DarkGray

  Write-Host "📌 Nota: Si tienes rutas con corchetes [], ahora debería funcionar." -ForegroundColor Magenta
}

function Show-WalMenu {
  Write-Host "📌 walManager on (pywal), usa walhelp" -ForegroundColor DarkGray
}

# Alias para ayuda
Set-Alias -Name walhelp -Value Show-WalHelp

# Mostrar menú corto al importar el módulo
Show-WalMenu

# Exportar funciones
Export-ModuleMember -Function Get-CurrentWallpaper, Update-WalFromCurrentWallpaper, Set-WallpaperFromArts, Show-WalColors, Show-WalMenu, Update-WalTheme, swal-search, Process-SelectedImage, Show-WalHelp
Export-ModuleMember -Alias gwp, uwal, swal, cwal, wal, sws, walhelp

