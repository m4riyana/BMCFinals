// Run: node supabase/deploy-commerce.cjs (after npx.cmd supabase login).
// Secrets are read locally, never logged or committed.
const fs=require('node:fs');
const os=require('node:os');
const path=require('node:path');
const {spawnSync}=require('node:child_process');
const root=path.resolve(__dirname,'..');
require('../backend/node_modules/dotenv').config({path:path.join(root,'backend','.env'),quiet:true});
const {createClient}=require('../backend/node_modules/@supabase/supabase-js');
function cli(args) {
  // Arguments are fixed commands or generated paths, never secret values.
  const result=spawnSync(process.platform==='win32'?'npx.cmd':'npx',['--yes','supabase',...args],{cwd:root,stdio:'inherit',shell:process.platform==='win32'});
  if(result.status!==0) throw new Error('Supabase CLI command failed. Complete supabase login and retry.');
}
async function main() {
 const projectUrl=new URL(process.env.SUPABASE_URL);
 const ref=projectUrl.hostname.split('.')[0];
 if(!/^[a-z]{20}$/.test(ref) || projectUrl.hostname!==`${ref}.supabase.co`) throw new Error('Invalid Supabase project URL');
 // Check account access before creating resources or uploading secrets.
 cli(['functions','list','--project-ref',ref]);
 const secrets={COMMERCE_DB_URL:process.env.SUPABASE_DB_URL,ADMIN_EMAILS:process.env.ADMIN_EMAILS||'',XENDIT_SECRET_KEY:process.env.XENDIT_SECRET_KEY,XENDIT_CALLBACK_TOKEN:process.env.XENDIT_CALLBACK_TOKEN};
 if(process.env.XENDIT_RETURN_URL) secrets.XENDIT_RETURN_URL=process.env.XENDIT_RETURN_URL;
 if(!secrets.COMMERCE_DB_URL || !secrets.XENDIT_SECRET_KEY?.startsWith('xnd_development_') || !secrets.XENDIT_CALLBACK_TOKEN) throw new Error('Configure database credentials and Xendit Test Mode secrets in backend/.env first.');
 const dir=fs.mkdtempSync(path.join(os.tmpdir(),'ibasho-edge-'));
 const envFile=path.join(dir,'function.env');
 try {
  fs.writeFileSync(envFile,Object.entries(secrets).map(([k,v])=>`${k}=${JSON.stringify(v)}`).join('\n'),{mode:0o600});
  cli(['secrets','set','--project-ref',ref,'--env-file',`"${envFile}"`]);
  if(!process.env.XENDIT_RETURN_URL) cli(['secrets','unset','--project-ref',ref,'XENDIT_RETURN_URL']);
 } finally { fs.rmSync(envFile,{force:true}); fs.rmdirSync(dir); }
 const admin=createClient(projectUrl.origin,process.env.SUPABASE_SERVICE_ROLE_KEY,{auth:{persistSession:false,autoRefreshToken:false}});
 const {data:buckets,error:listError}=await admin.storage.listBuckets();
 if(listError) throw new Error('Unable to inspect Supabase Storage');
 const options={public:true,fileSizeLimit:5*1024*1024,allowedMimeTypes:['image/jpeg','image/png','image/webp']};
 const result=buckets.some(b=>b.id==='ibasho-images')
   ? await admin.storage.updateBucket('ibasho-images',options)
   : await admin.storage.createBucket('ibasho-images',options);
 if(result.error) throw new Error('Unable to configure image storage');
 // Preserve legacy paths by copying existing local images with the same keys.
 for(const kind of ['products','profiles']) {
  const folder=path.join(root,'backend','uploads',kind);
  if(!fs.existsSync(folder)) continue;
  for(const name of fs.readdirSync(folder)) {
   if(!/^[a-f0-9-]+\.webp$/.test(name)) continue;
   const {error}=await admin.storage.from('ibasho-images').upload(`${kind}/${name}`,fs.readFileSync(path.join(folder,name)),{contentType:'image/webp',upsert:true,cacheControl:'31536000'});
   if(error) throw new Error('Legacy image migration failed');
  }
 }
 cli(['functions','deploy','commerce','--project-ref',ref,'--use-api']);
 const base=`${projectUrl.origin}/functions/v1/commerce`;
 const response=await fetch(`${base}/api/catalog`,{signal:AbortSignal.timeout(60000)});
 const data=await response.json();
 if(!response.ok || !Array.isArray(data.products)) throw new Error('Deployed catalog health check failed');
 console.log(`Deployed and verified: ${base}`);
 console.log(`Xendit Test Mode webhook: ${base}/api/xendit/webhook`);
}
main().catch(error=>{console.error(error.message);process.exitCode=1;});
