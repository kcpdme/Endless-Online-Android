#!/usr/bin/env python3
"""Export original EO PCM effects and the pinned client's exact sound mappings.

SoundEffectID is one-based at playback: ContentProvider starts dictionary key0,
then SfxPlayer indexes id-1. Thus MeleeWeaponAttack15 is sfx015.wav, not016.
The original archive/audio and generated assets remain ignored.
"""
import argparse,hashlib,json,re,zipfile
from pathlib import Path
from import_eo import canonical_wav,read_member,write_json

def read_mappings(client):
    root=Path(client)/'EndlessClient'
    paths=[root/'Audio/SoundEffectID.cs',root/'Audio/SfxPlayer.cs',root/'Content/ContentProvider.cs',root/'Rendering/Metadata/WeaponMetadataProvider.cs',root/'Rendering/Metadata/EffectMetadataProvider.cs']
    text=paths[0].read_text(encoding='utf-8-sig')
    enum=re.search(r'enum SoundEffectID\s*\{(.*?)\n\s*}',text,re.S).group(1)
    names={};value=-1
    for line in enum.splitlines():
        line=line.split('//',1)[0].strip().rstrip(',')
        if not line:continue
        name,sep,assigned=line.partition('=');name=name.strip();assigned=assigned.strip()
        value=(int(assigned) if assigned.isdigit() else names[assigned]) if sep else value+1
        names[name]=value
    weapons={}
    for ident,values in re.findall(r'\{\s*(\d+),\s*new WeaponMetadata\([^,]+,\s*new\[\]\s*\{([^}]+)}',paths[3].read_text()):
        weapons[ident]=[names[n] for n in re.findall(r'SoundEffectID\.(\w+)',values)]
    effects={}
    for ident,name,number in re.findall(r'\{\s*(\d+),\s*new EffectMetadata\([^,]+,[^,]+,[^,]+,\s*(?:SoundEffectID\.(\w+)|(\d+)),',paths[4].read_text()):
        effects[ident]=names[name] if name else int(number)
    assert len(weapons)==75 and len(effects)==34
    return dict(names=names,weapons=weapons,effects=effects,attack_sound_delay_seconds=.24,source={str(p.relative_to(Path(client))):hashlib.sha256(p.read_bytes()).hexdigest() for p in paths})

def export(archive,client,out):
    out=Path(out);manifest=json.loads((out/'manifest.json').read_text());config=read_mappings(client)
    target=out/'audio/sfx';target.mkdir(parents=True,exist_ok=True);sounds={}
    with zipfile.ZipFile(archive) as source:
        for member in sorted(n for n in source.namelist() if re.fullmatch(r'sfx/sfx\d{3}\.wav',n)):
            ident=int(re.search(r'(\d{3})\.wav',member).group(1));raw=read_member(source,member);canonical,meta=canonical_wav(raw)
            path=target/f'sfx{ident:03}.wav';path.write_bytes(canonical)
            sounds[str(ident)]=dict(path='res://content/'+str(path.relative_to(out)),source_member=member,source_sha256=hashlib.sha256(raw).hexdigest(),sha256=hashlib.sha256(canonical).hexdigest(),**meta)
        bard={}
        for instrument,prefix in [(49,'har'),(50,'gui')]:
            notes=[]
            for index in range(1,37):
                member=f'sfx/{prefix}{index:03}.wav';raw=read_member(source,member);canonical,meta=canonical_wav(raw)
                path=target/f'{prefix}{index:03}.wav';path.write_bytes(canonical)
                notes.append(dict(path='res://content/'+str(path.relative_to(out)),source_member=member,source_sha256=hashlib.sha256(raw).hexdigest(),sha256=hashlib.sha256(canonical).hexdigest(),**meta))
            bard[str(instrument)]=notes
        manifest['bard_notes']=bard
    assert len(sounds)==81
    assert all(str(i) in sounds for values in config['weapons'].values() for i in values)
    assert all(i==0 or str(i) in sounds for i in config['effects'].values())
    manifest['sfx']=sounds;manifest['sfx_config']=config
    # Maintain old named aliases for offline/import compatibility with correct files.
    for key,name in [('attack','MeleeWeaponAttack'),('punch','PunchAttack'),('pickup','InventoryPickup')]:manifest['sounds'][key]=sounds[str(config['names'][name])]
    write_json(out/'manifest.json',manifest)
    return dict(sounds=len(sounds),weapon_mappings=len(config['weapons']),effect_mappings=len(config['effects']),bytes=sum(p.stat().st_size for p in target.glob('*.wav')))

if __name__=='__main__':
    p=argparse.ArgumentParser(description=__doc__);p.add_argument('--client-zip',type=Path,required=True);p.add_argument('--original-client',type=Path,required=True);p.add_argument('--output',type=Path,default=Path('client/content'))
    a=p.parse_args();print(json.dumps(export(a.client_zip,a.original_client,a.output)))
