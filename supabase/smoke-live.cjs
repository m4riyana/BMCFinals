// Creates one temporary account/profile/photo and cleans up only its own data.
const assert=require('node:assert/strict');
const crypto=require('node:crypto');
const path=require('node:path');
require('../backend/node_modules/dotenv').config({path:path.join(__dirname,'../backend/.env'),quiet:true});
const {createClient}=require('../backend/node_modules/@supabase/supabase-js');
const {SupabaseRepository}=require('../backend/lib/supabase_repository');
async function main(){
 const url=process.env.SUPABASE_URL,base=url+'/functions/v1/commerce';
 const options={auth:{persistSession:false,autoRefreshToken:false}};
 const admin=createClient(url,process.env.SUPABASE_SERVICE_ROLE_KEY,options);
 const client=createClient(url,process.env.SUPABASE_ANON_KEY,options);
 const repo=new SupabaseRepository(process.env.SUPABASE_DB_URL);
 const handle='smoke'+crypto.randomBytes(6).toString('hex');
 const email=handle+'@example.com',password=crypto.randomBytes(24).toString('base64url')+'aA1!';
 let uid,photo,token;
 async function request(route,{method='GET',body,authenticated=false,headers={}}={}){
  const r=await fetch(base+route,{method,headers:{...(authenticated?{authorization:`Bearer ${token}`} : {}),...(body && !(body instanceof FormData)?{'content-type':'application/json'}:{}),...headers},body:body instanceof FormData?body:body?JSON.stringify(body):undefined,signal:AbortSignal.timeout(60000)});
  return {status:r.status,data:await r.json()};
 }
 try {
  assert.equal((await request('/api/catalog')).status,200);
  assert.equal((await request('/api/me/profile')).status,401);
  const created=await admin.auth.admin.createUser({email,password,email_confirm:true});
  if(created.error) throw new Error('Temporary account creation failed: '+created.error.message);
  uid=created.data.user.id;
  const login=await client.auth.signInWithPassword({email,password});
  if(login.error) throw new Error('Temporary account login failed');
  token=login.data.session.access_token;
  assert.equal((await request('/api/admin/products',{authenticated:true})).status,403);
  const saved=await request('/api/me/profile',{method:'PUT',authenticated:true,body:{username:handle,name:'Temporary migration check',contactEmail:email,phoneNumber:'',address:''}});
  assert.equal(saved.status,200,'profile save');
  assert.equal((await request('/api/me/profile',{authenticated:true})).data.profile.username,handle);
  const usernameLogin=await request('/api/auth/username-login',{method:'POST',body:{username:handle,password}});
  assert.equal(usernameLogin.status,200,'username login');
  assert.equal(usernameLogin.data.email,email);
  const form=new FormData();
  form.append('image',new Blob([Buffer.from('iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+aG1cAAAAASUVORK5CYII=','base64')],{type:'image/png'}),'check.png');
  const upload=await request('/api/me/profile/photo',{method:'POST',authenticated:true,body:form});
  assert.equal(upload.status,201,'photo upload');photo=upload.data.profile.profilePhotoPath;
  const image=await fetch(base+photo,{signal:AbortSignal.timeout(30000)});
  assert.equal(image.status,200,'public storage redirect');await image.arrayBuffer();
  assert.equal((await request('/api/me/profile/photo',{method:'DELETE',authenticated:true})).status,200);
  assert.equal((await request('/api/xendit/webhook',{method:'POST',body:{}})).status,401);
  const callback=await request('/api/xendit/webhook',{method:'POST',headers:{'x-callback-token':process.env.XENDIT_CALLBACK_TOKEN},body:{event:'deployment.smoke',data:{}}});
  assert.equal(callback.status,200,'configured webhook token');
  console.log('Live checks passed: catalog, login, username login, profile save/read, Storage upload/read/delete, admin denial, webhook token validation.');
 }finally{
  if(photo) {const {error}=await admin.storage.from('ibasho-images').remove([photo.slice('/uploads/'.length)]);if(error)console.error('Temporary photo cleanup failed');}
  if(uid){
   await repo.transaction(async tx=>{tx.delete(`profiles/${uid}`);tx.delete(`usernames/${handle}`);});
   const {error}=await admin.auth.admin.deleteUser(uid);
   if(error)throw new Error('Temporary auth account cleanup failed');
   console.log('Temporary test account, profile, username and photo cleaned up.');
  }
  await repo.pool.end();
 }
}
main().catch(e=>{console.error(e.message);process.exitCode=1;});
