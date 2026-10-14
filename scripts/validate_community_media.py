#!/usr/bin/env python3
"""Validate actual curated bytes, not filename or a client-provided MIME. No network/upload."""
import hashlib
import json
from pathlib import Path
import subprocess
from PIL import Image
ROOT = Path(__file__).resolve().parents[1]
MAX_BYTES=1048576

def inspect(path):
    data=path.read_bytes()
    if not 0 < len(data) <= MAX_BYTES: raise ValueError(f'Invalid byte size: {path.name}')
    if data.startswith(b'\x89PNG\r\n\x1a\n'):
        with Image.open(path) as im:
            if im.format!='PNG': raise ValueError('Not a PNG')
            width,height=im.size
            if not 32<=width<=1024 or not 32<=height<=512: raise ValueError('Dimensions outside budget')
            im.verify()
        return dict(mime='image/png',byte_length=len(data),width=width,height=height,duration=None,sha256=hashlib.sha256(data).hexdigest())
    if len(data)<12 or data[4:8]!=b'ftyp': raise ValueError('Only validated PNG or H.264 MP4 accepted; convert approved GIF first')
    raw=subprocess.check_output(['ffprobe','-v','error','-show_streams','-show_format','-of','json',str(path)],text=True)
    info=json.loads(raw);streams=info['streams']
    video=[s for s in streams if s['codec_type']=='video']
    if len(video)!=1 or len(streams)!=1 or video[0]['codec_name']!='h264' or video[0].get('pix_fmt')!='yuv420p': raise ValueError('One silent H.264/yuv420p video stream required')
    width,height=video[0]['width'],video[0]['height'];duration=float(info['format']['duration'])
    if not 32<=width<=1024 or not 32<=height<=512 or not .1<=duration<=8: raise ValueError('Video outside dimension/duration budget')
    return dict(mime='video/mp4',byte_length=len(data),width=width,height=height,duration=duration,sha256=hashlib.sha256(data).hexdigest())

def main():
    manifest=json.loads((ROOT/'docs/community-media-manifest.json').read_text())
    migration=(ROOT/'supabase/migrations/20261014020000_curated_cosmetics.sql').read_text()
    for item in manifest:
        suffix='mp4' if item['mime']=='video/mp4' else 'png'
        actual=inspect(ROOT/'Anivibe/Resources/CommunityMedia'/f"{item['asset_key']}.{suffix}")
        for key,value in actual.items():
            if key=='duration' and value is not None:
                assert abs(value-item[key])<=.05, (item['id'],key)
            else: assert value==item[key], (item['id'],key,value,item[key])
        poster=inspect(ROOT/'Anivibe/Resources/CommunityMedia'/f"{item['poster_key']}.png")
        assert poster['sha256']==item['poster_sha256']
        assert item['sha256'] in migration
        print(f"{item['id']}: actual MIME, bytes, dimensions, duration, codec and SHA-256 verified")
    print(f'{len(manifest)} curated items verified. No arbitrary media upload endpoint exists.')
if __name__=='__main__':main()
