import pg from 'npm:pg@8.13.3';
const {Pool} = pg;
import ca from './ca.js';
class SupabaseRepository {
  constructor(connectionString) {
    this.pool = new Pool({connectionString, ssl: {rejectUnauthorized:true, ca}, max:1, connectionTimeoutMillis:10000, idleTimeoutMillis:1000});
  }
  parse(path) {
    const i = path.indexOf('/');
    if (i < 1 || i === path.length - 1) throw new Error('Invalid document path');
    return [path.slice(0,i), path.slice(i+1)];
  }
  async get(path) {
    const [collection,id] = this.parse(path);
    const result = await this.pool.query('SELECT data FROM public.ibasho_documents WHERE collection=$1 AND id=$2',[collection,id]);
    return result.rows[0]?.data ?? null;
  }
  async set(path, value) {
    const [collection,id] = this.parse(path);
    await this.pool.query('INSERT INTO public.ibasho_documents(collection,id,data) VALUES($1,$2,$3) ON CONFLICT(collection,id) DO UPDATE SET data=EXCLUDED.data',[collection,id,value]);
  }
  async list(collection, filters={}) {
    const result = await this.pool.query('SELECT id,data FROM public.ibasho_documents WHERE collection=$1',[collection]);
    return result.rows.map(({id,data})=>({...data,id}))
      .filter(v=>(!filters.active || v.isActive === true) && (!filters.uid || v.uid===filters.uid) && (!filters.categoryId || v.categoryId===filters.categoryId))
      .sort((a,b)=>collection==='orders' ? String(b.createdAt||'').localeCompare(String(a.createdAt||'')) : 0)
      .slice(0,filters.limit||500);
  }
  async transaction(fn) {
    const client=await this.pool.connect();
    try {
      await client.query('BEGIN');
      // Global transaction lock protects checkout stock, idempotency, and username reservations.
      await client.query('SELECT pg_advisory_xact_lock(824791)');
      const staged=new Map();
      const tx={
        get:async path=>{
          if(staged.has(path)) return staged.get(path);
          const [collection,id]=this.parse(path);
          const result=await client.query('SELECT data FROM public.ibasho_documents WHERE collection=$1 AND id=$2',[collection,id]);
          return result.rows[0]?.data ?? null;
        },
        query:async (collection,filters={})=>{
          const result=await client.query('SELECT id,data FROM public.ibasho_documents WHERE collection=$1',[collection]);
          const docs=new Map(result.rows.map(v=>[v.id,v.data]));
          for(const [path,value] of staged) { const [c,id]=this.parse(path); if(c===collection) value===null?docs.delete(id):docs.set(id,value); }
          return [...docs].map(([id,data])=>({...data,id}))
            .filter(v=>(!filters.active || v.isActive===true)&&(!filters.uid || v.uid===filters.uid)&&(!filters.categoryId || v.categoryId===filters.categoryId))
            .sort((a,b)=>collection==='orders'?String(b.createdAt||'').localeCompare(String(a.createdAt||'')):0)
            .slice(0,filters.limit||500);
        },
        set:(path,value)=>staged.set(path,value),
        delete:path=>staged.set(path,null)
      };
      const result=await fn(tx);
      for(const [path,value] of staged) {
        const [collection,id]=this.parse(path);
        if(value===null) await client.query('DELETE FROM public.ibasho_documents WHERE collection=$1 AND id=$2',[collection,id]);
        else await client.query('INSERT INTO public.ibasho_documents(collection,id,data) VALUES($1,$2,$3) ON CONFLICT(collection,id) DO UPDATE SET data=EXCLUDED.data',[collection,id,value]);
      }
      await client.query('COMMIT'); return result;
    } catch(error) { await client.query('ROLLBACK'); throw error; }
    finally {client.release();}
  }
}
export {SupabaseRepository};
