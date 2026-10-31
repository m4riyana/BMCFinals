'use strict';
const {createClient} = require('@supabase/supabase-js');
function createSupabaseAuth(url, anonKey, serviceRoleKey) {
  const admin=createClient(url,serviceRoleKey,{auth:{persistSession:false,autoRefreshToken:false}});
  const publicClient=()=>createClient(url,anonKey,{auth:{persistSession:false,autoRefreshToken:false}});
  return {
    async verifyIdToken(token) {
      const {data,error}=await admin.auth.getUser(token);
      if(error || !data.user) throw new Error('Invalid Supabase access token');
      return {uid:data.user.id,email:data.user.email,email_verified:!!data.user.email_confirmed_at,admin:false};
    },
    async getUser(uid) {
      const {data,error}=await admin.auth.admin.getUserById(uid);
      if(error || !data.user) throw new Error('Account not found');
      return {uid:data.user.id,email:data.user.email,disabled:false};
    },
    async loginWithPassword(email,password) {
      const {data,error}=await publicClient().auth.signInWithPassword({email,password});
      if(error || !data.session) throw new Error('Invalid credentials');
      return {accessToken:data.session.access_token,uid:data.user.id};
    }
  };
}
module.exports={createSupabaseAuth};
