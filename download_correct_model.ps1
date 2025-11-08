# Download the correct FaceNet TensorFlow Lite model
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "Downloading Correct FaceNet .tflite Model" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

$modelDir = "assets\models"
$modelPath = "$modelDir\facenet.tflite"

# Backup old file if exists
if (Test-Path $modelPath) {
    Write-Host "Backing up old model file..." -ForegroundColor Yellow
    Move-Item $modelPath "$modelPath.backup" -Force
}

Write-Host "Downloading from kby-ai repository..." -ForegroundColor Yellow
Write-Host ""

try {
    # Using .NET WebClient for better compatibility with large files
    $webClient = New-Object System.Net.WebClient
    $url = "https://github.com/kby-ai/FaceRecognition-Flutter/raw/main/assets/facenet.tflite"
    
    Write-Host "Source: $url" -ForegroundColor Gray
    Write-Host "Destination: $modelPath" -ForegroundColor Gray
    Write-Host ""
    Write-Host "Downloading... (this may take a minute)" -ForegroundColor Yellow
    
    $webClient.DownloadFile($url, $modelPath)
    
    $fileSize = (Get-Item $modelPath).Length / 1MB
    Write-Host ""
    Write-Host "Success! Model downloaded." -ForegroundColor Green
    Write-Host "File size: $([math]::Round($fileSize, 2)) MB" -ForegroundColor Green
    Write-Host ""
    Write-Host "Next steps:" -ForegroundColor Cyan
    Write-Host "1. Restart the app (flutter run)" -ForegroundColor White
    Write-Host "2. Check for: 'FaceNet model loaded successfully'" -ForegroundColor White
    Write-Host "3. Delete all employees and re-register them" -ForegroundColor White
    Write-Host ""
}
catch {
    Write-Host "Download failed: $_" -ForegroundColor Red
    Write-Host ""
    Write-Host "Manual steps:" -ForegroundColor Yellow
    Write-Host "1. Go to: https://github.com/kby-ai/FaceRecognition-Flutter/tree/main/assets" -ForegroundColor White
    Write-Host "2. Click on 'facenet.tflite'" -ForegroundColor White
    Write-Host "3. Click 'Download raw file' button" -ForegroundColor White
    Write-Host "4. Save as: $modelPath" -ForegroundColor White
    Write-Host ""
    
    # Restore backup if exists
    if (Test-Path "$modelPath.backup") {
        Move-Item "$modelPath.backup" $modelPath -Force
    }
}
