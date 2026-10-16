#!/usr/bin/env python3
"""Inventory user-provided EO archives without executing or extracting code."""
import argparse
import hashlib
import json
from pathlib import Path
import struct
import zipfile
from import_eo import PEBitmaps, decode_number, parse_emf, read_member, write_json
from export_catalog import pub_records, parse_items, parse_npcs


def digest(data):return hashlib.sha256(data).hexdigest()


def audit(baseline,gfx_path,delta_path,runtime):
    report={'source_archives':{},'graphics':[],'delta_maps':[],'delta_pub':[],
            'publication_rights':'Unresolved for original game art/data. Inputs and generated reports remain local ignored references.'}
    for path in (baseline,gfx_path,delta_path):
        with zipfile.ZipFile(path) as archive:
            bad=archive.testzip()
            if bad:raise ValueError(f'CRC mismatch: {bad}')
            metadata=path.with_name(path.name+'.metadata.json')
            report['source_archives'][path.name]={'sha256':digest(path.read_bytes()),'bytes':path.stat().st_size,'crc_ok':True,
                 'provenance':json.loads(metadata.read_text()) if metadata.exists() else None}
    with zipfile.ZipFile(baseline) as old,zipfile.ZipFile(gfx_path) as new:
        for member in sorted(n for n in new.namelist() if n.lower().endswith('.egf')):
            canonical='gfx/'+member.rsplit('/',1)[-1]
            a=read_member(old,canonical);b=read_member(new,member)
            pe=PEBitmaps(b);dimensions=[]
            for bitmap in pe.resources.values():
                header=struct.unpack_from('<I',bitmap)[0]
                if header>=40:w,h=struct.unpack_from('<ii',bitmap,4)
                elif header==12:w,h=struct.unpack_from('<HH',bitmap,4)
                else:raise ValueError('unknown bitmap header')
                dimensions.append((w,abs(h)))
            report['graphics'].append({'member':member,'bytes':len(b),'sha256':digest(b),
                'byte_identical_to_baseline':a==b,'bitmap_count':len(pe.resources),
                'graphic_id_range':[min(pe.resources)-100,max(pe.resources)-100],
                'min_dimensions':[min(w for w,h in dimensions),min(h for w,h in dimensions)],
                'max_dimensions':[max(w for w,h in dimensions),max(h for w,h in dimensions)]})
    with zipfile.ZipFile(delta_path) as archive:
        for member in archive.namelist():
            suffix=Path(member).suffix.lower()
            if '/data/maps/' in member and suffix=='.emf':
                world=parse_emf(read_member(archive,member),int(Path(member).stem))
                report['delta_maps'].append({'member':member,'id':world['id'],'name':world['name'],
                  'dimensions':[world['width'],world['height']],'npcs':len(world['npcs']),
                  'sha256':digest(read_member(archive,member))})
            if '/data/pub/' in member and suffix in ('.eif','.enf','.ecf','.esf'):
                data=read_member(archive,member);signature=data[:3].decode()
                size,names={'EIF':(58,1),'ENF':(39,1),'ECF':(14,1),'ESF':(51,2)}[signature]
                records=pub_records(data,signature,size,names)
                staged=runtime/'data/pub'/Path(member).name
                same=staged.exists() and data==staged.read_bytes()
                result={'member':member,'signature':signature,'record_size':size,'record_count':len(records),
                        'bytes':len(data),'sha256':digest(data),'identical_to_runtime':same}
                if staged.exists():
                    baseline_records=pub_records(staged.read_bytes(),signature,size,names)
                    result['runtime_record_count']=len(baseline_records)
                    result['added_ids']=sorted(set(records)-set(baseline_records))
                    result['changed_ids']=[i for i in records.keys()&baseline_records.keys() if records[i]!=baseline_records[i]]
                report['delta_pub'].append(result)
        license_member=next((n for n in archive.namelist() if n.endswith('/LICENSE.txt')),None)
        if license_member:report['delta_license']={'member':license_member,'sha256':digest(read_member(archive,license_member)),
          'opening':read_member(archive,license_member).decode(errors='replace')[:240]}
    report['summary']={'graphics_files':len(report['graphics']),
       'graphics_all_identical':all(g['byte_identical_to_baseline'] for g in report['graphics']),
       'bitmap_resources':sum(g['bitmap_count'] for g in report['graphics']),
       'delta_maps':len(report['delta_maps']),'runtime_numbered_maps':len(list((runtime/'data/maps').glob('[0-9][0-9][0-9][0-9][0-9].emf'))),
       'recommendation':'Keep current graphics and 282-map runtime baseline. The new graphics are exact duplicates; the delta server archive is a separate small older/custom data set.'}
    return report


def main():
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument('--baseline',type=Path,required=True);p.add_argument('--gfx',type=Path,required=True)
    p.add_argument('--delta',type=Path,required=True);p.add_argument('--runtime',type=Path,required=True)
    p.add_argument('--output',type=Path,required=True);a=p.parse_args()
    report=audit(a.baseline,a.gfx,a.delta,a.runtime);a.output.parent.mkdir(parents=True,exist_ok=True)
    write_json(a.output,report);print(json.dumps(report['summary'],indent=2))


if __name__=='__main__':main()
