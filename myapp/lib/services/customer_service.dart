import '../commerce/commerce_api.dart';
class CustomerService {
  final CommerceApi api;
  CustomerService({CommerceApi? api}):api=api??CommerceApi();
  Future<Map<String,dynamic>> getProfile()=>api.profile();
  Future<Map<String,dynamic>> saveProfile({required String username,required String name,required String contactEmail,required String phoneNumber,required String address}) => api.saveProfile(username:username,name:name,contactEmail:contactEmail,phoneNumber:phoneNumber,address:address);
}
