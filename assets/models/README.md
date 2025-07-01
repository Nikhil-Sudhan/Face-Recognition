# Face Recognition Model Setup

## Overview
This directory should contain the TensorFlow Lite face recognition model for real face matching.

## Required Model
Place a face recognition model file named `facenet.tflite` in this directory.

## Recommended Models

### 1. FaceNet Model
- **File name**: `facenet.tflite`
- **Input size**: 160x160x3
- **Output size**: 128 (face embedding vector)
- **Download from**: [TensorFlow Hub](https://tfhub.dev/tensorflow/facenet/1) or convert from TensorFlow SavedModel

### 2. MobileFaceNet (Lightweight alternative)
- **File name**: `mobilefacenet.tflite` (rename to `facenet.tflite`)
- **Input size**: 112x112x3
- **Output size**: 128
- **Better for mobile devices**

## Model Conversion
If you have a TensorFlow SavedModel:

```python
import tensorflow as tf

# Load your model
model = tf.keras.models.load_model('path_to_your_model')

# Convert to TensorFlow Lite
converter = tf.lite.TFLiteConverter.from_keras_model(model)
converter.optimizations = [tf.lite.Optimize.DEFAULT]
tflite_model = converter.convert()

# Save the model
with open('facenet.tflite', 'wb') as f:
    f.write(tflite_model)
```

## Current Status
Without the `.tflite` model file, the system uses:
- **Google ML Kit Face Detection** for face detection
- **Enhanced feature extraction** with color histograms and texture analysis
- **Cosine similarity** for face matching
- **80% similarity threshold** for recognition

## Performance
- **With TFLite model**: High accuracy face recognition
- **Without TFLite model**: Good face detection with basic feature matching
- **Real-time processing**: 1-3 seconds per face

## Integration
The face recognition service automatically:
1. Checks for the TFLite model on initialization
2. Falls back to enhanced detection if model not found
3. Processes faces and extracts 128-dimensional embeddings
4. Stores embeddings in the database for comparison
5. Uses cosine similarity for face matching during attendance

## File Structure
```
assets/
├── models/
│   ├── facenet.tflite        # Main face recognition model
│   └── README.md             # This file
└── images/                   # Sample images (if needed)
``` 