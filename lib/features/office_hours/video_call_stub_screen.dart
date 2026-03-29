import 'package:flutter/material.dart';

class VideoCallStubScreen extends StatelessWidget {
  const VideoCallStubScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Video Call')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Video call (stub)',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 8),
            const Text(
              'Frontend placeholder. Later you can plug in WebRTC/Zoom-like SDK.'
              ' For now this screen represents the call UI entry point.',
            ),
            const SizedBox(height: 9),
            FilledButton.icon(
              onPressed: () => Navigator.of(context).pop(),
              icon: const Icon(Icons.call_end),
              label: const Text('End'),
            ),
          ],
        ),
      ),
    );
  }
}
