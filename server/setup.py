#!/usr/bin/env python3
"""Build pinned etheos + SQLite without privileged installs; stage local reference content."""
import argparse, hashlib, json, os, pathlib, secrets, shutil, subprocess, urllib.request, zipfile
from prepare_quests import prepare
ROOT = pathlib.Path(__file__).resolve().parent
PINS = {
    'etheos': ('https://github.com/ethanmoffat/etheos.git', 'd6b6395d5ae28e1b20cd72f33fbf23ba921e7919'),
    'bcrypt': ('https://github.com/trusch/libbcrypt.git', 'd6523c370de6e724ce4ec703e2449b5b028ea3b1'),
    'googletest': ('https://github.com/google/googletest.git', 'b514bdc898e2951020cbdca1304b75f5950d1f59'),
}
SAMPLE = ('https://etheosstorage.blob.core.windows.net/data/sample-data.zip', 'fad601ce11a4ed8d991b80b1cf31fcba237d01c566b4dc40cabb86b28861cc4e')
SQLITE = ('https://www.sqlite.org/2024/sqlite-amalgamation-3460100.zip', '77823cb110929c2bcb0f5d48e4833b5c59a8a6e40cdea3936b99e199dbbe5784')
JSON = ('https://raw.githubusercontent.com/nlohmann/json/v3.9.1/single_include/nlohmann/json.hpp', '7804b38146921d03374549c9e2a5e3acda097814c43caf2b96a0278e58df26e0')
def run(*args, **kwargs):
    print('+', ' '.join(str(x) for x in args), flush=True)
    subprocess.run([str(x) for x in args], check=True, **kwargs)
def download(url, expected, path):
    if not path.exists():
        print('Downloading', url, flush=True)
        urllib.request.urlretrieve(url, path)
    actual = hashlib.sha256(path.read_bytes()).hexdigest()
    if actual != expected: raise RuntimeError(f'SHA256 mismatch for {path}: {actual}')
    return path

def checkout(name, path):
    url, commit = PINS[name]
    if not (path / '.git').is_dir(): run('git', 'clone', '--no-checkout', url, path)
    run('git', '-C', path, 'checkout', '--detach', commit)
    actual = subprocess.check_output(['git', '-C', str(path), 'rev-parse', 'HEAD'], text=True).strip()
    if actual != commit: raise RuntimeError(f'Wrong revision for {name}')

def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('--state-dir', type=pathlib.Path, default=ROOT / '.local')
    p.add_argument('--sample-zip', type=pathlib.Path, help='Use already downloaded archive; SHA256 still verified')
    p.add_argument('--cmake', default=os.environ.get('CMAKE', shutil.which('cmake')))
    p.add_argument('--jobs', type=int, default=2)
    a = p.parse_args()
    if not a.cmake:
        candidates = sorted((pathlib.Path.home() / 'Android/Sdk/cmake').glob('*/bin/cmake'))
        if candidates: a.cmake = str(candidates[-1])
    if not a.cmake: p.error('CMake 3.x (3.13+) required. Set CMAKE or --cmake to an existing local installation.')
    state = a.state_dir.resolve(); state.mkdir(parents=True, exist_ok=True)
    deps = state / 'deps'; deps.mkdir(exist_ok=True)
    source = state / 'source'; build = state / 'build'; build.mkdir(exist_ok=True)
    checkout('etheos', source)
    (source / 'json').mkdir(exist_ok=True)
    shutil.copy2(download(*JSON, deps / 'json.hpp'), source / 'json/json.hpp')
    checkout('bcrypt', build / 'bcrypt-src')
    checkout('googletest', build / 'googletest-src')
    sqlite_zip = download(*SQLITE, deps / 'sqlite-amalgamation-3460100.zip')
    with zipfile.ZipFile(sqlite_zip) as z: z.extractall(deps)
    sqlite_src = deps / 'sqlite-amalgamation-3460100'
    sqlite_lib = deps / 'libsqlite3.a'
    if not sqlite_lib.exists():
        run(os.environ.get('CC', 'cc'), '-O2', '-DSQLITE_THREADSAFE=1', '-c', sqlite_src / 'sqlite3.c', '-o', deps / 'sqlite3.o')
        run('ar', 'rcs', sqlite_lib, deps / 'sqlite3.o')
    run(a.cmake, '-S', source, '-B', build, '-DCMAKE_BUILD_TYPE=Release', '-DEOSERV_OFFLINE=ON',
        '-DEOSERV_WANT_MYSQL=OFF', '-DEOSERV_WANT_SQLSERVER=OFF', '-DEOSERV_WANT_SQLITE=ON',
        '-DEOSERV_USE_PRECOMPILED_HEADERS=OFF', f'-DCMAKE_CXX_FLAGS=-include {source / "src/stdafx.h"}', f'-DSQLITE3_INCLUDE_DIR={sqlite_src}', f'-DSQLITE3_LIBRARY={sqlite_lib}')
    run(a.cmake, '--build', build, '--target', 'etheos', '-j', max(1,a.jobs))
    runtime = state / 'runtime'; runtime.mkdir(exist_ok=True)
    # Only configuration and reference game data are staged, never source git metadata.
    for name in ['config', 'lang', 'data']:
        shutil.copytree(source / name, runtime / name, dirs_exist_ok=True)
    for name in ['config.ini', 'admin.ini', 'install.sql']:
        shutil.copy2(source / name, runtime / name)
    sample_path = a.sample_zip.resolve() if a.sample_zip else deps / 'sample-data.zip'
    sample_path = download(*SAMPLE, sample_path)
    with zipfile.ZipFile(sample_path) as z:
        names = z.namelist()
        for member in names:
            path = pathlib.PurePosixPath(member)
            if path.parts[0] != 'sample-data' or '..' in path.parts: raise RuntimeError('Unexpected archive path')
            if member.endswith('/'): continue
            target = runtime / 'data' / pathlib.Path(*path.parts[1:])
            target.parent.mkdir(parents=True, exist_ok=True)
            target.write_bytes(z.read(member))
    quests = prepare(runtime / 'data/quests')
    maps = sorted((runtime / 'data/maps').glob('[0-9][0-9][0-9][0-9][0-9].emf'))
    local = runtime / 'config.local.ini'
    if local.exists():
        salt_lines = [line for line in local.read_text().splitlines() if line.startswith('PasswordSalt = ')]
        salt = salt_lines[0].split(' = ',1)[1] if salt_lines else secrets.token_hex(32)
    else: salt = secrets.token_hex(32)
    local.write_text(f'''# Generated LOCAL DEVELOPMENT config. Not suitable for public hosting.
Host = 127.0.0.1
Port = 8078
SLN = no
ServerName = Aster Vale Local Development
FirstCharacterAdmin = no
IPReconnectLimit = 0
MaxConnectionsPerIP = 12
StartMap = 5
StartX = 40
StartY = 40
StartItems = 21,1;80,1;143,1
DBType = sqlite
DBHost = database.sdb
DBUser =
DBPass =
DBName =
InstallSQL = ./install.sql
Maps = {max(int(x.stem) for x in maps)}
Quests = {max(q['id'] for q in quests)}
PasswordSalt = {salt}
ThreadPoolThreads = 2
LogOut = -
LogErr = -
StyleConsole = no
WorldDumpFile = ./world.bak.json
''')
    local.chmod(0o600)
    # Avoid loading SQL Server defaults at all (SQLite-only build).
    (runtime / 'config/database.ini').write_text('INCLUDE = ./config/database/sqlite.ini\nInstallSQL = ./install.sql\nAutoCreateDatabase = no\nDBPassFile =\nDBAuthType = sql\n')
    shutil.copy2(build / 'etheos', runtime / 'etheos')
    report = {'source_pins':{k:{'url':v[0],'commit':v[1]} for k,v in PINS.items()},
              'sample':{'url':SAMPLE[0],'sha256':SAMPLE[1]}, 'sqlite':{'url':SQLITE[0],'sha256':SQLITE[1]}, 'nlohmann_json':{'url':JSON[0],'sha256':JSON[1]},
              'numbered_maps':len(maps),'highest_map_id':max(int(x.stem) for x in maps),
              'quest_conversion':'Generated .eqf copies with logged conservative legacy-syntax fixes. Original .txt bytes preserved. Real parser validation recorded separately.',
              'quests':quests,'runtime':str(runtime),'binding':'127.0.0.1:8078','database':'SQLite',
              'rights':'Reference content only; redistribution/publication permissions unresolved.'}
    (state / 'content-report.json').write_text(json.dumps(report, indent=2)+'\n')
    (ROOT / '.state-path').write_text(str(state)+'\n')
    print(f'Built and staged {len(maps)} maps, {len(quests)} quests. Runtime: {runtime}')
if __name__ == '__main__': main()
