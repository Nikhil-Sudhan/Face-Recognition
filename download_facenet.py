import urllib.request
import os

# Create models directory
models_dir = "assets/models"
os.makedirs(models_dir, exist_ok=True)

# Model URL and destination
model_url = "https://github.com/kby-ai/FaceRecognition-Flutter/raw/main/assets/facenet.tflite"
model_path = os.path.join(models_dir, "facenet.tflite")

print("=" * 50)
print("FaceNet Model Download Script")
print("=" * 50)
print(f"\nDownloading from: {model_url}")
print(f"Destination: {model_path}\n")

try:
    # Download with progress
    def download_progress(block_num, block_size, total_size):
        downloaded = block_num * block_size
        percent = (downloaded / total_size) * 100 if total_size > 0 else 0
        mb_downloaded = downloaded / (1024 * 1024)
        mb_total = total_size / (1024 * 1024)
        print(f"\rProgress: {percent:.1f}% ({mb_downloaded:.1f}/{mb_total:.1f} MB)", end='', flush=True)
    
    urllib.request.urlretrieve(model_url, model_path, download_progress)
    
    file_size = os.path.getsize(model_path) / (1024 * 1024)
    print(f"\n\n✓ Model downloaded successfully!")
    print(f"  File size: {file_size:.2f} MB")
    
    print("\n" + "=" * 50)
    print("Next Steps:")
    print("=" * 50)
    print("1. Run: flutter pub get")
    print("2. Delete all employees from the app")
    print("3. Re-register employees with new model")
    print("4. Test face recognition accuracy\n")
    
except Exception as e:
    print(f"\n✗ Error: {e}")
    print("\nAlternative: Download manually from:")
    print("https://github.com/kby-ai/FaceRecognition-Flutter/tree/main/assets")
    print(f"Save as: {model_path}\n")
