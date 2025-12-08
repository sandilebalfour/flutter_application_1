import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../state/app_state.dart';

class TimelinePage extends StatelessWidget {
  const TimelinePage({super.key});

  @override
  Widget build(BuildContext context) {
    final app = Provider.of<AppState>(context);
    final sortedCheckpoints = [...app.checkpoints]..sort((a, b) => a.createdAt.compareTo(b.createdAt));

    return Scaffold(
      appBar: AppBar(title: const Text('My Journey Timeline')),
      body: sortedCheckpoints.isEmpty
          ? const Center(child: Text('No journey milestones yet. Add one to get started!'))
          : SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 32.0),
              child: Column(
                children: [
                  // Road/path visualization
                  SizedBox(
                    width: double.infinity,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: List.generate(
                        sortedCheckpoints.length,
                        (index) {
                          final cp = sortedCheckpoints[index];
                          final isLast = index == sortedCheckpoints.length - 1;

                          return Column(
                            children: [
                              // Road segment (vertical line)
                              if (index > 0)
                                Container(
                                  width: 8,
                                  height: 40,
                                  decoration: BoxDecoration(
                                    color: sortedCheckpoints[index - 1].completed ? Colors.green : Colors.blue,
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                ),
                              // Milestone button
                              GestureDetector(
                                onTap: () {
                                  // Show milestone details
                                  showDialog(
                                    context: context,
                                    builder: (ctx) => AlertDialog(
                                      title: Text(cp.title),
                                      content: Column(
                                        mainAxisSize: MainAxisSize.min,
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text('Created: ${cp.createdAt.toString().split('.')[0]}'),
                                          if (cp.completed && cp.completedAt != null)
                                            Padding(
                                              padding: const EdgeInsets.only(top: 8.0),
                                              child: Text('Completed: ${cp.completedAt.toString().split('.')[0]}', style: const TextStyle(color: Colors.green, fontWeight: FontWeight.bold)),
                                            ),
                                          if (!cp.completed)
                                            Padding(
                                              padding: const EdgeInsets.only(top: 8.0),
                                              child: Text('Status: In Progress', style: const TextStyle(color: Colors.blue)),
                                            ),
                                        ],
                                      ),
                                      actions: [
                                        if (!cp.completed)
                                          ElevatedButton(
                                            onPressed: () {
                                              Provider.of<AppState>(context, listen: false).completeCheckpoint(cp.id);
                                              Navigator.pop(ctx);
                                            },
                                            child: const Text('Mark Complete'),
                                          ),
                                        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Close')),
                                      ],
                                    ),
                                  );
                                },
                                child: Container(
                                  width: 120,
                                  height: 120,
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    color: cp.completed ? Colors.green : Colors.blue,
                                    boxShadow: [
                                      BoxShadow(
                                        color: (cp.completed ? Colors.green : Colors.blue).withValues(alpha: 0.5),
                                        blurRadius: 12,
                                        spreadRadius: 2,
                                      ),
                                    ],
                                  ),
                                  child: Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Icon(
                                        cp.completed ? Icons.check_circle : Icons.location_on,
                                        color: Colors.white,
                                        size: 40,
                                      ),
                                      const SizedBox(height: 6),
                                      Padding(
                                        padding: const EdgeInsets.symmetric(horizontal: 8.0),
                                        child: Text(
                                          cp.title,
                                          textAlign: TextAlign.center,
                                          style: const TextStyle(
                                            color: Colors.white,
                                            fontWeight: FontWeight.bold,
                                            fontSize: 11,
                                          ),
                                          maxLines: 2,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                              // Info card below milestone
                              Padding(
                                padding: const EdgeInsets.only(top: 12.0, bottom: 8.0),
                                child: Card(
                                  color: cp.completed ? Colors.green.withValues(alpha: 0.1) : Colors.blue.withValues(alpha: 0.1),
                                  child: Padding(
                                    padding: const EdgeInsets.all(8.0),
                                    child: Column(
                                      children: [
                                        Text(
                                          'Created: ${cp.createdAt.toString().split('.')[0]}',
                                          style: const TextStyle(fontSize: 11, color: Colors.grey),
                                        ),
                                        if (cp.completed && cp.completedAt != null)
                                          Text(
                                            'Completed: ${cp.completedAt.toString().split('.')[0]}',
                                            style: const TextStyle(fontSize: 11, color: Colors.green, fontWeight: FontWeight.bold),
                                          ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                              // Road segment after (vertical line)
                              if (!isLast)
                                Container(
                                  width: 8,
                                  height: 60,
                                  decoration: BoxDecoration(
                                    color: cp.completed ? Colors.green : Colors.blue,
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                ),
                            ],
                          );
                        },
                      ),
                    ),
                  ),
                  // Finish line if all completed
                  if (sortedCheckpoints.isNotEmpty && sortedCheckpoints.every((cp) => cp.completed))
                    Padding(
                      padding: const EdgeInsets.only(top: 40.0),
                      child: Column(
                        children: [
                          const Icon(Icons.flag_circle, size: 80, color: Colors.amber),
                          const SizedBox(height: 12),
                          const Text(
                            'Journey Complete! 🎉',
                            style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.amber),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
    );
  }
}
