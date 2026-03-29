import 'package:flutter/material.dart';

enum LegalDoc { terms, privacy }

class LegalScreen extends StatelessWidget {
  const LegalScreen({super.key, required this.doc});

  final LegalDoc doc;

  static Route<void> route(LegalDoc doc) {
    return MaterialPageRoute<void>(builder: (_) => LegalScreen(doc: doc));
  }

  @override
  Widget build(BuildContext context) {
    // Palette (must match auth palette; avoid theme accent colors).
    const cBg = Color(0xFFF9FAFB);
    const cCardBg = Color(0xFFFFFFFF);
    const cTextPrimary = Color(0xFF1F2937);
    const cTextSecondary = Color(0xFF6B7280);
    const cBorder = Color(0xFFD1D5DB);
    const cLink = Color(0xFF0369A1);

    final title = doc == LegalDoc.terms ? 'Terms of Service' : 'Privacy Policy';

    final body = doc == LegalDoc.terms ? _termsText : _privacyText;

    return Scaffold(
      backgroundColor: cBg,
      appBar: AppBar(
        backgroundColor: cCardBg,
        foregroundColor: cTextPrimary,
        elevation: 0,
        centerTitle: true,
        title: Text(
          title,
          style: const TextStyle(
            color: cTextPrimary,
            fontWeight: FontWeight.w800,
          ),
        ),
        bottom: const PreferredSize(
          preferredSize: Size.fromHeight(1),
          child: Divider(height: 1, thickness: 1, color: cBorder),
        ),
        iconTheme: const IconThemeData(color: cTextPrimary),
      ),
      body: SafeArea(
        child: Theme(
          data: Theme.of(context).copyWith(
            textSelectionTheme: const TextSelectionThemeData(
              cursorColor: cLink,
              selectionHandleColor: cLink,
            ),
          ),
          child: SelectionArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Text(
                body,
                style: const TextStyle(
                  color: cTextSecondary,
                  height: 1.45,
                  fontSize: 14.5,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

const String _termsText = '''
Terms of Service
Last Updated: March 27, 2026

1. General Provisions
1.1. Scope: These Terms govern your access to and use of the eClass IUT application.

1.2. Acceptance: By accessing or using the app, you agree to be bound by these Terms. If you do not agree to all of the terms, do not use the application.

1.3. Eligibility: You represent that you are a student or staff member of Inha University in Tashkent (IUT) or an authorized user.

2. User Accounts and Security
2.1. Accuracy: You agree to provide accurate and complete information during sign-in and account setup.

2.2. Responsibility: You are solely responsible for maintaining the confidentiality of your account credentials and for all activities that occur under your account.

2.3. Termination: We reserve the right to suspend or terminate your access if we suspect any unauthorized or illegal activity.

3. User Content and Data
3.1. Ownership: You retain all rights to the data you enter (e.g., student names, IDs, attendance marks).

3.2. Rights to Use: You represent that you have the necessary rights or permissions to input such data into the app.

3.3. Restrictions: You must not attempt to bypass security measures, scrape data, or access information that does not belong to you.

4. Integration with Google Services
4.1. Export Feature: The app allows you to export data to Google Sheets. By using this feature, you authorize the app to interact with your Google Drive and create/modify files on your behalf.

4.2. Third-Party Terms: Your use of Google Sheets and Firebase is also subject to Google’s Terms of Service.

5. Disclaimer of Warranties
5.1. "As Is" Basis: The application is provided on an "AS IS" and "AS AVAILABLE" basis. We do not guarantee that the service will be uninterrupted, secure, or error-free.

5.2. No Guarantee of Accuracy: While we strive for precision, we are not responsible for any clerical errors or data loss resulting from app malfunctions or user mistakes.

6. Limitation of Liability
6.1. Exclusion of Damages: To the maximum extent permitted by law, the developer shall not be liable for any indirect, incidental, or consequential damages (including loss of data or academic standing) arising out of your use of the app.

7. Changes to Terms
7.1. Updates: We may update these Terms from time to time. Continued use of the app after such changes constitutes your acceptance of the new Terms.

8. Contact Information
8.1. Support: For any legal or technical inquiries, please reach out to:
tobaskaplus@gmail.com
''';

const String _privacyText = '''
Privacy Policy
Last Updated: March 27, 2026

1. Data we may process
1.1. Account data: name, email address, and account identifier provided by your sign-in method (e.g., Google Sign-In).

1.2. Attendance/class data: groups, lessons, and attendance marks that you manually enter or import.

1.3. Technical data: basic diagnostics, device model, and OS version to improve stability (if enabled).

2. How we use data
2.1. To authenticate you and provide secure access to your account.

2.2. To store and sync your lessons/attendance across multiple devices.

2.3. To export attendance reports to Google Sheets upon your explicit request.

3. Google Sheets and Drive integration
3.1. When using the export feature, the app requests specific permission to create or update spreadsheets in your Google account.

3.2. The app only accesses files it has created. We do not read your other private documents.

3.3. All exported files are stored in your personal Google Drive; you have full control over them and can delete them at any time.

4. Data retention and deletion
4.1. We retain your data as long as your account is active.

4.2. Account Deletion: You may request to delete your account and all associated data at any time through the app settings or by contacting us via email.

4.3. Once deleted, your data cannot be recovered from our servers.

5. Third-party services
5.1. The app relies on Google Firebase for data storage and authentication.

5.2. These services may collect information as described in Google’s Privacy Policy.

6. Children's Privacy
6.1. This app is not intended for children under the age of 13. We do not knowingly collect personal information from children.

7. Contact us
7.1. If you have any questions regarding this Privacy Policy, please contact us at:
tobaskaplus@gmail.com
''';
