import 'dart:async';
import 'dart:io';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_beacon/flutter_beacon.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:rxdart/subjects.dart';
//import 'package:webview_flutter/webview_flutter.dart';

final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
    FlutterLocalNotificationsPlugin();

// Streams are created so that app can respond to notification-related events since the plugin is initialised in the `main` function
final BehaviorSubject<ReceivedNotification> didReceiveLocalNotificationSubject =
    BehaviorSubject<ReceivedNotification>();

final BehaviorSubject<String> selectNotificationSubject = BehaviorSubject<String>();

class ReceivedNotification {
  final int id;
  final String title;
  final String body;
  final String payload;

  ReceivedNotification(
      {@required this.id, @required this.title, @required this.body, @required this.payload});
}

Future<void> main() async {
  runApp(MaterialApp(home: FlutterBeacons()));
}

class FlutterBeacons extends StatefulWidget {
  @override
  _FlutterBeaconsState createState() => _FlutterBeaconsState();
}

class _FlutterBeaconsState extends State<FlutterBeacons> with WidgetsBindingObserver {
  final StreamController<BluetoothState> streamController = StreamController();
  final _regionBeacons = <Region, List<Beacon>>{};
  final _beacons = <Beacon>[];

  StreamSubscription<BluetoothState> _streamBluetooth;
  StreamSubscription<RangingResult> _streamRanging;

  //  Completer<WebViewController> _controller = Completer<WebViewController>();
  FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin;

  bool authorizationStatusOk = false;
  bool locationServiceEnabled = false;
  bool bluetoothEnabled = false;

  var _currentBeacon;

  @override
  void initState() {
    WidgetsBinding.instance.addObserver(this);

    listeningState();
    listeningFCM();

    var initializationSettingsAndroid = new AndroidInitializationSettings('app_icon');
    var initializationSettingsIOS = new IOSInitializationSettings();
    var initializationSettings =
        new InitializationSettings(initializationSettingsAndroid, initializationSettingsIOS);

    flutterLocalNotificationsPlugin = new FlutterLocalNotificationsPlugin();
    flutterLocalNotificationsPlugin.initialize(initializationSettings);

    super.initState();
  }

  listeningFCM() {
    final FirebaseMessaging _fcm = FirebaseMessaging();

    _fcm.getToken().then((token) {
      print(token);
    });

    _fcm.configure(
      onMessage: (Map<String, dynamic> message) async {
        print('onMessage: $message');
        _alertDialog(context, message['notification']['title'], message['notification']['body']);
      },
      onLaunch: (Map<String, dynamic> message) async {
        print('onLaunch: $message');
        _alertDialog(context, message['notification']['title'], message['notification']['body']);
      },
      onResume: (Map<String, dynamic> message) async {
        print('onResume: $message');
        // TODO optional
      },
    );
  }

  listeningState() async {
    print('Listening to bluetooth state');

    _streamBluetooth = flutterBeacon.bluetoothStateChanged().listen((BluetoothState state) async {
      streamController.add(state);

      switch (state) {
        case BluetoothState.stateOn:
          initScanBeacon();
          break;
        case BluetoothState.stateOff:
          await pauseScanBeacon();
          await checkAllRequirements();
          break;
      }
    });
  }

  checkAllRequirements() async {
    final bluetoothState = await flutterBeacon.bluetoothState;
    final bluetoothEnabled = bluetoothState == BluetoothState.stateOn;
    final authorizationStatus = await flutterBeacon.authorizationStatus;
    final authorizationStatusOk = authorizationStatus == AuthorizationStatus.allowed ||
        authorizationStatus == AuthorizationStatus.always;
    final locationServiceEnabled = await flutterBeacon.checkLocationServicesIfEnabled;

    setState(() {
      this.authorizationStatusOk = authorizationStatusOk;
      this.locationServiceEnabled = locationServiceEnabled;
      this.bluetoothEnabled = bluetoothEnabled;
    });
  }

  initScanBeacon() async {
    await flutterBeacon.initializeScanning;
    await checkAllRequirements();

    if (!authorizationStatusOk || !locationServiceEnabled || !bluetoothEnabled) {
      print('RETURNED, authorizationStatusOk=$authorizationStatusOk, '
          'locationServiceEnabled=$locationServiceEnabled, '
          'bluetoothEnabled=$bluetoothEnabled');
      return;
    }

    final regions = <Region>[
      Region(
          identifier: 'Beacon 1',
          proximityUUID: 'F0A4B678-6F21-45C4-AF52-C73C07AE668D',
          major: 30389,
          minor: 21485),
      Region(
          identifier: 'Beacon 2',
          proximityUUID: 'B9407F30-F5F8-466E-AFF9-25556B57FE6E',
          major: 55593,
          minor: 40398),
      Region(
          identifier: 'Beacon 3',
          proximityUUID: '6D36AC22-F0DE-43BE-8B6A-90C2925211A3',
          major: 1976,
          minor: 20868)
    ];

    if (_streamRanging != null) {
      if (_streamRanging.isPaused) {
        _streamRanging.resume();
        return;
      }
    }

    _streamRanging = flutterBeacon.ranging(regions).listen((RangingResult result) {
      if (result != null && mounted) {
        setState(() {
          _regionBeacons[result.region] = result.beacons;
          _beacons.clear();
          _regionBeacons.values.forEach((list) {
            _beacons.addAll(list);
          });
          _beacons.sort(_compareParameters);
        });
      }
    });
  }

  pauseScanBeacon() async {
    _streamRanging?.pause();
    if (_beacons.isNotEmpty) {
      setState(() {
        _beacons.clear();
      });
    }
  }

  int _compareParameters(Beacon a, Beacon b) {
    int compare = a.proximityUUID.compareTo(b.proximityUUID);

    if (compare == 0) {
      compare = a.major.compareTo(b.major);
    }

    if (compare == 0) {
      compare = a.minor.compareTo(b.minor);
    }

    return compare;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) async {
    print('AppLifecycleState = $state');

    if (state == AppLifecycleState.resumed) {
      if (_streamBluetooth != null && _streamBluetooth.isPaused) {
        _streamBluetooth.resume();
      }
      await checkAllRequirements();
      if (authorizationStatusOk && locationServiceEnabled && bluetoothEnabled) {
        await initScanBeacon();
      } else {
        await pauseScanBeacon();
        await checkAllRequirements();
      }
    } else if (state == AppLifecycleState.paused) {
      _streamBluetooth?.pause();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    streamController?.close();
    _streamRanging?.cancel();
    _streamBluetooth?.cancel();
    flutterBeacon.close;

    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      theme: ThemeData(
        brightness: Brightness.light,
        primaryColor: Colors.white,
      ),
      darkTheme: ThemeData(
        brightness: Brightness.dark,
      ),
      home: Scaffold(appBar: _mountAppBar(), body: _openBeaconContainer()),
    );
  }

  AppBar _mountAppBar() {
    return AppBar(
      title: const Text('Flutter Beacon'),
      centerTitle: false,
      actions: <Widget>[
        if (!authorizationStatusOk)
          IconButton(
              icon: Icon(Icons.portable_wifi_off),
              color: Colors.red,
              onPressed: () async {
                await flutterBeacon.requestAuthorization;
              }),
        if (!locationServiceEnabled)
          IconButton(
              icon: Icon(Icons.location_off),
              color: Colors.red,
              onPressed: () async {
                if (Platform.isAndroid) {
                  await flutterBeacon.openLocationSettings;
                } else if (Platform.isIOS) {}
              }),
        StreamBuilder<BluetoothState>(
          builder: (context, snapshot) {
            if (snapshot.hasData) {
              final state = snapshot.data;

              if (state == BluetoothState.stateOn) {
                return IconButton(
                  icon: Icon(Icons.bluetooth_connected),
                  onPressed: () async {
                    if (Platform.isAndroid) {
                      try {
                        await flutterBeacon.openBluetoothSettings;
                      } on PlatformException catch (e) {
                        print(e);
                      }
                    } else if (Platform.isIOS) {}
                  },
                  color: Colors.lightBlueAccent,
                );
              }

              if (state == BluetoothState.stateOff) {
                return IconButton(
                  icon: Icon(Icons.bluetooth),
                  onPressed: () async {
                    if (Platform.isAndroid) {
                      try {
                        await flutterBeacon.openBluetoothSettings;
                      } on PlatformException catch (e) {
                        print(e);
                      }
                    } else if (Platform.isIOS) {}
                  },
                  color: Colors.red,
                );
              }

              return IconButton(
                icon: Icon(Icons.bluetooth_disabled),
                onPressed: () {},
                color: Colors.grey,
              );
            }

            return SizedBox.shrink();
          },
          stream: streamController.stream,
          initialData: BluetoothState.stateUnknown,
        ),
      ],
    );
  }

  Container _openBeaconContainer() {
    String image;

    if (_beacons.length == 0) {
      return Container(
        decoration: new BoxDecoration(color: Colors.black),
        child: new Center(
          child: new Text(
            'Não há beacons na região!',
            style: new TextStyle(
              fontSize: 18.0,
              color: Colors.white,
            ),
          ),
        ),
      );
    }

    switch (_beacons.first.proximityUUID) {
      case 'F0A4B678-6F21-45C4-AF52-C73C07AE668D':
        image = 'images/image-1.jpg';

        setState(() {
          if (_currentBeacon == null) {
            _showNotificationWithSound(
                1, 'Olá cliente, bem-vindo!', 'Você se conectou atráves do Beacon 1.');
          } else {
            if (_beacons.first.proximityUUID != _currentBeacon.proximityUUID) {
              _showNotificationWithSound(
                  1, 'Olá cliente, bem-vindo!', 'Você se conectou atráves do Beacon 1.');
            }

            _currentBeacon = _beacons.first;
          }
        });

        break;

      case 'B9407F30-F5F8-466E-AFF9-25556B57FE6E':
        image = 'images/image-2.jpg';

        setState(() {
          if (_currentBeacon == null) {
            _showNotificationWithSound(
                2, 'Opaa! Como está indo a sua compra?', 'Você se conectou atráves do Beacon 2.');
          } else {
            if (_beacons.first.proximityUUID != _currentBeacon.proximityUUID) {
              _showNotificationWithSound(
                  2, 'Opaa! Como está indo a sua compra?', 'Você se conectou atráves do Beacon 2.');
            }
          }

          _currentBeacon = _beacons.first;
        });

        break;
      case '6D36AC22-F0DE-43BE-8B6A-90C2925211A3':
        image = 'images/image-3.jpg';

        setState(() {
          if (_currentBeacon == null) {
            _showNotificationWithSound(
                3, 'Qual é o produto que mais te agrada?', 'Você se conectou atráves do Beacon 3.');
          } else {
            if (_beacons.first.proximityUUID != _currentBeacon.proximityUUID) {
              _showNotificationWithSound(3, 'Qual é o produto que mais te agrada?',
                  'Você se conectou atráves do Beacon 3.');
            }
          }

          _currentBeacon = _beacons.first;
        });
        break;
    }

    if (_currentBeacon != null) {
      print(_currentBeacon.proximityUUID);
    }

    return Container(
      decoration: new BoxDecoration(
          image: DecorationImage(
            image: new AssetImage(image),
            fit: BoxFit.fill,
          )),
    );
  }

  void _alertDialog(BuildContext context, String title, String content) {
    showDialog(
      context: context,
      barrierDismissible: false, // user must tap button!
      builder: (BuildContext context) {
        return AlertDialog(title: Text(title), content: Text(content), actions: [
          FlatButton(
              child: Text('OK'),
              onPressed: () {
                Navigator.of(context).pop();
              })
        ]);
      },
    );
  }
}

Future _showNotificationWithSound(int id, String title, String body) async {
  var androidPlatformChannelSpecifics = new AndroidNotificationDetails(
      'your channel id', 'your channel name', 'your channel description',
      importance: Importance.Max, priority: Priority.Max);
  var iOSPlatformChannelSpecifics = new IOSNotificationDetails(sound: "slow_spring_board.aiff");
  var platformChannelSpecifics =
  new NotificationDetails(androidPlatformChannelSpecifics, iOSPlatformChannelSpecifics);

  await flutterLocalNotificationsPlugin.show(
    id,
    title,
    body,
    platformChannelSpecifics,
    payload: '',
  );
}

//class Notification {
//  Notification(this.title, this.body, this.priority, this.icon, this.to);
//
//  final String title;
//  final String body;
//  final String priority;
//  final String icon;
//  final String to;
//
//  // named constructor
//  Notification.fromJson(Map<String, dynamic> json)
//      : title = json['title'],
//        body = json['priority'],
//        priority = json['priority'],
//        icon = json['icon'],
//        to = json['to'];
//
//  // method
//  Map<String, dynamic> toJson() {
//    return {
//      'notification': {'title': title, 'body': body, 'priority': priority, 'icon': icon},
//      'to': to
//    };
//  }
//}
