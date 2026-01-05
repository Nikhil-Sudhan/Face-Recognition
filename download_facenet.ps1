# PowerShell script to download FaceNet model for Flutter Face Recognition App
# Run this script from the project root directory

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "FaceNet Model Download Script" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

# Create models directory if it doesn't exist
$modelsDir = "assets\models"
if (-not (Test-Path $modelsDir)) {
    Write-Host "Creating models directory..." -ForegroundColor Yellow
    New-Item -ItemType Directory -Path $modelsDir -Force | Out-Null
}

# FaceNet model URL - trying alternative source
# Using a reliable Hugging Face mirror
$modelUrl = "https://github.com/kby-ai/FaceRecognition-Flutter/raw/main/assets/facenet.tflite"
$modelPath = "$modelsDir\facenet.tflite"

Write-Host "Downloading FaceNet model..." -ForegroundColor Yellow
Write-Host "Source: $modelUrl" -ForegroundColor Gray
Write-Host "Destination: $modelPath" -ForegroundColor Gray
Write-Host ""

try {
    # Download the model
    Invoke-WebRequest -Uri $modelUrl -OutFile $modelPath -UseBasicParsing
    
    $fileSize = (Get-Item $modelPath).Length / 1MB
    Write-Host "Successfully downloaded!" -ForegroundColor Green
    Write-Host "  File size: $([math]::Round($fileSize, 2)) MB" -ForegroundColor Green
    Write-Host ""
    
    # Verify the file
    if ((Get-Item $modelPath).Length -gt 0) {
        Write-Host "Model file verified" -ForegroundColor Green
    }
    
    Write-Host ""
    Write-Host "========================================" -ForegroundColor Cyan
    Write-Host "Next Steps:" -ForegroundColor Cyan
    Write-Host "========================================" -ForegroundColor Cyan
    Write-Host "1. Run: flutter pub get" -ForegroundColor White
    Write-Host "2. Delete all employees from the app" -ForegroundColor White
    Write-Host "3. Re-register employees with new model" -ForegroundColor White
    Write-Host "4. Test face recognition accuracy" -ForegroundColor White
    Write-Host ""
    Write-Host "The app will automatically use FaceNet when available!" -ForegroundColor Green
    Write-Host ""
    
}
catch {
    Write-Host "Error downloading model: $_" -ForegroundColor Red
    Write-Host ""
    Write-Host "Alternative download options:" -ForegroundColor Yellow
    Write-Host "1. Manual download from: https://github.com/kby-ai/FaceRecognition-Flutter" -ForegroundColor White
    Write-Host "2. Or from: https://www.kaggle.com/models/google/facenet" -ForegroundColor White
    Write-Host "3. Place the .tflite file in: $modelsDir\facenet.tflite" -ForegroundColor White
    Write-Host ""
    exit 1
}
