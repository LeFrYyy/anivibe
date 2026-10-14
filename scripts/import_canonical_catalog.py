#!/usr/bin/env python3
"""Generate a reviewed owner-only SQL import, never auto-match source numbering or deploy."""
import argparse
import json
import uuid
from pathlib import Path

def ident(value): return str(uuid.UUID(value))
def quote(value): return "'"+str(value).replace("'","''")+"'"
def number(value,low,high):
    if isinstance(value,bool) or not isinstance(value,(int,float)) or not low<=value<=high: raise ValueError('Number outside allowed range')
    return value

def generate(doc):
    lines=['-- Operator-reviewed catalog import. Back up first; no client/service secrets.','begin;']
    seen=set()
    for anime in doc['anime']:
        aid=ident(anime['id']);anilist=number(anime['anilist_id'],1,2147483647)
        if not isinstance(anilist,int) or not 1<=len(anime['title'])<=300 or 'ЗАМЕНИТЬ' in anime['title']:raise ValueError('Anime title required')
        lines.append(f"insert into public.canonical_anime(id,anilist_id,title) values({quote(aid)},{anilist},{quote(anime['title'])}) on conflict(id) do update set title=excluded.title,anilist_id=excluded.anilist_id;")
        ordinals=set();keys=set()
        for ep in anime['episodes']:
            eid=ident(ep['id']);key=ep['catalog_key'];kind=ep['kind'];order=number(ep['sort_order'],1,100000)
            if kind not in ('episode','special','movie','part') or not key or key in keys or order in ordinals:raise ValueError('Ambiguous/duplicate episode key/order')
            keys.add(key);ordinals.add(order)
            verified=ep.get('duration_verified',False)
            if not isinstance(verified,bool):raise ValueError('duration_verified must be a boolean')
            duration=ep.get('duration')
            if duration is None and verified:raise ValueError('Verified episode needs a trusted duration')
            if duration is not None:number(duration,30,21600)
            sql_duration='null' if duration is None else str(duration)
            lines.append(f"insert into public.canonical_episodes(id,anime_id,catalog_key,label,kind,sort_order,duration,duration_verified) values({quote(eid)},{quote(aid)},{quote(key)},{quote(ep['label'])},{quote(kind)},{order},{sql_duration},{str(verified).lower()}) on conflict(id) do update set label=excluded.label,duration=excluded.duration,duration_verified=excluded.duration_verified;")
            for source in ep['sources']:
                mid=ident(source['id']);provider=source['provider_id'];identity=source['source_identity'];voice=source.get('voice','')
                canonical_key=(provider,identity,voice)
                if canonical_key in seen:raise ValueError('One source identity/voice cannot map to two canonical episodes')
                seen.add(canonical_key)
                raw=source['source_episode']
                if set(raw)-{'providerID','titleID','season','number','title','payload'} or not {'providerID','titleID','number','payload'}<=set(raw):raise ValueError('Use the exact ProviderEpisode JSON contract')
                wire_provider=raw['providerID'].get('rawValue') if isinstance(raw['providerID'],dict) else raw['providerID']
                if wire_provider!=provider or provider not in ('kodik','anilibria','manifest'):raise ValueError('Invalid/test/unknown provider; add an explicitly reviewed provider before importing')
                number(raw['number'],1,100000)
                if not isinstance(raw['payload'],str) or len(raw['payload'])>100000 or not isinstance(raw['titleID'],str) or 'ЗАМЕНИТЬ' in raw['payload'] or 'ЗАМЕНИТЬ' in identity:raise ValueError('Invalid provider payload')
                offset=number(source.get('source_offset',0),-300,300)
                sd=source.get('source_duration');sv=source.get('verified',False)
                if not isinstance(sv,bool):raise ValueError('verified must be a boolean')
                if sd is None and sv:raise ValueError('Verified source needs a measured duration')
                if sd is not None:number(sd,30,22000)
                if sv and duration is not None and sd+3<duration+offset:raise ValueError('Source cannot cover the canonical timeline')
                sql_sd='null' if sd is None else str(sd)
                payload=quote(json.dumps(raw,ensure_ascii=False,separators=(',',':')))+'::jsonb'
                lines.append(f"insert into public.episode_source_mappings(id,episode_id,provider_id,source_identity,voice,source_episode,source_offset,source_duration,verified) values({quote(mid)},{quote(eid)},{quote(provider)},{quote(identity)},{quote(voice)},{payload},{offset},{sql_sd},{str(sv).lower()}) on conflict(id) do update set source_episode=excluded.source_episode,source_duration=excluded.source_duration,verified=excluded.verified;")
    lines+=['commit;'];return '\n'.join(lines)+'\n'

def main():
    cli=argparse.ArgumentParser(description=__doc__);cli.add_argument('input',type=Path);cli.add_argument('output',type=Path)
    args=cli.parse_args();doc=json.loads(args.input.read_text());sql=generate(doc);args.output.write_text(sql)
    print('SQL written. Review every identity and measured duration before applying as database owner.')
if __name__=='__main__':main()
