#!/usr/bin/env python3
"""Render original EO MIDI tracks for Android and retain every map's music header.

Uses the installed libfluidsynth fast file renderer and an explicit GM SoundFont.
Reference: https://www.fluidsynth.org/api/FileRenderer.html
Source MIDI, SoundFont and generated audio stay in ignored local content.
"""
import argparse
import ctypes as C
import ctypes.util
import hashlib
import json
from pathlib import Path
import subprocess
import tempfile
import wave
import zipfile
from import_eo import decode_number, write_json


def render_midi(midi, wav, soundfont):
    lib=C.CDLL(ctypes.util.find_library('fluidsynth'))
    def function(name, result, *args):
        f=getattr(lib,name);f.restype=result;f.argtypes=list(args);return f
    ptr=C.c_void_p;integer=C.c_int;string=C.c_char_p
    settings=function('new_fluid_settings',ptr)()
    synth=player=renderer=None
    try:
        setstr=function('fluid_settings_setstr',integer,ptr,string,string)
        setnum=function('fluid_settings_setnum',integer,ptr,string,C.c_double)
        setint=function('fluid_settings_setint',integer,ptr,string,integer)
        for key,value in [(b'audio.file.name',str(wav).encode()),(b'audio.file.type',b'wav'),(b'audio.file.format',b's16'),(b'player.timing-source',b'sample')]:
            assert setstr(settings,key,value)==0,(key,value)
        assert setnum(settings,b'synth.sample-rate',44100)==0
        assert setnum(settings,b'synth.gain',.45)==0
        assert setint(settings,b'synth.lock-memory',0)==0
        assert setint(settings,b'audio.period-size',1024)==0
        synth=function('new_fluid_synth',ptr,ptr)(settings);assert synth
        assert function('fluid_synth_sfload',integer,ptr,string,integer)(synth,str(soundfont).encode(),1)>=0
        player=function('new_fluid_player',ptr,ptr)(synth);assert player
        assert function('fluid_player_add',integer,ptr,string)(player,str(midi).encode())==0
        assert function('fluid_player_play',integer,ptr)(player)==0
        renderer=function('new_fluid_file_renderer',ptr,ptr)(synth);assert renderer
        status=function('fluid_player_get_status',integer,ptr)
        block=function('fluid_file_renderer_process_block',integer,ptr)
        count=0
        while status(player)==1:
            assert block(renderer)==0
            count+=1
            if count*1024>44100*900:raise RuntimeError('MIDI exceeds15-minute render limit')
        assert count>0,'Empty MIDI rendering'
    finally:
        if player:
            function('fluid_player_stop',integer,ptr)(player)
            function('fluid_player_join',integer,ptr)(player)
        if renderer:function('delete_fluid_file_renderer',None,ptr)(renderer)
        if player:function('delete_fluid_player',None,ptr)(player)
        if synth:function('delete_fluid_synth',None,ptr)(synth)
        if settings:function('delete_fluid_settings',None,ptr)(settings)


def export(archive, runtime, output, soundfont, limit=0):
    manifest=json.loads((output/'manifest.json').read_text())
    tracks={};(output/'audio/music').mkdir(parents=True,exist_ok=True)
    font_hash=hashlib.sha256(soundfont.read_bytes()).hexdigest()
    previous=manifest.get('music',{}).get('tracks',{})
    with zipfile.ZipFile(archive) as z,tempfile.TemporaryDirectory(prefix='eo-music-') as temp:
        names=sorted(n for n in z.namelist() if n.startswith('mfx/') and n.lower().endswith('.mid'))
        for ident,name in enumerate(names,1):
            if limit and ident>limit:break
            raw=z.read(name);digest=hashlib.sha256(raw).hexdigest();target=output/f'audio/music/mfx{ident:03}.ogg'
            old=previous.get(str(ident),{})
            if target.exists() and old.get('source_sha256')==digest and old.get('soundfont_sha256')==font_hash:
                tracks[str(ident)]=old;continue
            midi=Path(temp)/'source.mid';wav=Path(temp)/'render.wav';midi.write_bytes(raw)
            render_midi(midi,wav,soundfont)
            with wave.open(str(wav),'rb') as w:
                seconds=w.getnframes()/w.getframerate();assert seconds>0 and w.getnchannels()==2
            subprocess.run(['ffmpeg','-v','error','-y','-i',str(wav),'-c:a','libvorbis','-q:a','3',str(target)],check=True)
            tracks[str(ident)]=dict(path='res://content/'+str(target.relative_to(output)),source_member=name,source_sha256=digest,soundfont_sha256=font_hash,duration_seconds=round(seconds,3),sample_rate=44100,sha256=hashlib.sha256(target.read_bytes()).hexdigest())
            print(f'Music {ident:02}: {seconds:.1f}s, {target.stat().st_size} bytes',flush=True)
    if limit:return tracks
    catalog_path=output/'catalog.json';catalog=json.loads(catalog_path.read_text());counts={}
    for key,record in catalog['maps'].items():
        raw=(runtime/f'data/maps/{int(key):05}.emf').read_bytes()
        values=dict(music_id=decode_number(raw[33:34]),music_control=decode_number(raw[34:35]),ambient_sound=decode_number(raw[35:37]))
        assert values['music_id']==0 or str(values['music_id']) in tracks
        p=output/record['path'].removeprefix('res://content/');world=json.loads(p.read_text());world.update(values);write_json(p,world)
        record.update(values);counts[values['music_id']]=counts.get(values['music_id'],0)+1
    selected=output/'world.json';world=json.loads(selected.read_text());world.update({k:catalog['maps'][str(world['id'])][k] for k in ('music_id','music_control','ambient_sound')});write_json(selected,world)
    write_json(catalog_path,catalog)
    manifest['music']=dict(tracks=tracks,source_archive=archive.name,source_sha256=hashlib.sha256(archive.read_bytes()).hexdigest(),soundfont=soundfont.name,soundfont_sha256=font_hash,renderer='FluidSynth General MIDI -> Ogg Vorbis',map_track_counts=counts)
    manifest['online_content']['catalog_sha256']=hashlib.sha256(catalog_path.read_bytes()).hexdigest();write_json(output/'manifest.json',manifest)
    return tracks


if __name__=='__main__':
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument('--client-zip',type=Path,required=True);p.add_argument('--runtime',type=Path,required=True);p.add_argument('--output',type=Path,default=Path('client/content'))
    p.add_argument('--soundfont',type=Path,default=Path('/usr/share/sounds/sf2/TimGM6mb.sf2'));p.add_argument('--limit',type=int,default=0)
    a=p.parse_args();export(a.client_zip,a.runtime,a.output,a.soundfont,a.limit)
