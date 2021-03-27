import 'dart:io';
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:geolocator/geolocator.dart';
import 'package:device_info/device_info.dart';
import 'package:noise_meter/noise_meter.dart';
import 'package:mysql1/mysql1.dart';

class MyHomePage extends StatefulWidget {
  MyHomePage({Key key, this.title}) : super(key: key);

  // This widget is the home page of your application. It is stateful, meaning
  // that it has a State object (defined below) that contains fields that affect
  // how it looks.

  // This class is the configuration for the state. It holds the values (in this
  // case the title) provided by the parent (in this case the App widget) and
  // used by the build method of the State. Fields in a Widget subclass are
  // always marked "final".

  final String title;

  @override
  _MyHomePageState createState() => _MyHomePageState();
}

class _MyHomePageState extends State<MyHomePage> {
  Completer<GoogleMapController> _controller = Completer();

  Map<MarkerId, Marker> markers = <MarkerId, Marker>{};
  MarkerId selectedMarker;
  int _markerIdCounter = 1;

  bool _isRecording = false;
  StreamSubscription<NoiseReading> _noiseSubscription;
  NoiseMeter _noiseMeter = new NoiseMeter();
  NoiseReading _noiseReading;

  static final DeviceInfoPlugin deviceInfoPlugin = DeviceInfoPlugin();
  String _deviceName;
  String _deviceVersion;
  String _identifier;

  var _conn = null;

  @override
  void initState() {
    super.initState();
    initPlatformState();
    connectMySQL();
  }

  @override
  void dispose() {
    closeMySQL();
    stop();
  }

  static final CameraPosition _capeTown = CameraPosition(
    target: LatLng(-33.92584, 18.423222),
    zoom: 9.6,
  );

  @override
  Widget build(BuildContext context) {
    return new Scaffold(
      body: GoogleMap(
        mapType: MapType.normal,
        initialCameraPosition: _capeTown,
        onMapCreated: (GoogleMapController controller) {
          _controller.complete(controller);
        },
        markers: Set<Marker>.of(markers.values),
        mapToolbarEnabled: false,
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _isRecording ? stop : _startPublish,
        label: _isRecording ? Text('Stop') : Text('Start'),
        icon: _isRecording ? Icon(Icons.stop) : Icon(Icons.publish),
        backgroundColor: _isRecording ? Colors.red : Colors.green,
      ),
    );
  }

  Future<void> _startPublish() async {
    start(); // Start to record

    final GoogleMapController controller = await _controller.future;
    Position position = await Geolocator()
        .getLastKnownPosition(desiredAccuracy: LocationAccuracy.high);

    final CameraPosition _capeView = CameraPosition(
        bearing: 192.8334901395799,
        target: LatLng(position != null ? position.latitude : -33.92584,
            position != null ? position.longitude : 18.423222),
        tilt: 59.440717697143555,
        zoom: 19.151926040649414);

    controller.animateCamera(CameraUpdate.newCameraPosition(_capeView));

    if (position != null) {
      var geolocator = Geolocator();
      var locationOptions =
          LocationOptions(accuracy: LocationAccuracy.high, distanceFilter: 10);

      StreamSubscription<Position> positionStream = geolocator
          .getPositionStream(locationOptions)
          .listen((Position position) {
        final String markerIdVal = 'marker_id_$_markerIdCounter';
        _markerIdCounter++;
        final MarkerId markerId = MarkerId(markerIdVal);

        var now = new DateTime.now().toUtc();

        querySQL(
            'insert into track (timestamp, deviceName, deviceVersion, identifier, noiseLevel, lat, lng) values (?, ?, ?, ?, ?, ?, ?)',
            [
              now,
              _deviceName,
              _deviceVersion,
              _identifier,
              _noiseReading.maxDecibel,
              position.latitude,
              position.longitude
            ]);

        final Marker marker = Marker(
            markerId: markerId,
            position: LatLng(
              position.latitude,
              position.longitude,
            ),
            infoWindow: InfoWindow(
              title: _deviceName,
              snippet: "Noise Level: " +
                  _noiseReading.maxDecibel.toStringAsFixed(2) +
                  " dB\n" +
                  now.toString(),
            ));

        setState(() {
          markers[markerId] = marker;
        });

        final CameraPosition _track = CameraPosition(
            bearing: 192.8334901395799,
            target: LatLng(position.latitude, position.longitude),
            tilt: 59.440717697143555,
            zoom: 19.151926040649414);

        controller.animateCamera(CameraUpdate.newCameraPosition(_track));
      });
    }
  }

  Future<void> initPlatformState() async {
    String deviceName;
    String deviceVersion;
    String identifier;

    try {
      if (Platform.isAndroid) {
        var build = await deviceInfoPlugin.androidInfo;
        deviceName = build.model;
        deviceVersion = build.version.toString();
        identifier = build.androidId; //UUID for Android
      } else if (Platform.isIOS) {
        var data = await deviceInfoPlugin.iosInfo;
        deviceName = data.name;
        deviceVersion = data.systemVersion;
        identifier = data.identifierForVendor; //UUID for iOS
      }
    } on PlatformException {
      print('Failed to get platform version');
    }

    if (!mounted) return;

    setState(() {
      _deviceName = deviceName;
      _deviceVersion = deviceVersion;
      _identifier = identifier;
    });
  }

  void onData(NoiseReading noiseReading) {
    this.setState(() {
      if (!this._isRecording) {
        this._isRecording = true;
      }
    });
    print(noiseReading.toString());
    _noiseReading = noiseReading;
  }

  void start() async {
    try {
      _noiseSubscription = _noiseMeter.noiseStream.listen(onData);
    } catch (err) {
      print(err);
    }
  }

  void stop() async {
    try {
      if (_noiseSubscription != null) {
        _noiseSubscription.cancel();
        _noiseSubscription = null;
      }
      this.setState(() {
        this._isRecording = false;
      });
    } catch (err) {
      print('stopRecorder error: $err');
    }
  }

  Future connectMySQL() async {
    var settings = new ConnectionSettings(
        host: '154.0.168.111',
        port: 3306,
        user: 'malooher_push',
        password: 'simplepush',
        db: 'malooher_simple');
    var conn = await MySqlConnection.connect(settings);

    if (!mounted) return;

    setState(() {
      _conn = conn;
    });
  }

  Future closeMySQL() async {
    if (_conn != null) {
      await _conn.close();
    }
  }

  Future querySQL(var query, var values) async {
    if (_conn != null) {
      await _conn.query(query, values);
    }
  }
}
