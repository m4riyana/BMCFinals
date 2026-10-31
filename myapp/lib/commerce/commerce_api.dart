import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:http/http.dart' as http;
import '../services/payment_service.dart';

class CommerceException implements Exception {
  final String message;
  final int? statusCode;
  const CommerceException(this.message, [this.statusCode]);
  @override
  String toString() => message;
}

/// All mutations use Supabase bearer tokens, never ambient cookie credentials.
class CommerceApi {
  final http.Client _client;
  final String baseUrl;
  CommerceApi({http.Client? client, this.baseUrl = PaymentService.backendUrl})
      : _client = client ?? http.Client();
  String? get currentUid => Supabase.instance.client.auth.currentUser?.id;
  String? get currentEmail => Supabase.instance.client.auth.currentUser?.email;
  Stream<String?> get authChanges =>
      Supabase.instance.client.auth.onAuthStateChange.map((e) => e.session?.user.id);
  Future<Map<String, String>> _headers(bool authenticated) async {
    final headers = <String, String>{
      'Content-Type': 'application/json',
      'Accept': 'application/json'
    };
    if (authenticated) {
      final user = Supabase.instance.client.auth.currentUser;
      if (user == null)
        throw const CommerceException('Please sign in to continue.', 401);
      final token = Supabase.instance.client.auth.currentSession?.accessToken;
      if (token == null) throw const CommerceException('Please sign in again.', 401);
      headers['Authorization'] = 'Bearer $token';
    }
    return headers;
  }

  Uri _uri(String path) =>
      Uri.parse('${baseUrl.replaceAll(RegExp(r'/$'), '')}$path');
  Future<Map<String, dynamic>> request(String method, String path,
      {Object? body, bool authenticated = true}) async {
    try {
      final request = http.Request(method, _uri(path))
        ..headers.addAll(await _headers(authenticated));
      if (body != null) request.body = jsonEncode(body);
      final streamed =
          await _client.send(request).timeout(const Duration(seconds: 20));
      final response = await http.Response.fromStream(streamed)
          .timeout(const Duration(seconds: 20));
      Map<String, dynamic> data;
      try {
        data = Map<String, dynamic>.from(jsonDecode(response.body) as Map);
      } catch (_) {
        throw const CommerceException(
            'The store returned an unexpected response. Please try again.');
      }
      if (response.statusCode < 200 || response.statusCode >= 300)
        throw CommerceException(
            '${data['error'] ?? 'This request could not be completed.'}',
            response.statusCode);
      return data;
    } on CommerceException {
      rethrow;
    } on TimeoutException {
      throw const CommerceException(
          'The store took too long to respond. Please try again.');
    } catch (_) {
      throw const CommerceException(
          'Unable to reach the store. Please check your connection and try again.');
    }
  }

  Future<Map<String, dynamic>> catalog() =>
      request('GET', '/api/catalog', authenticated: false);
  Future<Map<String, dynamic>> me() => request('GET', '/api/me');
  Future<Map<String, dynamic>> loginWithUsername(
          String username, String password) =>
      request('POST', '/api/auth/username-login',
          body: {'username': username, 'password': password},
          authenticated: false);
  Future<Map<String, dynamic>> profile() => request('GET', '/api/me/profile');
  Future<Map<String, dynamic>> saveProfile({
    required String username,
    required String name,
    required String contactEmail,
    required String phoneNumber,
    required String address,
  }) =>
      request('PUT', '/api/me/profile', body: {
        'username': username,
        'name': name,
        'contactEmail': contactEmail,
        'phoneNumber': phoneNumber,
        'address': address,
      });
  Future<Map<String, dynamic>> deleteProfilePhoto() =>
      request('DELETE', '/api/me/profile/photo');
  Future<Map<String, dynamic>> uploadProfilePhoto(
      Uint8List bytes, String filename) async {
    if (bytes.length > 5 * 1024 * 1024) {
      throw const CommerceException('Choose an image smaller than 5 MB.');
    }
    try {
      final request =
          http.MultipartRequest('POST', _uri('/api/me/profile/photo'));
      final headers = await _headers(true);
      headers.remove('Content-Type');
      request.headers.addAll(headers);
      request.files.add(
          http.MultipartFile.fromBytes('image', bytes, filename: filename));
      final response = await http.Response.fromStream(
          await _client.send(request).timeout(const Duration(seconds: 40)));
      final data = Map<String, dynamic>.from(jsonDecode(response.body) as Map);
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw CommerceException(
            '${data['error'] ?? 'Profile picture upload failed.'}',
            response.statusCode);
      }
      return data;
    } on CommerceException {
      rethrow;
    } catch (_) {
      throw const CommerceException(
          'Profile picture upload failed. Please try again.');
    }
  }

  Future<Map<String, dynamic>> cart() => request('GET', '/api/me/cart');
  Future<Map<String, dynamic>> saveCart(List<Map<String, dynamic>> items) =>
      request('PUT', '/api/me/cart', body: {'items': items});
  Future<Map<String, dynamic>> wishlist() => request('GET', '/api/me/wishlist');
  Future<Map<String, dynamic>> saveWishlist(List<String> productIds) =>
      request('PUT', '/api/me/wishlist', body: {'productIds': productIds});
  Future<Map<String, dynamic>> orders() => request('GET', '/api/me/orders');
  Future<Map<String, dynamic>> createOrder(Map<String, dynamic> body) =>
      request('POST', '/api/orders', body: body);
  Future<Map<String, dynamic>> order(String orderId) =>
      request('GET', '/api/me/orders/${Uri.encodeComponent(orderId)}');
  Future<Map<String, dynamic>> cancelOrder(String orderId) =>
      request('POST', '/api/me/orders/${Uri.encodeComponent(orderId)}/cancel',
          body: const {});
  Future<String> uploadImage(Uint8List bytes, String filename) async {
    if (bytes.length > 5 * 1024 * 1024)
      throw const CommerceException('Choose an image smaller than 5 MB.');
    try {
      final request = http.MultipartRequest('POST', _uri('/api/admin/images'));
      final headers = await _headers(true);
      headers.remove('Content-Type');
      request.headers.addAll(headers);
      request.files.add(
          http.MultipartFile.fromBytes('image', bytes, filename: filename));
      final response = await http.Response.fromStream(
          await _client.send(request).timeout(const Duration(seconds: 40)));
      final data = Map<String, dynamic>.from(jsonDecode(response.body) as Map);
      if (response.statusCode < 200 || response.statusCode >= 300)
        throw CommerceException(
            '${data['error'] ?? 'Image upload failed.'}', response.statusCode);
      return data['imagePath'] as String;
    } on CommerceException {
      rethrow;
    } catch (_) {
      throw const CommerceException('Image upload failed. Please try again.');
    }
  }

  String imageUrl(String path) => path.startsWith('/')
      ? '${baseUrl.replaceAll(RegExp(r'/$'), '')}$path'
      : path;
  void dispose() => _client.close();
}
