import {createClient} from 'npm:@supabase/supabase-js@2.57.4';
import {canonicalJPEG} from './jpeg.ts';
const url = Deno.env.get('SUPABASE_URL')!;
const key = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!;
const admin = createClient(url,key,{auth:{persistSession:false,autoRefreshToken:false}});
const answer = (status: number, body: unknown) => new Response(JSON.stringify(body),{status,headers:{'Content-Type':'application/json','Cache-Control':'no-store'}});
async function boundedBody(req: Request, limit: number): Promise<Uint8Array> {
  if (Number(req.headers.get('content-length') || 0)>limit) throw new Error('size');
  const reader=req.body?.getReader(); if (!reader) throw new Error('empty');
  const parts: Uint8Array[]=[];let total=0;
  try { while (true) { const {value,done}=await reader.read();if(done)break;
    total+=value.length;if(total>limit){await reader.cancel();throw new Error('size');} parts.push(value);
  }} finally {reader.releaseLock();}
  const out=new Uint8Array(total);let offset=0;for(const part of parts){out.set(part,offset);offset+=part.length;}return out;
}
Deno.serve(async req => {
  // Native app uses user JWT. Explicit validation also supports deployments with verify_jwt=false.
  const authorization=req.headers.get('authorization') || '';
  if(!authorization.startsWith('Bearer '))return answer(401,{error:'auth'});
  const {data:auth,error:authError}=await admin.auth.getUser(authorization.slice(7));
  if(authError || !auth.user)return answer(401,{error:'auth'});
  const actor=auth.user.id;
  try {
    if(req.method==='POST') {
      const input=JSON.parse(new TextDecoder().decode(await boundedBody(req,2048)));
      if(typeof input.user_id!=='string' || !/^[0-9a-f-]{36}$/.test(input.user_id))return answer(400,{error:'id'});
      // Read profile AS USER first; never use admin to bypass profile visibility.
      const client=createClient(url,Deno.env.get('SUPABASE_ANON_KEY')!,{global:{headers:{Authorization:authorization}},auth:{persistSession:false}});
      const {data:profile,error}=await client.from('profiles').select('avatar_path').eq('user_id',input.user_id).maybeSingle();
      if(error || !profile)return answer(404,{error:'profile'});
      if(!profile.avatar_path)return answer(200,{url:null});
      const {data,error:signError}=await admin.storage.from('avatars').createSignedUrl(profile.avatar_path,60);
      if(signError)throw signError;
      return answer(200,{url:data.signedUrl});
    }
    if(req.method!=='PUT' && req.method!=='DELETE')return answer(405,{error:'method'});
    const {data:allowed,error:limitError}=await admin.rpc('anivibe_avatar_limit',{p_user:actor});
    if(limitError)throw limitError;if(!allowed)return answer(429,{error:'rate'});
    let path: string|null=null;
    if(req.method==='PUT') {
      let image: Uint8Array;
      try {image=canonicalJPEG(await boundedBody(req,1048576));} catch {return answer(400,{error:'image'});}
      path=actor+'/'+crypto.randomUUID()+'.jpg';
      const {error}=await admin.storage.from('avatars').upload(path,image,{contentType:'image/jpeg',upsert:false});if(error)throw error;
    }
    const {data:oldPath,error}=await admin.rpc('anivibe_set_avatar',{p_user:actor,p_path:path});
    if(error){if(path)await admin.storage.from('avatars').remove([path]);throw error;}
    // Atomically replaced path is safe to remove even with concurrent uploads.
    if(oldPath) { const {error:cleanupError}=await admin.storage.from('avatars').remove([oldPath]);
      if(cleanupError)console.error('avatar cleanup failed'); }
    return answer(200,{ok:true});
  } catch {return answer(500,{error:'backend'});}
});
