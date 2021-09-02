import 'dart:async';
// In order to *not* need this ignore, consider extracting the "web" version
// of your plugin as a separate package, instead of inlining it in the same
// package as the core of your plugin.
// ignore: avoid_web_libraries_in_flutter
import 'dart:html';
import 'dart:js';
import 'package:camcode/dart_ui_stub/dart_ui.dart' as ui;

import 'package:camcode/barcode.dart';
import 'package:flutter/services.dart';
import 'package:flutter_web_plugins/flutter_web_plugins.dart';

/// A web implementation of the Camcode plugin.
class CamcodeWeb {
  // VideoElement used to display the camera image
  late VideoElement _webcamVideoElement;
  // ImageElement used to display taken pictures
  late ImageElement imageElement;
  // The current processing image
  late ImageData image;
  // timer shceduling the pictures treatment process
  late Timer _timer;
  // indicates if the the scan got result or not
  bool gotResult = false;
  // used to transmit result to the Widget via MethodChannel
  late Completer<String> completer;

  // Registering method
  static void registerWith(Registrar registrar) {
    final channel = MethodChannel(
      'camcode',
      const StandardMethodCodec(),
      // ignore: unnecessary_cast
      registrar as BinaryMessenger,
    );

    final pluginInstance = CamcodeWeb();
    channel.setMethodCallHandler(pluginInstance.handleMethodCall);
  }

  // handle channel calls
  Future<dynamic> handleMethodCall(MethodCall call) async {
    switch (call.method) {
      case 'initialize':
        final List arguments = call.arguments;
        return initialize(
          arguments[0],
          arguments[1],
          arguments[2],
        );
      case 'defineScanzone':
        _scanZoneX = call.arguments.length > 0 ? call.arguments[0] : null;
        _scanZoneY = call.arguments.length > 1 ? call.arguments[1] : null;
        _scanZoneWidth = call.arguments.length > 2 ? call.arguments[2] : null;
        _scanZoneHeight = call.arguments.length > 3 ? call.arguments[3] : null;
        break;
      case 'releaseResources':
        return releaseResources();
      case 'fetchResult':
        return fetchResult();
      default:
        throw PlatformException(
          code: 'Unimplemented',
          details: 'camcode for web doesn\'t implement \'${call.method}\'',
        );
    }
  }

  // wait for the result to be completed
  Future<String> fetchResult() {
    return completer.future;
  }

  int? _scanZoneX;
  int? _scanZoneY;
  double? _scanZoneWidth;
  double? _scanZoneHeight;

  /// Initialize the scanner :
  /// - request user permission
  /// - request camera stream
  /// - initialize video
  /// - start video streaming
  /// - start picture snapshot timer scheduling
  int initialize(
    double width,
    double height,
    int refreshDelayMillis,
  ) {
    completer = Completer<String>();
    gotResult = false;
    // Create a video element which will be provided with stream source
    _webcamVideoElement = VideoElement()
      ..width = width.toInt()
      ..height = height.toInt()
      ..autoplay = true
      ..muted = true;
    _webcamVideoElement.setAttribute('playsinline', 'true');

    imageElement = ImageElement()
      ..width = 320
      ..height = 320;

    // Register an webcam

    final time = DateTime.now().microsecondsSinceEpoch;

    // ignore: undefined_prefixed_name
    ui.platformViewRegistry.registerViewFactory(
      'webcamVideoElement$time',
      (int viewId) => _webcamVideoElement,
    );
    // ignore: undefined_prefixed_name
    ui.platformViewRegistry.registerViewFactory(
      'imageElement',
      (int viewId) => imageElement,
    );

    // Access the webcam stream
    if (window.location.protocol.contains('https')) {
      var options;
      if (window.navigator.userAgent.contains('Mobi')) {
        options = {
          'audio': false,
          'video': {
            'facingMode': {'exact': 'environment'},
            'width': width.toInt(),
            'height': height.toInt()
          }
        };
      } else {
        options = {
          'audio': false,
          'video': {'width': width.toInt(), 'height': height.toInt()}
        };
      }
      window.navigator.mediaDevices
          ?.getUserMedia(options)
          .then((MediaStream stream) {
        _webcamVideoElement.srcObject = stream;
      });
    } else {
      window.navigator.getUserMedia(video: true).then((MediaStream stream) {
        _webcamVideoElement.srcObject = stream;
      });
    }

    Future.delayed(Duration(seconds: 1), () {
      _timer = Timer.periodic(Duration(milliseconds: refreshDelayMillis),
          (timer) async {
        _takePicture(
          _scanZoneX,
          _scanZoneY,
          _scanZoneWidth,
          _scanZoneHeight,
        );
      });
    });

    return time;
  }

  /// Takes a picture of the current camera image
  /// and process it for barcode identification
  void _takePicture(
    int? scanZoneX,
    int? scanZoneY,
    double? scanZoneWidth,
    double? scanZoneHeight,
  ) async {
    final _canvasElement = CanvasElement(
      width: _webcamVideoElement.width,
      height: _webcamVideoElement.height,
    );
    final context = _canvasElement.context2D;
    // TODO: Reduce size of image allowing to detect barcodes
    context.drawImageScaled(
      _webcamVideoElement,
      scanZoneX ?? 0,
      scanZoneY ?? 0,
      scanZoneWidth ?? _webcamVideoElement.width,
      scanZoneHeight ?? _webcamVideoElement.height,
    );
    image = context.getImageData(
      scanZoneX ?? 0,
      scanZoneY ?? 0,
      scanZoneWidth?.toInt() ?? _canvasElement.width ?? 0,
      scanZoneHeight?.toInt() ?? _canvasElement.height ?? 0,
    );
    final dataUrl = _canvasElement.toDataUrl('image/png');
    imageElement.src = dataUrl;

    detectBarcode(dataUrl, allowInterop((result) => onBarcodeResult(result)));
  }

  // Method called on barcode result to finish the process and send result
  Future<void> onBarcodeResult(String _barcode) async {
    if (!gotResult) {
      gotResult = true;
      releaseResources();
      completer.complete(_barcode);
    }
  }

  // Release resources to avoid leaks
  void releaseResources() {
    _timer.cancel();
    _webcamVideoElement.pause();
    _webcamVideoElement.srcObject?.getTracks().forEach((track) {
      track.stop();
      track.enabled = false;
    });
    _webcamVideoElement.srcObject = null;
  }
}
