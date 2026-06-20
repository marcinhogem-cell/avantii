param(
  [int]$Port = 4173,
  [string]$Root = (Get-Location).Path
)

$ip = [Net.IPAddress]::Parse("127.0.0.1")
$listener = New-Object Net.Sockets.TcpListener($ip, $Port)
$listener.Start()
Write-Host "Serving $Root at http://127.0.0.1:$Port/"

$rootFull = [IO.Path]::GetFullPath($Root)
if (-not $rootFull.EndsWith([IO.Path]::DirectorySeparatorChar)) {
  $rootFull += [IO.Path]::DirectorySeparatorChar
}

$mime = @{
  ".html" = "text/html; charset=utf-8"
  ".css" = "text/css; charset=utf-8"
  ".js" = "application/javascript; charset=utf-8"
  ".json" = "application/json; charset=utf-8"
  ".png" = "image/png"
  ".jpg" = "image/jpeg"
  ".jpeg" = "image/jpeg"
  ".svg" = "image/svg+xml"
  ".ico" = "image/x-icon"
}

while ($true) {
  $client = $listener.AcceptTcpClient()
  $stream = $client.GetStream()
  $reader = New-Object IO.StreamReader($stream)
  $line = $reader.ReadLine()
  if (-not $line) {
    $client.Close()
    continue
  }
  while (($header = $reader.ReadLine()) -ne "") { }

  $parts = $line.Split(" ")
  $requestPath = if ($parts.Length -gt 1) { [uri]::UnescapeDataString($parts[1].Split("?")[0].TrimStart("/")) } else { "" }
  if ([string]::IsNullOrWhiteSpace($requestPath)) { $requestPath = "index.html" }
  $localPath = [IO.Path]::GetFullPath((Join-Path $rootFull $requestPath))
  $isInsideRoot = $localPath.StartsWith($rootFull, [StringComparison]::OrdinalIgnoreCase)
  if ($isInsideRoot -and (Test-Path $localPath -PathType Container)) {
    $localPath = [IO.Path]::GetFullPath((Join-Path $localPath "index.html"))
    $isInsideRoot = $localPath.StartsWith($rootFull, [StringComparison]::OrdinalIgnoreCase)
  }
  if (-not $isInsideRoot) {
    $status = "403 Forbidden"
    $contentType = "text/plain; charset=utf-8"
    $bytes = [Text.Encoding]::UTF8.GetBytes("403")
  } elseif (-not (Test-Path $localPath -PathType Leaf)) {
    $status = "404 Not Found"
    $contentType = "text/plain; charset=utf-8"
    $bytes = [Text.Encoding]::UTF8.GetBytes("404")
  } else {
    $status = "200 OK"
    $ext = [IO.Path]::GetExtension($localPath).ToLowerInvariant()
    $contentType = if ($mime.ContainsKey($ext)) { $mime[$ext] } else { "application/octet-stream" }
    $bytes = [IO.File]::ReadAllBytes($localPath)
  }
  $headers = "HTTP/1.1 $status`r`nContent-Type: $contentType`r`nContent-Length: $($bytes.Length)`r`nConnection: close`r`n`r`n"
  $headerBytes = [Text.Encoding]::ASCII.GetBytes($headers)
  $stream.Write($headerBytes, 0, $headerBytes.Length)
  $stream.Write($bytes, 0, $bytes.Length)
  $stream.Flush()
  $client.Close()
}
