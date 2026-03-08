Add-Type -AssemblyName System.Windows.Forms
$img = [System.Windows.Forms.Clipboard]::GetImage()
if ($img -ne $null) {
    $img.Save('C:\ps\uigen\clipboard.png')
    Write-Output 'Saved'
} else {
    Write-Output 'No image'
}
