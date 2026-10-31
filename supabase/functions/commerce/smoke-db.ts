// Read-only connectivity check: deno run -A --env-file=backend/.env this-file
import {SupabaseRepository} from './lib/supabase_repository.js';
const repository=new SupabaseRepository(Deno.env.get('SUPABASE_DB_URL'));
try {
  const products=await repository.list('products',{active:true});
  console.log(`Edge database connection OK; ${products.length} active products.`);
} finally {await repository.pool.end();}
