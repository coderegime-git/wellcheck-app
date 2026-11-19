import 'package:flutter/material.dart';

class NoInterNetScreen extends StatefulWidget {
  const NoInterNetScreen({super.key});

  static const routeName = 'no_internet';

  @override
  State<NoInterNetScreen> createState() => _NoInterNetScreenState();
}

class _NoInterNetScreenState extends State<NoInterNetScreen> {
  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      child: Scaffold(
        body: Container(
          padding: EdgeInsets.symmetric(horizontal: 50),
          child: Stack(
            children: [
              Positioned(
                top: 50,
                child: Icon(
                  Icons.wifi_off,
                  size: 300,
                  color: Colors.grey.shade300,
                ),
              ),
              Positioned(
                top: 100,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.start,
                  /* crossAxisAlignment: CrossAxisAlignment.center,
                  mainAxisAlignment: MainAxisAlignment.center,*/
                  children: [
                    /* Icon(Icons.network_check_rounded, color: Colors.red,
                        size: 200),*/
                    SizedBox(height: 20),
                    Text(
                      'Your are\ncurrently\noffline!',
                      style: TextStyle(
                        color: Colors.black,
                        fontSize: 34,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    SizedBox(height: 20),
                    Text(
                      'We were unable to load the page\nyou requested',
                      style: TextStyle(fontSize: 18, color: Colors.black),
                    ),
                    SizedBox(height: 5),
                    Text(
                      'please check your network\nconnection and try again',
                      style: TextStyle(fontSize: 18, color: Colors.black),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
