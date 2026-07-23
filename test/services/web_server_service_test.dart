import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:easy_memory/data/database.dart';
import 'package:easy_memory/data/rule_repository.dart';
import 'package:easy_memory/data/match_item_repository.dart';
import 'package:easy_memory/data/file_record_repository.dart';
import 'package:easy_memory/models/rule.dart';
import 'package:easy_memory/models/match_item.dart';
import 'package:easy_memory/models/file_record.dart';
import 'package:easy_memory/services/web_server_service.dart';

void main() {
  late Database db;
  late RuleRepository ruleRepo;
  late MatchItemRepository matchItemRepo;
  late FileRecordRepository fileRecordRepo;
  late WebServerService server;

  setUp(() async {
    sqfliteFfiInit();
    db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
    // Create tables
    await db.execute('''
      CREATE TABLE rules (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL,
        regex_pattern TEXT NOT NULL,
        format_string TEXT NOT NULL DEFAULT '\$0',
        scan_directory TEXT,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL
      )
    ''');
    await db.execute('''
      CREATE TABLE match_items (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        rule_id INTEGER NOT NULL,
        match_value TEXT NOT NULL,
        created_at TEXT NOT NULL,
        FOREIGN KEY (rule_id) REFERENCES rules (id) ON DELETE CASCADE
      )
    ''');
    await db.execute('''
      CREATE TABLE file_records (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        match_item_id INTEGER NOT NULL,
        file_name TEXT NOT NULL,
        full_path TEXT NOT NULL,
        directory TEXT NOT NULL,
        scanned_at TEXT NOT NULL,
        FOREIGN KEY (match_item_id) REFERENCES match_items (id) ON DELETE CASCADE
      )
    ''');
    await db.execute('CREATE INDEX idx_match_items_rule_id ON match_items (rule_id)');
    await db.execute('CREATE INDEX idx_file_records_match_item_id ON file_records (match_item_id)');

    DatabaseHelper.setDatabaseForTesting(db);

    ruleRepo = RuleRepository();
    matchItemRepo = MatchItemRepository();
    fileRecordRepo = FileRecordRepository();
    server = WebServerService();
  });

  tearDown(() async {
    await server.stop();
    await db.close();
    DatabaseHelper.setDatabaseForTesting(db);
  });

  group('WebServerService', () {
    test('start and stop server', () async {
      expect(server.isRunning, false);
      await server.start(port: 0);
      expect(server.isRunning, true);
      expect(server.port, greaterThan(0));
      await server.stop();
      expect(server.isRunning, false);
    });

    test('GET / returns HTML page', () async {
      await server.start(port: 0);
      final client = HttpClient();
      try {
        final request = await client.getUrl(Uri.parse('http://127.0.0.1:${server.port}/'));
        final response = await request.close();
        expect(response.statusCode, 200);
        final body = await response.transform(utf8.decoder).join();
        expect(body, contains('Easy Memory'));
        expect(body, contains('<!DOCTYPE html>'));
      } finally {
        client.close();
      }
    });

    test('GET /api/query returns empty list for no match', () async {
      await server.start(port: 0);
      final client = HttpClient();
      try {
        final request = await client.getUrl(
          Uri.parse('http://127.0.0.1:${server.port}/api/query?match=NOTHING'),
        );
        final response = await request.close();
        expect(response.statusCode, 200);
        final body = await response.transform(utf8.decoder).join();
        expect(jsonDecode(body), []);
      } finally {
        client.close();
      }
    });

    test('GET /api/query returns matching results', () async {
      // Insert test data
      final ruleId = await ruleRepo.insert(const Rule(
        name: '测试规则',
        regexPattern: r'(\d{3})_(\w+)',
        formatString: r'$1@$2',
        createdAt: '2025-01-01T00:00:00',
        updatedAt: '2025-01-01T00:00:00',
      ));

      final matchId = await matchItemRepo.insert(MatchItem(
        ruleId: ruleId,
        matchValue: '001@TEST',
        createdAt: '2025-01-01T00:00:00',
      ));

      await fileRecordRepo.insert(FileRecord(
        matchItemId: matchId,
        fileName: '001_test.pdf',
        fullPath: 'C:/docs/001_test.pdf',
        directory: 'C:/docs',
        scannedAt: '2025-01-01T00:00:00',
      ));

      await server.start(port: 0);
      final client = HttpClient();
      try {
        final request = await client.getUrl(
          Uri.parse('http://127.0.0.1:${server.port}/api/query?match=001'),
        );
        final response = await request.close();
        expect(response.statusCode, 200);
        final body = await response.transform(utf8.decoder).join();
        final results = jsonDecode(body) as List;
        expect(results.length, 1);
        expect(results[0]['match_value'], '001@TEST');
        expect(results[0]['rule_name'], '测试规则');
        expect((results[0]['files'] as List).length, 1);
        expect(results[0]['files'][0]['full_path'], 'C:/docs/001_test.pdf');
      } finally {
        client.close();
      }
    });

    test('GET /api/rules returns rules list', () async {
      await ruleRepo.insert(const Rule(
        name: '规则A',
        regexPattern: r'\d+',
        formatString: r'$0',
        createdAt: '2025-01-01T00:00:00',
        updatedAt: '2025-01-01T00:00:00',
      ));
      await ruleRepo.insert(const Rule(
        name: '规则B',
        regexPattern: r'\w+',
        formatString: r'$0',
        createdAt: '2025-01-02T00:00:00',
        updatedAt: '2025-01-02T00:00:00',
      ));

      await server.start(port: 0);
      final client = HttpClient();
      try {
        final request = await client.getUrl(
          Uri.parse('http://127.0.0.1:${server.port}/api/rules'),
        );
        final response = await request.close();
        expect(response.statusCode, 200);
        final body = await response.transform(utf8.decoder).join();
        final rules = jsonDecode(body) as List;
        expect(rules.length, 2);
        expect(rules[0]['name'], '规则B');
        expect(rules[1]['name'], '规则A');
      } finally {
        client.close();
      }
    });
  });
}