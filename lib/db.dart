import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';

String hash(String p) => sha256.convert(utf8.encode(p)).toString();

class DB {
  static Database? _d;
  static Future<Database> get db async => _d ??= await openDatabase(
        join(await getDatabasesPath(), 'families.db'),
        version: 1,
        onCreate: (d, v) async {
          await d.execute('''CREATE TABLE families(id INTEGER PRIMARY KEY AUTOINCREMENT,
            governorate TEXT, district TEXT, lat REAL, lng REAL, name TEXT, phone TEXT,
            national_id TEXT, voter_id TEXT, employed INTEGER, job_type TEXT, education TEXT,
            request_type TEXT, notes TEXT, created_at TEXT)''');
          await d.execute('''CREATE TABLE members(id INTEGER PRIMARY KEY AUTOINCREMENT,
            family_id INTEGER, name TEXT, relation TEXT, age INTEGER, education TEXT, details TEXT)''');
          await d.execute('CREATE TABLE users(id INTEGER PRIMARY KEY AUTOINCREMENT, username TEXT UNIQUE, password TEXT, role TEXT)');
          await d.insert('users', {'username': 'admin', 'password': hash('admin123'), 'role': 'مدير'});
        },
      );

  static Future<bool> login(String u, String p) async =>
      (await (await db).query('users', where: 'username=? AND password=?', whereArgs: [u, hash(p)])).isNotEmpty;

  static Future<List<Map<String, dynamic>>> search(String q) async {
    final d = await db;
    if (q.trim().isEmpty) return d.query('families', orderBy: 'id DESC');
    final l = '%${q.trim()}%';
    return d.query('families',
        where: 'name LIKE ? OR national_id LIKE ? OR voter_id LIKE ? OR phone LIKE ?',
        whereArgs: [l, l, l, l], orderBy: 'id DESC');
  }

  static Future<Map<String, int>> stats() async {
    final d = await db;
    Future<int> c(String sql) async => Sqflite.firstIntValue(await d.rawQuery(sql)) ?? 0;
    return {
      'families': await c('SELECT COUNT(*) FROM families'),
      'people': await c('SELECT COUNT(*) FROM families') + await c('SELECT COUNT(*) FROM members'),
      'requests': await c("SELECT COUNT(*) FROM families WHERE request_type!='خدمة عامة'"),
      'services': await c("SELECT COUNT(*) FROM families WHERE request_type='خدمة عامة'"),
    };
  }

  static Future<void> saveFamily(Map<String, dynamic> f, List<Map<String, dynamic>> ms) async {
    final d = await db;
    await d.transaction((t) async {
      final id = await t.insert('families', {...f, 'created_at': DateTime.now().toIso8601String()});
      for (final m in ms) {
        await t.insert('members', {...m, 'family_id': id});
      }
    });
  }

  static Future<List<Map<String, dynamic>>> members(int fid) async =>
      (await db).query('members', where: 'family_id=?', whereArgs: [fid]);

  static Future<void> deleteFamily(int id) async {
    final d = await db;
    await d.delete('members', where: 'family_id=?', whereArgs: [id]);
    await d.delete('families', where: 'id=?', whereArgs: [id]);
  }

  static Future<List<Map<String, dynamic>>> groupCount(String col) async =>
      (await db).rawQuery('SELECT $col AS k, COUNT(*) AS n FROM families GROUP BY $col ORDER BY n DESC');

  static Future<List<Map<String, dynamic>>> users() async => (await db).query('users');
  static Future<void> addUser(String u, String p, String role) async =>
      (await db).insert('users', {'username': u, 'password': hash(p), 'role': role});
  static Future<void> delUser(int id) async =>
      (await db).delete('users', where: 'id=? AND username!=?', whereArgs: [id, 'admin']);

  // ---- Backup / Restore (JSON) ----
  static Future<String> exportJson() async {
    final d = await db;
    return jsonEncode({
      'app': 'families_app',
      'version': 1,
      'exported_at': DateTime.now().toIso8601String(),
      'families': await d.query('families'),
      'members': await d.query('members'),
    });
  }

  static Future<void> restoreJson(String s) async {
    final j = jsonDecode(s) as Map<String, dynamic>;
    if (j['app'] != 'families_app') throw 'ملف غير صالح';
    final d = await db;
    await d.transaction((t) async {
      await t.delete('members');
      await t.delete('families');
      for (final f in j['families']) {
        await t.insert('families', Map<String, dynamic>.from(f));
      }
      for (final m in j['members']) {
        await t.insert('members', Map<String, dynamic>.from(m));
      }
    });
  }
}
