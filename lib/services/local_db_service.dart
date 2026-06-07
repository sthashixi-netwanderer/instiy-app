import 'dart:convert';
import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';
import '../models/message_model.dart';

class LocalDbService {
  static final LocalDbService instance = LocalDbService._init();
  static Database? _database;

  LocalDbService._init();

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDB('instiy_offline.db');
    return _database!;
  }

  Future<Database> _initDB(String filePath) async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, filePath);

    return await openDatabase(
      path,
      version: 1,
      onCreate: _createDB,
    );
  }

  Future<void> _createDB(Database db, int version) async {
    // We store the raw JSON of the message to easily re-hydrate using Message.fromJson
    await db.execute('''
      CREATE TABLE messages_cache (
        id TEXT PRIMARY KEY,
        conversation_id TEXT NOT NULL,
        created_at TEXT NOT NULL,
        raw_json TEXT NOT NULL
      )
    ''');
    
    // Index for fast conversation querying
    await db.execute('''
      CREATE INDEX idx_conversation_id 
      ON messages_cache (conversation_id, created_at DESC)
    ''');
  }

  /// Caches a batch of messages into SQLite
  Future<void> cacheMessages(List<Map<String, dynamic>> messagesJson) async {
    final db = await instance.database;
    final batch = db.batch();

    for (final json in messagesJson) {
      batch.insert(
        'messages_cache',
        {
          'id': json['id'],
          'conversation_id': json['conversation_id'],
          'created_at': json['created_at'],
          'raw_json': jsonEncode(json),
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }
    await batch.commit(noResult: true);
  }

  /// Retrieves messages from local SQLite cache for a specific conversation
  Future<List<Message>> getCachedMessages(String conversationId, {int limit = 20, int offset = 0}) async {
    final db = await instance.database;

    final maps = await db.query(
      'messages_cache',
      where: 'conversation_id = ?',
      whereArgs: [conversationId],
      orderBy: 'created_at DESC',
      limit: limit,
      offset: offset,
    );

    return maps.map((row) {
      final jsonStr = row['raw_json'] as String;
      final jsonMap = jsonDecode(jsonStr) as Map<String, dynamic>;
      return Message.fromJson(jsonMap);
    }).toList();
  }
}
