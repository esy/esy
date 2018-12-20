Test-Path HKLM:System\CurrentControlSet\Control\FileSystem
Write-Host Getting long path registry value...
Get-ItemProperty -Path HKLM:System\CurrentControlSet\Control\FileSystem -Name LongPathsEnabled
Write-Host Setting long path registry value...
Set-ItemProperty -Path HKLM:System\CurrentControlSet\Control\FileSystem -Name LongPathsEnabled -Value 1
Write-Host New Value
Get-ItemProperty -Path HKLM:System\CurrentControlSet\Control\FileSystem -Name LongPathsEnabled
Write-Host DONE $LastExitCode
