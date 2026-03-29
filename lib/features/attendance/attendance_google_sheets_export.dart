import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/services.dart' show PlatformException;
import 'package:google_sign_in/google_sign_in.dart';
import 'package:googleapis/sheets/v4.dart' as sheets;
import 'package:http/http.dart' as http;

import '../../models/models.dart';

class AttendanceGoogleSheetsExporter {
  static const _scopes = <String>[
    'email',
    'profile',
    'https://www.googleapis.com/auth/spreadsheets',
  ];

  AttendanceGoogleSheetsExporter({GoogleSignIn? googleSignIn})
    : _googleSignIn = googleSignIn ?? GoogleSignIn(scopes: _scopes);

  final GoogleSignIn _googleSignIn;

  Future<Uri> export({
    required ClassSession session,
    required DateTime date,
    required List<Student> students,
    required Map<String, AttendanceStatus> statusByStudentId,
  }) async {
    final dateKey = _dateKey(date);
    final title = 'Attendance ${session.sectionName} $dateKey';

    final account = await _ensureSignedIn();
    await _ensureScopes(account);
    final headers = await _getAuthHeadersWithRetry(account);
    final client = _GoogleAuthClient(headers);

    try {
      final api = sheets.SheetsApi(client);

      final created = await api.spreadsheets.create(
        sheets.Spreadsheet(
          properties: sheets.SpreadsheetProperties(title: title),
          sheets: [
            sheets.Sheet(
              properties: sheets.SheetProperties(title: 'Attendance'),
            ),
          ],
        ),
      );

      final spreadsheetId = created.spreadsheetId;
      if (spreadsheetId == null || spreadsheetId.isEmpty) {
        throw StateError('Failed to create spreadsheet');
      }

      final sheetId =
          created.sheets?.firstOrNull?.properties?.sheetId ??
          (await api.spreadsheets.get(
            spreadsheetId,
          )).sheets?.firstOrNull?.properties?.sheetId;

      if (sheetId == null) {
        throw StateError('Failed to resolve spreadsheet sheetId');
      }

      final values = <List<Object?>>[
        ['Group', 'Student ID', 'Name in Full', 'Status'],
      ];

      for (final s in students) {
        final status = statusByStudentId[s.id] ?? AttendanceStatus.unmarked;
        values.add([
          session.sectionName,
          s.id,
          s.fullName,
          _statusLabel(status),
        ]);
      }

      await api.spreadsheets.values.update(
        sheets.ValueRange(values: values),
        spreadsheetId,
        'Attendance!A1',
        valueInputOption: 'RAW',
      );

      await api.spreadsheets.batchUpdate(
        sheets.BatchUpdateSpreadsheetRequest(
          requests: _buildFormattingRequests(
            sheetId: sheetId,
            rowCount: students.length + 1,
          ),
        ),
        spreadsheetId,
      );

      // Open the created spreadsheet.
      final url =
          (created.spreadsheetUrl != null && created.spreadsheetUrl!.isNotEmpty)
          ? created.spreadsheetUrl!
          : 'https://docs.google.com/spreadsheets/d/$spreadsheetId/edit';
      final uri = Uri.parse(url);

      // On web, the Google Sign-In client may have created the file in the
      // user's drive but opening in a new tab is still fine.
      if (kIsWeb) {
        return uri;
      }

      return uri;
    } finally {
      client.close();
    }
  }

  static List<sheets.Request> _buildFormattingRequests({
    required int sheetId,
    required int rowCount,
  }) {
    final headerGreen = sheets.Color(red: 0.70, green: 0.85, blue: 0.60);

    final black = sheets.Color(red: 0, green: 0, blue: 0);

    sheets.Border border({int width = 1}) {
      return sheets.Border(style: 'SOLID', width: width, color: black);
    }

    final fullRange = sheets.GridRange(
      sheetId: sheetId,
      startRowIndex: 0,
      endRowIndex: rowCount,
      startColumnIndex: 0,
      endColumnIndex: 4,
    );

    final headerRange = sheets.GridRange(
      sheetId: sheetId,
      startRowIndex: 0,
      endRowIndex: 1,
      startColumnIndex: 0,
      endColumnIndex: 4,
    );

    final dataRange = sheets.GridRange(
      sheetId: sheetId,
      startRowIndex: 1,
      endRowIndex: rowCount,
      startColumnIndex: 0,
      endColumnIndex: 4,
    );

    sheets.Request setColumnWidth({required int columnIndex, required int px}) {
      return sheets.Request(
        updateDimensionProperties: sheets.UpdateDimensionPropertiesRequest(
          range: sheets.DimensionRange(
            sheetId: sheetId,
            dimension: 'COLUMNS',
            startIndex: columnIndex,
            endIndex: columnIndex + 1,
          ),
          properties: sheets.DimensionProperties(pixelSize: px),
          fields: 'pixelSize',
        ),
      );
    }

    sheets.Request alignRange({
      required sheets.GridRange range,
      String? horizontal,
    }) {
      return sheets.Request(
        repeatCell: sheets.RepeatCellRequest(
          range: range,
          cell: sheets.CellData(
            userEnteredFormat: sheets.CellFormat(
              verticalAlignment: 'MIDDLE',
              horizontalAlignment: horizontal,
              wrapStrategy: 'OVERFLOW_CELL',
            ),
          ),
          fields:
              'userEnteredFormat.verticalAlignment,userEnteredFormat.horizontalAlignment,userEnteredFormat.wrapStrategy',
        ),
      );
    }

    final groupIdStatusColumns = sheets.GridRange(
      sheetId: sheetId,
      startRowIndex: 1,
      endRowIndex: rowCount,
      startColumnIndex: 0,
      endColumnIndex: 2,
    );

    final statusColumn = sheets.GridRange(
      sheetId: sheetId,
      startRowIndex: 1,
      endRowIndex: rowCount,
      startColumnIndex: 3,
      endColumnIndex: 4,
    );

    final nameColumn = sheets.GridRange(
      sheetId: sheetId,
      startRowIndex: 1,
      endRowIndex: rowCount,
      startColumnIndex: 2,
      endColumnIndex: 3,
    );

    return [
      sheets.Request(
        updateSheetProperties: sheets.UpdateSheetPropertiesRequest(
          properties: sheets.SheetProperties(
            sheetId: sheetId,
            gridProperties: sheets.GridProperties(frozenRowCount: 1),
          ),
          fields: 'gridProperties.frozenRowCount',
        ),
      ),

      // Header row styling.
      sheets.Request(
        repeatCell: sheets.RepeatCellRequest(
          range: headerRange,
          cell: sheets.CellData(
            userEnteredFormat: sheets.CellFormat(
              backgroundColor: headerGreen,
              textFormat: sheets.TextFormat(bold: true),
              horizontalAlignment: 'CENTER',
              verticalAlignment: 'MIDDLE',
              wrapStrategy: 'OVERFLOW_CELL',
            ),
          ),
          fields:
              'userEnteredFormat(backgroundColor,textFormat,horizontalAlignment,verticalAlignment,wrapStrategy)',
        ),
      ),

      // Borders for all table cells.
      sheets.Request(
        updateBorders: sheets.UpdateBordersRequest(
          range: fullRange,
          top: border(width: 2),
          bottom: border(width: 2),
          left: border(width: 2),
          right: border(width: 2),
          innerHorizontal: border(width: 1),
          innerVertical: border(width: 1),
        ),
      ),

      // Data alignment: center for Group/Student ID/Status, left for Name.
      alignRange(range: dataRange, horizontal: null),
      alignRange(range: groupIdStatusColumns, horizontal: 'CENTER'),
      alignRange(range: statusColumn, horizontal: 'CENTER'),
      alignRange(range: nameColumn, horizontal: 'LEFT'),

      // Column widths tuned for readability.
      setColumnWidth(columnIndex: 0, px: 110),
      setColumnWidth(columnIndex: 1, px: 130),
      setColumnWidth(columnIndex: 2, px: 320),
      setColumnWidth(columnIndex: 3, px: 110),
    ];
  }

  Future<GoogleSignInAccount> _ensureSignedIn() async {
    GoogleSignInAccount? account = _googleSignIn.currentUser;
    account ??= await _googleSignIn.signInSilently(suppressErrors: true);
    account ??= await _googleSignIn.signIn();

    if (account == null) {
      throw StateError('Google sign-in aborted');
    }
    return account;
  }

  Future<void> _ensureScopes(GoogleSignInAccount account) async {
    try {
      final granted = await _googleSignIn.requestScopes(_scopes);
      if (!granted) {
        throw StateError('Google permissions not granted');
      }
    } on PlatformException catch (e) {
      if (e.code != 'sign_in_required') rethrow;
      // The plugin sometimes reports sign-in required for scope requests.
      await _googleSignIn.signOut();
      final refreshed = await _googleSignIn.signIn();
      if (refreshed == null) {
        throw StateError('Google sign-in aborted');
      }

      final granted = await _googleSignIn.requestScopes(_scopes);
      if (!granted) {
        throw StateError('Google permissions not granted');
      }
    }
  }

  Future<Map<String, String>> _getAuthHeadersWithRetry(
    GoogleSignInAccount account,
  ) async {
    try {
      return await account.authHeaders;
    } on PlatformException catch (e) {
      if (e.code != 'sign_in_required') rethrow;
      // Force interactive sign-in and then retry.
      await _googleSignIn.signOut();
      final refreshed = await _googleSignIn.signIn();
      if (refreshed == null) {
        throw StateError('Google sign-in aborted');
      }
      await _ensureScopes(refreshed);
      return await refreshed.authHeaders;
    }
  }

  static String _statusLabel(AttendanceStatus s) {
    return switch (s) {
      AttendanceStatus.present => 'Present',
      AttendanceStatus.late => 'Late',
      AttendanceStatus.unmarked => 'Absent',
    };
  }

  static String _dateKey(DateTime dt) {
    String two(int v) => v.toString().padLeft(2, '0');
    return '${dt.year}-${two(dt.month)}-${two(dt.day)}';
  }
}

extension _FirstOrNullExt<T> on List<T> {
  T? get firstOrNull => isEmpty ? null : first;
}

class _GoogleAuthClient extends http.BaseClient {
  _GoogleAuthClient(this._headers);

  final Map<String, String> _headers;
  final http.Client _inner = http.Client();

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    request.headers.addAll(_headers);
    return _inner.send(request);
  }

  @override
  void close() {
    _inner.close();
    super.close();
  }
}
