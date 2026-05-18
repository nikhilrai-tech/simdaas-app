import 'package:flutter/material.dart';
import 'package:pdfrx/pdfrx.dart';

class UserGuidePdfScreen extends StatelessWidget {
  const UserGuidePdfScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('User Guide')),
      body: PdfViewer.asset('assets/user_guide.pdf'),
    );
  }
}
