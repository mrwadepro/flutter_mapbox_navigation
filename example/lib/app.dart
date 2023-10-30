import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_mapbox_navigation/flutter_mapbox_navigation.dart';
import 'package:http/http.dart' as http;
import 'package:latlng/latlng.dart';

class SampleNavigationApp extends StatefulWidget {
  const SampleNavigationApp({super.key});

  @override
  State<SampleNavigationApp> createState() => _SampleNavigationAppState();
}

class _SampleNavigationAppState extends State<SampleNavigationApp> {
  String? _platformVersion;
  String? _instruction;

  // ... (your WayPoint initializations here)

  Future<Map<String, dynamic>> loadLearningJourney() async {
    String jsonString =
        await rootBundle.loadString('assets/learning_journey_sample.json');
    return json.decode(jsonString);
  }

  List<List<WayPoint>> waypointSegments = [];
  int currentSegmentIndex = 0;

  bool _isMultipleStop = false;
  double? _distanceRemaining, _durationRemaining;
  MapBoxNavigationViewController? _controller;
  bool _routeBuilt = false;
  bool _isNavigating = false;
  bool _inFreeDrive = false;
  late MapBoxOptions _navigationOption;

  @override
  void initState() {
    super.initState();
    initialize();
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  Future<void> initialize() async {
    // If the widget was removed from the tree while the asynchronous platform
    // message was in flight, we want to discard the reply rather than calling
    // setState to update our non-existent appearance.
    if (!mounted) return;

    _navigationOption = MapBoxNavigation.instance.getDefaultOptions();
    _navigationOption.simulateRoute = true;
    _navigationOption.language = "en";
    _navigationOption.tilt = 50;
    //_navigationOption.initialLatitude = 36.1175275;
    //_navigationOption.initialLongitude = -115.1839524;
    MapBoxNavigation.instance.registerRouteEventListener(_onEmbeddedRouteEvent);

    String? platformVersion;
    // Platform messages may fail, so we use a try/catch PlatformException.
    try {
      platformVersion = await MapBoxNavigation.instance.getPlatformVersion();
    } on PlatformException {
      platformVersion = 'Failed to get platform version.';
    }

    setState(() {
      _platformVersion = platformVersion;
    });

    MapBoxNavigation.instance.registerRouteEventListener(_onEmbeddedRouteEvent);
  }

  Future<List<LatLng>> getRouteFromMapboxDirectionsAPI() async {
    String startLocation = "-96.7970,32.7767"; // Dallas, TX
    String endLocation = "-118.2437,34.0522"; // Los Angeles, CA
    String mapboxAccessToken =
        "sk.eyJ1IjoibXJ3YWRlcHJvIiwiYSI6ImNsbzdzbDJ2NTA3eGoydnBjaHhrZno3dWEifQ.4YpHjLjjgEbCeMs2269BkQ"; // Replace with your Mapbox access token

    String url =
        "https://api.mapbox.com/directions/v5/mapbox/driving/$startLocation;$endLocation?access_token=$mapboxAccessToken&geometries=geojson";

    var response = await http.get(Uri.parse(url));

    var jsonResponse = json.decode(response.body);
    List coordinates = jsonResponse['routes'][0]['geometry']['coordinates'];

    return coordinates
        .map((coordinate) => LatLng(coordinate[1], coordinate[0]))
        .toList();
  }

  Future<List<List<WayPoint>>> _getWaypointsFromRouteSegments() async {
    var journeyData = await loadLearningJourney();

    List<LatLng> routeCoordinates = await getRouteFromMapboxDirectionsAPI();

    List<List<WayPoint>> waypointSegments = [];
    List<WayPoint> currentSegment = [];
    int waypointIndex = 0;

    for (var milestone in journeyData['learning_journey']) {
      for (var lesson in milestone['lessons']) {
        if (waypointIndex < routeCoordinates.length) {
          currentSegment.add(WayPoint(
            name: lesson['lesson_title'],
            latitude: routeCoordinates[waypointIndex].latitude,
            longitude: routeCoordinates[waypointIndex].longitude,
            isSilent: false,
          ));

          if (currentSegment.length == 25) {
            waypointSegments.add(currentSegment);
            currentSegment = [];
          }

          waypointIndex++;
        } else {
          break;
        }
      }
    }

    if (currentSegment.isNotEmpty) {
      waypointSegments.add(currentSegment);
    }

    return waypointSegments;
  }

  Future<void> getWaypointsFromRoute() async {
    waypointSegments = await _getWaypointsFromRouteSegments();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        appBar: AppBar(
          title: const Text('Plugin example app'),
        ),
        body: Center(
          child: Column(children: <Widget>[
            // ... (your UI code here)

            ElevatedButton(
              child: Text("Start Learning Journey"),
              onPressed: () async {
                try {
                  await getWaypointsFromRoute();
                  if (waypointSegments.isNotEmpty) {
                    currentSegmentIndex = 0;
                    var opt = MapBoxOptions.from(_navigationOption);
                    opt.simulateRoute = true;
                    opt.voiceInstructionsEnabled = true;
                    opt.bannerInstructionsEnabled = true;
                    opt.units = VoiceUnits.metric;
                    opt.language = "en";
                    print("Options! ${opt}");

                    await MapBoxNavigation.instance.startNavigation(
                        wayPoints: waypointSegments[currentSegmentIndex],
                        options: opt);
                  }
                } catch (e) {
                  print("Error starting navigation: $e");
                }
              },
            ),

            // ... (rest of your UI code here)
          ]),
        ),
      ),
    );
  }

  Future<void> _onEmbeddedRouteEvent(e) async {
    _distanceRemaining = await MapBoxNavigation.instance.getDistanceRemaining();
    _durationRemaining = await MapBoxNavigation.instance.getDurationRemaining();

    switch (e.eventType) {
      case MapBoxEvent.progress_change:
        var progressEvent = e.data as RouteProgressEvent;
        if (progressEvent.currentStepInstruction != null) {
          _instruction = progressEvent.currentStepInstruction;
        }
        break;
      case MapBoxEvent.route_building:
      case MapBoxEvent.route_built:
        setState(() {
          _routeBuilt = true;
        });
        break;
      case MapBoxEvent.route_build_failed:
        setState(() {
          _routeBuilt = false;
        });
        break;
      case MapBoxEvent.navigation_running:
        setState(() {
          _isNavigating = true;
        });
        break;

      case MapBoxEvent.on_arrival:
        if (currentSegmentIndex < waypointSegments.length - 1) {
          currentSegmentIndex++;
          var opt = MapBoxOptions.from(_navigationOption);
          opt.simulateRoute = true;
          opt.voiceInstructionsEnabled = true;
          opt.bannerInstructionsEnabled = true;
          opt.units = VoiceUnits.metric;
          opt.language = "en";
          await MapBoxNavigation.instance.startNavigation(
              wayPoints: waypointSegments[currentSegmentIndex], options: opt);
        }
        break;

      case MapBoxEvent.navigation_finished:
      case MapBoxEvent.navigation_cancelled:
        setState(() {
          _routeBuilt = false;
          _isNavigating = false;
        });
        break;
      default:
        break;
    }
    setState(() {});
  }
}
