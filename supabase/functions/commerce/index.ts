import {createClient} from 'npm:@supabase/supabase-js@2.99.1';
import {createApp} from './app.js';
import {CommerceService} from './lib/commerce.js';
import {SupabaseRepository} from './lib/supabase_repository.js';
import {createSupabaseAuth} from './lib/supabase_auth.js';
import {XenditGateway} from './lib/xendit.js';
import {ImageStorage} from './storage.js';
import seed from './seed.json' with {type:'json'};

function required(name:string):string {
  const value=Deno.env.get(name);
  if(!value) throw new Error(`Missing function secret: ${name}`);
  return value;
}
const url=required('SUPABASE_URL');
const serviceKey=required('SUPABASE_SERVICE_ROLE_KEY');
const client=createClient(url,serviceKey,{auth:{persistSession:false,autoRefreshToken:false}});
const repository=new SupabaseRepository(required('COMMERCE_DB_URL'));
const secretKey=Deno.env.get('XENDIT_SECRET_KEY');
const returnUrl=Deno.env.get('XENDIT_RETURN_URL');
const app=createApp({
  repository,
  commerce:new CommerceService(repository,{shipping:seed.shipping}),
  supabaseAuth:createSupabaseAuth(url,required('SUPABASE_ANON_KEY'),serviceKey),
  storage:new ImageStorage(client),
  xendit:secretKey ? new XenditGateway({secretKey,callbackToken:required('XENDIT_CALLBACK_TOKEN'),returnUrl}) : null,
  adminEmails:(Deno.env.get('ADMIN_EMAILS') || '').split(',').filter(Boolean),
});
app.listen(8000);
