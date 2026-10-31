import 'dart:convert';
import 'dart:math';

import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../config/supabase_config.dart';

class PaymentResult {
  final String referenceId;
  final String paymentUrl;
  PaymentResult(this.referenceId, this.paymentUrl);
}

class PaymentService {
  static const String backendUrl = String.fromEnvironment(
    'BACKEND_URL',
    defaultValue: '${SupabaseConfig.url}/functions/v1/commerce',
  );

  Future<PaymentResult> createPayment({
    required String customerName,
    required String contactNumber,
    required String address,
    required List<Map<String, dynamic>> items,
  }) async {
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) throw Exception('Please log in first.');
    final token = Supabase.instance.client.auth.currentSession?.accessToken;
    if (token == null) throw Exception('Please sign in again.');
    final random = Random.secure();
    final idempotencyKey =
        'payment-${DateTime.now().microsecondsSinceEpoch}-${List.generate(8, (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0')).join()}';
    final response = await http.post(
      Uri.parse('$backendUrl/api/orders'),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $token',
      },
      body: jsonEncode({
        'customerName': customerName,
        'contactNumber': contactNumber,
        'address': address,
        'items': items,
        'paymentMethod': 'xendit',
        'idempotencyKey': idempotencyKey,
      }),
    );
    final data = jsonDecode(response.body) as Map<String, dynamic>;
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception(data['error'] ?? 'Payment request failed');
    }
    final order = Map<String, dynamic>.from(data['order'] as Map);
    final url = (data['paymentUrl'] ?? order['paymentUrl']) as String?;
    if (url == null || url.isEmpty) throw Exception('No payment URL returned.');
    return PaymentResult(order['reference'] as String, url);
  }

  Future<void> openPayment(String url) async {
    final uri = Uri.parse(url);
    if (uri.scheme != 'https' ||
        !const {'checkout-staging.xendit.co', 'dev.xen.to', 'xen.to'}
            .contains(uri.host)) {
      throw Exception('Invalid Xendit Test Mode payment URL.');
    }
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      throw Exception('Could not open Xendit checkout.');
    }
  }
}
