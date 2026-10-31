import 'package:supabase_flutter/supabase_flutter.dart';
class ProductService {
  final SupabaseClient _db = Supabase.instance.client;
  Future<List<Map<String,dynamic>>> getProducts() async {
    final rows = await _db.from('ibasho_documents').select('id,data').eq('collection','products');
    return rows.map((row) => <String,dynamic>{...Map<String,dynamic>.from(row['data'] as Map), 'id':row['id']}).where((p)=>p['isActive']==true).toList();
  }
}
