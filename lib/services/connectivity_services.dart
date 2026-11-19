import 'dart:async';
import 'dart:io';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:well_check_v3/features/auth/splash_screen.dart';

import '../core/navigation/no_network_screen.dart';

class ConnectivityService {
  static final ConnectivityService _instance = ConnectivityService._internal();

  factory ConnectivityService() => _instance;

  ConnectivityService._internal();

  bool _started = false;

  StreamSubscription<List<ConnectivityResult>>? _connectivitySubscription;
  bool _isNoInternetPageShown = false;
  BuildContext? _currentContext;

  void startMonitoring(BuildContext context) {
    if (_started) return;
    _started = true;

    _currentContext = context;
    _connectivitySubscription?.cancel();
    _connectivitySubscription = Connectivity().onConnectivityChanged.listen((
      List<ConnectivityResult> results,
    ) async {
      bool hasInternet = await _hasInternet();

      bool isConnected = results.any(
        (r) =>
            r == ConnectivityResult.wifi ||
            r == ConnectivityResult.mobile ||
            r == ConnectivityResult.ethernet,
      );

      if (!isConnected || !hasInternet) {
        if (!_isNoInternetPageShown && _currentContext != null) {
          _isNoInternetPageShown = true;
          Navigator.push(
            _currentContext!,
            MaterialPageRoute(builder: (_) => const NoInterNetScreen()),
          ).then((_) {
            _isNoInternetPageShown = false;
          });
        }
        SharedPreferences prefs = await SharedPreferences.getInstance();

        await prefs.setBool('internet', true ?? false);
        //   await AppData.setInternet(true);
      } else {
        if (_isNoInternetPageShown && _currentContext != null) {
          SharedPreferences prefs = await SharedPreferences.getInstance();

          await prefs.setBool('internet', false ?? false);
          // await AppData.setInternet(false);

          prefs.getBool('navigate') ?? false;
          bool splash = prefs.getBool('navigate') ?? false;
          if (splash) {
            Navigator.pop(_currentContext!);
            Navigator.push(
              _currentContext!,
              MaterialPageRoute(builder: (context) => const SplashScreen()),
            );
          } else {
            print("Internet restored - attempting to pop NoInternet page");
            if (_isNoInternetPageShown &&
                Navigator.of(_currentContext!).canPop()) {
              _isNoInternetPageShown = false;
              Navigator.of(_currentContext!).pop();
            } else {
              print("Cannot pop - NoInternet page not on top");
              _isNoInternetPageShown = false;
            }
          }
        }
      }
    });
  }

  Future<bool> _hasInternet() async {
    try {
      final result = await InternetAddress.lookup('google.com');
      return result.isNotEmpty && result[0].rawAddress.isNotEmpty;
    } on SocketException catch (_) {
      return false;
    }
  }

  void dispose() {
    _started = false;

    _connectivitySubscription?.cancel();
    _currentContext = null;
  }
}

class ConnectivityNavigatorObserver extends NavigatorObserver {
  final ConnectivityService connectivityService;

  ConnectivityNavigatorObserver(this.connectivityService);

  @override
  void didPush(Route route, Route? previousRoute) {
    super.didPush(route, previousRoute);
    if (navigator != null) {
      connectivityService.startMonitoring(navigator!.context);
    }
  }

  @override
  void didPop(Route route, Route? previousRoute) {
    super.didPop(route, previousRoute);
    if (navigator != null) {
      connectivityService.startMonitoring(navigator!.context);
    }
  }
}
