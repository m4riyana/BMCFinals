import '../commerce/commerce_api.dart';
class OrdersService {
  final CommerceApi api;
  OrdersService({CommerceApi? api}): api=api??CommerceApi();
  Future<Map<String,dynamic>> getOrders() => api.orders();
  Future<Map<String,dynamic>> getOrder(String id) => api.order(id);
  Future<Map<String,dynamic>> createOrder(Map<String,dynamic> details) => api.createOrder(details);
  Future<Map<String,dynamic>> cancelOrder(String id) => api.cancelOrder(id);
}
