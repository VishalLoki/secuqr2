import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:google_mlkit_barcode_scanning/google_mlkit_barcode_scanning.dart';
import 'package:path_provider/path_provider.dart';
import 'package:secuqr/colors/appcolor.dart';
import 'package:secuqr/result_qr.dart';
import 'detector_view.dart';
import 'painters/barcode_detector_painter.dart';

class BarcodeScannerView extends StatefulWidget {
  const BarcodeScannerView({super.key});

  @override
  State<BarcodeScannerView> createState() => _BarcodeScannerViewState();
}

class _BarcodeScannerViewState extends State<BarcodeScannerView> {
  final BarcodeScanner _barcodeScanner =
      BarcodeScanner(formats: [BarcodeFormat.qrCode]);
  late List<Offset> corners;
  bool _canProcess = true;
  bool _isBusy = false;
  CustomPaint? _customPaint;
  String? _text;
  CameraLensDirection _cameraLensDirection = CameraLensDirection.back;
  double _barcodeSize = 0;
  CameraController? _cameraController;
  Size? _cameraSize;
  Timer? _captureTimer;
  bool _isCapturing = false;

  @override
  void initState() {
    super.initState();
    _initializeCamera();
  }

  Future<void> _initializeCamera() async {
    final cameras = await availableCameras();
    _cameraController = CameraController(
      cameras.first,
      ResolutionPreset.high,
    );

    try {
      await _cameraController!.initialize();
      _cameraSize = _cameraController!.value.previewSize;
      setState(() {});
    } catch (e) {
      if (kDebugMode) {
        print('Error initializing camera: $e');
      }
    }
  }

  Future<void> _pauseCamera() async {
    if (_cameraController?.value.isInitialized ?? false) {
      await _cameraController!.pausePreview();
    }
  }

  @override
  void dispose() {
    _captureTimer?.cancel();
    _canProcess = false;
    _barcodeScanner.close();
    _cameraController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isCameraInitialized = _cameraController?.value.isInitialized ?? false;
    final screenSize = MediaQuery.of(context).size;

    return Scaffold(
      backgroundColor: AppColors.statusBarColor,
      body: Column(
        children: [
          Expanded(
            child: isCameraInitialized
                ? Stack(
                    children: [
                      CameraPreview(_cameraController!),
                      DetectorView(
                        title: 'Barcode Scanner',
                        customPaint: _customPaint,
                        text: _text,
                        onImage: (inputImage) =>
                            _processImage(inputImage, screenSize),
                        initialCameraLensDirection: _cameraLensDirection,
                        onCameraLensDirectionChanged: (value) =>
                            _cameraLensDirection = value,
                      ),
                    ],
                  )
                : const Center(child: CircularProgressIndicator()),
          ),
          if (_barcodeSize > 0)
            Padding(
              padding: EdgeInsets.all(screenSize.width * 0.05),
              child: Text(
                'Max Barcode Size: ${_barcodeSize.toStringAsFixed(2)}',
                style: const TextStyle(color: Colors.white),
              ),
            ),
        ],
      ),
    );
  }

  Future<void> _processImage(InputImage inputImage, Size screenSize) async {
    if (!_canProcess || _isBusy || _isCapturing) return;
    _isBusy = true;
    setState(() {
      _text = '';
    });

    try {
      final barcodes = await _barcodeScanner.processImage(inputImage);

      if (inputImage.metadata?.size != null &&
          inputImage.metadata?.rotation != null) {
        final painter = BarcodeDetectorPainter(
          barcodes,
          inputImage.metadata!.size,
          inputImage.metadata!.rotation,
          _cameraLensDirection,
          (size) {
            SchedulerBinding.instance.addPostFrameCallback((_) {
              if (mounted) {
                setState(() {
                  _barcodeSize = size;
                });
                _adjustZoom(size);
                print("adjusting...");
                // Only start the capture timer if it hasn't already been started and we are not capturing
                if (!_isCapturing &&
                    (_captureTimer == null || !_captureTimer!.isActive)) {
                  print("capturingg.....");
                  _startCaptureTimer();
                }
              }
            });
          },
          _cameraSize ?? Size.zero,
        );

        _customPaint = CustomPaint(painter: painter);
      } else {
        String text = 'Barcodes found: ${barcodes.length}\n\n';
        for (final barcode in barcodes) {
          text += 'Barcode: ${barcode.rawValue}\n\n';
        }

        setState(() {
          _text = text;
          _customPaint = null;
        });
      }
    } catch (e) {
      if (kDebugMode) {
        print('Error processing image: $e');
      }
    } finally {
      _isBusy = false;
    }
  }

  Future<void> _captureImage() async {
    // Check if capture is already in progress or if the camera is not initialized
    if (_isCapturing ||
        _cameraController == null ||
        !_cameraController!.value.isInitialized) {
      return;
    }

    try {
      // Check if the widget is still mounted and the camera is initialized
      if (!mounted || !_cameraController!.value.isInitialized) {
        setState(() {
          _isCapturing = false;
        });
        return;
      }

      // Capture the image
      final XFile image = await _cameraController!.takePicture();
      final Uint8List imageBytes = await image.readAsBytes();
      _cameraController?.dispose();
      setState(() {
        _isCapturing = true;
      });
      if (kDebugMode) {
        print("Capturing image...");
      }

      // Cancel the timer if it exists
      setState(() {
        _captureTimer?.cancel();
      });

      // Save the image to a temporary directory
      final String tempPath = (await getTemporaryDirectory()).path;
      final File imageFile = File('$tempPath/temp_image.png');
      await imageFile.writeAsBytes(imageBytes);

      final inputImage = InputImage.fromFilePath(imageFile.path);

      // Navigate to the DisplayImagePage
      if (mounted) {
        // Navigator.pushAndRemoveUntil(
        //   context,
        //   MaterialPageRoute(
        //     builder: (context) => DisplayImagePage(
        //       inputImage: inputImage,
        //       imageFile: imageFile,
        //     ),
        //   ),
        //   ModalRoute.withName('/'),
        // );
      }
      // Dispose the camera controller after the image is saved
      // _cameraController?.dispose();
    } catch (e) {
      if (kDebugMode) {
        print('Error capturing image: $e');
      }
    } finally {
      // Ensure that the widget is still mounted before updating state
      if (mounted) {
        setState(() {
          _isCapturing = false;
        });
      }
    }
  }

  void _adjustZoom(double barcodeSize) {
    if (barcodeSize >= 8000) return;

    double zoomLevel = 1.0;

    if (barcodeSize < 1000) {
      zoomLevel = 5.0;
    } else if (barcodeSize < 1500) {
      zoomLevel = 4.75;
    } else if (barcodeSize < 2000) {
      zoomLevel = 4.5;
    } else if (barcodeSize < 3000) {
      zoomLevel = 4.0;
    } else if (barcodeSize < 4000) {
      zoomLevel = 3.5;
    } else if (barcodeSize < 5000) {
      zoomLevel = 3.0;
    } else if (barcodeSize < 6000) {
      zoomLevel = 2.5;
    } else if (barcodeSize < 7000) {
      zoomLevel = 2.0;
    } else {
      zoomLevel = 1.5;
    }

    if (_cameraController?.value.isInitialized ?? false) {
      _cameraController!.setZoomLevel(zoomLevel);
    }
  }

  void _startCaptureTimer() {
    // _captureTimer?.cancel();
    _captureTimer = Timer(const Duration(seconds: 1), _captureImage);
  }
}
