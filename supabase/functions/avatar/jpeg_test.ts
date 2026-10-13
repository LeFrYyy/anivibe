import jpeg from 'npm:jpeg-js@0.4.4';
import {canonicalJPEG,dimensions} from './jpeg.ts';
function assert(x: boolean) {if(!x)throw new Error('assert');}
function rejects(bytes: Uint8Array){let rejected=false;try{canonicalJPEG(bytes);}catch{rejected=true;}assert(rejected);}
Deno.test('canonical JPEG strips comments, preserves pixels/dimensions',()=>{
 const data=new Uint8Array(32*32*4).fill(255);
 const encoded=jpeg.encode({width:32,height:32,data,comments:['private metadata']},80).data;
 const out=canonicalJPEG(encoded);assert(dimensions(out).join(',')==='32,32');
 assert(!new TextDecoder().decode(out).includes('private metadata'));
});
Deno.test('reject PNG MIME spoof, empty, truncated, excessive bytes',()=>{
 for(const bytes of [new Uint8Array(),new Uint8Array([137,80,78,71]),new Uint8Array([255,216,255]),new Uint8Array(1048577)])rejects(bytes);
});
Deno.test('reject oversized SOF before decoder',()=>{
 const bytes=jpeg.encode({width:4,height:4,data:new Uint8Array(64)},80).data;
 const copy=new Uint8Array(bytes);
 for(let i=0;i<copy.length-8;i++){if(copy[i]===255&&copy[i+1]===192){copy[i+5]=255;copy[i+6]=255;break;}}
 rejects(copy);
});
Deno.test('accepted output is a valid independent JPEG',()=>{
 const input=jpeg.encode({width:16,height:8,data:new Uint8Array(512)},80).data;
 const image=jpeg.decode(canonicalJPEG(input));assert(image.width===16 && image.height===8);
});
