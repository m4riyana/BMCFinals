import {strict as assert} from 'node:assert';
import {createApp} from '../app.js';
import {CommerceService,imagePath} from '../lib/commerce.js';
import {MemoryRepository} from '../lib/repository.js';
import {ImageStorage} from '../storage.js';

Deno.test('gateway paths, auth and Storage-backed profile lifecycle',async()=>{
 const repository=new MemoryRepository();
 const removed=[];
 const photo='/uploads/profiles/aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa.png';
 const storage={upload:async()=>photo,remove:async p=>removed.push(p),publicUrl:()=> 'https://example.com/image.png'};
 const app=createApp({repository,commerce:new CommerceService(repository),storage,supabaseAuth:{verifyIdToken:async token=>{
  if(token!=='valid') throw new Error('invalid');
  return {uid:'test-user',email:'test@example.com',email_verified:true};
 }}});
 const server=app.listen(0);
 await new Promise(resolve=>server.once('listening',resolve));
 const base=`http://127.0.0.1:${server.address().port}/functions/v1/commerce`;
 const request=async(path,options={})=>{const r=await fetch(base+path,options);return {status:r.status,body:await r.json()};};
 try {
  assert.equal((await request('/api/catalog')).status,200);
  assert.equal((await request('/api/me/profile')).status,401);
  assert.equal((await request('/api/admin/products',{headers:{authorization:'Bearer valid'}})).status,403);
  const saved=await request('/api/me/profile',{method:'PUT',headers:{authorization:'Bearer valid','content-type':'application/json'},body:JSON.stringify({username:'TestUser',name:'Test User',contactEmail:'test@example.com',phoneNumber:'',address:''})});
  assert.equal(saved.status,200);
  const form=new FormData();form.append('image',new Blob([new Uint8Array([1,2,3])]),'photo.png');
  const uploaded=await request('/api/me/profile/photo',{method:'POST',headers:{authorization:'Bearer valid'},body:form});
  assert.equal(uploaded.status,201);assert.equal(uploaded.body.profile.profilePhotoPath,photo);
  const deleted=await request('/api/me/profile/photo',{method:'DELETE',headers:{authorization:'Bearer valid'}});
  assert.equal(deleted.status,200);assert.equal(deleted.body.profile.profilePhotoPath,'');assert.ok(removed.includes(photo));
  assert.equal((await request('/api/xendit/webhook',{method:'POST',headers:{'content-type':'application/json'},body:'{}'})).status,401);
 } finally {await new Promise(resolve=>server.close(resolve));}
});

Deno.test('Storage validates images and constrains object keys',async()=>{
 const writes=[];
 const objects={upload:async(...args)=>{writes.push(args);return {error:null};},getPublicUrl:key=>({data:{publicUrl:`https://example.com/${key}`}}),remove:async()=>({error:null})};
 const storage=new ImageStorage({storage:{from:()=>objects}});
 const png=Uint8Array.from(atob('iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+aG1cAAAAASUVORK5CYII='),c=>c.charCodeAt(0));
 const path=await storage.upload('products',png);
 assert.match(path,/^\/uploads\/products\/[a-f0-9-]+\.png$/);
 assert.equal(imagePath(path),path);
 assert.equal(writes[0][2].contentType,'image/png');
 await assert.rejects(()=>storage.upload('products',new TextEncoder().encode('<svg/>')));
 await assert.rejects(()=>storage.upload('products',new Uint8Array(5*1024*1024+1)));
 assert.equal(storage.publicUrl('products','../secret'),null);
 assert.equal(storage.publicUrl('private','a.png'),null);
});
