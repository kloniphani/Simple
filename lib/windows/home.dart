import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:geolocator/geolocator.dart';
import 'package:device_info/device_info.dart';

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

  static final CameraPosition _capeTown = CameraPosition(
    target: LatLng(-33.92584, 18.423222),
    zoom: 9.6,
  );

  @override
  Widget build(BuildContext context) {
    return new Scaffold(
      body: GoogleMap(
        mapType: MapType.hybrid,
        initialCameraPosition: _capeTown,
        onMapCreated: (GoogleMapController controller) {
          _controller.complete(controller);
        },
        markers: Set<Marker>.of(markers.values),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _startPublish,
        label: Text('Start'),
        icon: Icon(Icons.publish),
      ),
    );
  }

  Future<void> _startPublish() async {
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

        final Marker marker = Marker(
          markerId: markerId,
          position: LatLng(
            position.latitude,
            position.longitude,
          ),
          infoWindow: InfoWindow(title: 'Unknown', 
            snippet: "*",
         )
        );

        setState(() {
          markers[markerId] = marker;
        });

        final CameraPosition _track = CameraPosition(
          bearing: 192.8334901395799,
          target: LatLng(position.latitude,
            position.longitude ),
            tilt: 59.440717697143555,
          zoom: 19.151926040649414);

        controller.animateCamera(CameraUpdate.newCameraPosition(_track));

      });
    }
  }
}
