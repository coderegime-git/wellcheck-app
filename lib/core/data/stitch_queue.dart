import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class StitchQueue {
  static Database? _db;

  static Future<Database> get database async {
    if (_db != null) return _db!;
    _db = await _initDb();
    return _db!;
  }

  static Future<Database> _initDb() async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, 'stitch_queue.db');

    return await openDatabase(
      path,
      version: 1,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE offline_queue (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            action_type TEXT NOT NULL,
            payload TEXT NOT NULL,
            timestamp DATETIME DEFAULT CURRENT_TIMESTAMP
          )
        ''');
      },
    );
  }

  static Future<void> enqueue(String type, Map<String, dynamic> payload) async {
    final db = await database;
    await db.insert('offline_queue', {
      'action_type': type,
      'payload': jsonEncode(payload),
    });
  }

  static Future<void> processQueue(SupabaseClient client) async {
    final db = await database;
    final List<Map<String, dynamic>> maps = await db.query('offline_queue');

    for (var item in maps) {
      final type = item['action_type'];
      final payload = jsonDecode(item['payload']) as Map<String, dynamic>;

      try {
        if (type == 'pulse') {
          await client.from('well_events').insert(payload);
        } else if (type == 'medication_log') {
          await client.from('well_events').insert(payload);
        }
        
        // Success: remove from local queue
        await db.delete('offline_queue', where: 'id = ?', whereArgs: [item['id']]);
      } catch (e) {
        // Still offline or failed: keep in queue for next run
        debugPrint('Queue processing failed for item ${item['id']}: $e');
      }
    }
  }
}
