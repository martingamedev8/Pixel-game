param(
  [string]$Src = "C:\Users\henri\Documents\pixel-art-game-test\player.png",
  [string]$Backup = "C:\Users\henri\Documents\pixel-art-game-test\player_original.png",
  [string]$Out = "C:\Users\henri\Documents\pixel-art-game-test\player_cutout.png",
  [double]$Threshold = 120.0
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

if (!(Test-Path -LiteralPath $Src)) {
  throw "Source file not found: $Src"
}

if (!(Test-Path -LiteralPath $Backup)) {
  Copy-Item -Force -LiteralPath $Src -Destination $Backup
}

Add-Type -AssemblyName System.Drawing

function Get-RgbDistance([System.Drawing.Color]$a, [System.Drawing.Color]$b) {
  $dr = [double]$a.R - [double]$b.R
  $dg = [double]$a.G - [double]$b.G
  $db = [double]$a.B - [double]$b.B
  return [Math]::Sqrt($dr*$dr + $dg*$dg + $db*$db)
}

$bmp = [System.Drawing.Bitmap]::FromFile($Src)
try {
  $w = $bmp.Width
  $h = $bmp.Height

  $c1 = $bmp.GetPixel(0,0)
  $c2 = $bmp.GetPixel($w-1,0)
  $c3 = $bmp.GetPixel(0,$h-1)
  $c4 = $bmp.GetPixel($w-1,$h-1)
  $bgs = @($c1, $c2, $c3, $c4)

  # Use a byte array (much faster + less memory than bool[,])
  $visited = New-Object byte[] ($w * $h)
  $q = New-Object 'System.Collections.Generic.Queue[System.ValueTuple[int,int]]'

  for ($x=0; $x -lt $w; $x++) {
    $q.Enqueue([ValueTuple[int,int]]::new($x,0))
    $q.Enqueue([ValueTuple[int,int]]::new($x,$h-1))
  }
  for ($y=0; $y -lt $h; $y++) {
    $q.Enqueue([ValueTuple[int,int]]::new(0,$y))
    $q.Enqueue([ValueTuple[int,int]]::new($w-1,$y))
  }

  # Use LockBits for speed (SetPixel/GetPixel is extremely slow).
  $rect = New-Object System.Drawing.Rectangle 0, 0, $w, $h
  $data = $bmp.LockBits($rect, [System.Drawing.Imaging.ImageLockMode]::ReadWrite, [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
  try {
    $stride = $data.Stride
    $absStride = [Math]::Abs($stride)
    $bytes = $absStride * $h
    $buf = New-Object byte[] $bytes
    [System.Runtime.InteropServices.Marshal]::Copy($data.Scan0, $buf, 0, $bytes)

    function Get-Row([int]$y) {
      if ($stride -ge 0) { return $y }
      return ($h - 1 - $y)
    }
    function Get-Index([int]$x, [int]$y) {
      $row = Get-Row $y
      return ($row * $absStride) + ($x * 4)
    }
    function Get-ColorAt([int]$x, [int]$y) {
      $i = Get-Index $x $y
      $b = $buf[$i + 0]
      $g = $buf[$i + 1]
      $r = $buf[$i + 2]
      $a = $buf[$i + 3]
      return [System.Drawing.Color]::FromArgb($a, $r, $g, $b)
    }
    function Set-Alpha0([int]$x, [int]$y) {
      $i = Get-Index $x $y
      $buf[$i + 3] = 0
    }

    # Safety: don't spend forever on huge images.
    $maxOps = [Math]::Min([int64]($w*$h), 20000000)
    $ops = 0

  while ($q.Count -gt 0) {
    $ops++
    if ($ops -ge $maxOps) { break }
    $p = $q.Dequeue()
    $x = $p.Item1
    $y = $p.Item2

    if ($x -lt 0 -or $y -lt 0 -or $x -ge $w -or $y -ge $h) { continue }
    $vi = ($y * $w) + $x
    if ($visited[$vi] -ne 0) { continue }
    $visited[$vi] = 1

    $c = Get-ColorAt $x $y
    $minDist = 999999.0
    foreach ($b in $bgs) {
      $d = Get-RgbDistance $c $b
      if ($d -lt $minDist) { $minDist = $d }
    }
    $ok = ($c.A -eq 0) -or ($minDist -le $Threshold)
    if (-not $ok) { continue }

    # Make transparent but keep RGB (helps edge blending in some viewers)
    Set-Alpha0 $x $y

    $q.Enqueue([ValueTuple[int,int]]::new($x+1,$y))
    $q.Enqueue([ValueTuple[int,int]]::new($x-1,$y))
    $q.Enqueue([ValueTuple[int,int]]::new($x,$y+1))
    $q.Enqueue([ValueTuple[int,int]]::new($x,$y-1))
  }

    [System.Runtime.InteropServices.Marshal]::Copy($buf, 0, $data.Scan0, $bytes)
  }
  finally {
    $bmp.UnlockBits($data)
  }

  $bmp.Save($Out, [System.Drawing.Imaging.ImageFormat]::Png)
  $bmp.Dispose()
  Write-Host "cutout ok: src=$Src out=$Out backup=$Backup threshold=$Threshold ops=$ops"
}
finally {
  if ($null -ne $bmp) { $bmp.Dispose() }
}

