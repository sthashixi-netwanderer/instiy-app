import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';
import '../models/message_model.dart';

class LocalDbService {
  static final LocalDbService instance = LocalDbService._init();
  static Database? _database;

  LocalDbService._init();

  /// Returns null on web — sqflite has no web target.
  Future<Database?> get database async {
    if (kIsWeb) return null;
    if (_database != null) return _database!;
    _database = await _initDB('instiy_offline.db');
    return _database!;
  }

  Future<Database> _initDB(String filePath) async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, filePath);

    return await openDatabase(
      path,
      version: 2,
      onCreate: _createDB,
      onUpgrade: _upgradeDB,
    );
  }

  Future<void> _createDB(Database db, int version) async {
    await db.execute('''
      CREATE TABLE messages_cache (
        id TEXT PRIMARY KEY,
        conversation_id TEXT NOT NULL,
        created_at TEXT NOT NULL,
        raw_json TEXT NOT NULL
      )
    ''');

    await db.execute('''
      CREATE INDEX idx_conversation_id
      ON messages_cache (conversation_id, created_at DESC)
    ''');

    if (version >= 2) {
      await _createConversationsCache(db);
    }
  }

  Future<void> _upgradeDB(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      await _createConversationsCache(db);
    }
  }

  Future<void> _createConversationsCache(Database db) async {
    await db.execute('''
      CREATE TABLE conversations_cache (
        id TEXT PRIMARY KEY,
        user_id TEXT NOT NULL,
        raw_json TEXT NOT NULL,
        last_message_at TEXT,
        updated_at TEXT NOT NULL
      )
    ''');
    await db.execute('''
      CREATE INDEX idx_conv_cache_user
      ON conversations_cache (user_id, last_message_at DESC)
    ''');
  }

  /// Caches a batch of messages into SQLite (no-op on web).
  Future<void> cacheMessages(List<Map<String, dynamic>> messagesJson) async {
    final db = await database;
    if (db == null) return; // web: no-op
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

  /// Retrieves messages from local SQLite cache (returns empty on web).
  Future<List<Message>> getCachedMessages(String conversationId, {int limit = 20, int offset = 0}) async {
    final db = await database;
    if (db == null) return []; // web: no offline cache

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

  /// Cache conversations for a user (no-op on web).
  Future<void> cacheConversations(String userId, List<Conversation> conversations) async {
    final db = await database;
    if (db == null) return; // web: no-op
    final now = DateTime.now().toIso8601String();
    final batch = db.batch();

    await db.delete('conversations_cache', where: 'user_id = ?', whereArgs: [userId]);

    for (final conv in conversations) {
      batch.insert(
        'conversations_cache',
        {
          'id': conv.id,
          'user_id': userId,
          'raw_json': jsonEncode(conv.toJson()),
          'last_message_at': conv.lastMessageAt?.toIso8601String(),
          'updated_at': now,
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }
    await batch.commit(noResult: true);
  }

  /// Get cached conversations for a user (returns empty on web).
  Future<List<Conversation>> getCachedConversations(String userId) async {
    final db = await database;
    if (db == null) return []; // web: no offline cache

    final maps = await db.query(
      'conversations_cache',
      where: 'user_id = ?',
      whereArgs: [userId],
      orderBy: 'last_message_at DESC',
    );

    return maps.map((row) {
      final jsonStr = row['raw_json'] as String;
      final jsonMap = jsonDecode(jsonStr) as Map<String, dynamic>;
      return Conversation.fromJson(jsonMap);
    }).toList();
  }
}
