#!/usr/bin/env python3
"""Run the staged local-only development server in the foreground."""
import argparse, os, pathlib
ROOT=pathlib.Path(__file__).resolve().parent

def state_path(explicit=None):
    if explicit: return pathlib.Path(explicit).resolve()
    pointer=ROOT/'.state-path'
    return pathlib.Path(pointer.read_text().strip()) if pointer.exists() else ROOT/'.local'

def main():
    p=argparse.ArgumentParser(description=__doc__);p.add_argument('--state-dir');a=p.parse_args()
    runtime=state_path(a.state_dir)/'runtime'
    if not (runtime/'etheos').exists(): p.error('Run setup.py first.')
    config=(runtime/'config.local.ini').read_text()
    if 'Host = 127.0.0.1\n' not in config or 'SLN = no\n' not in config:
        p.error('This local launcher requires Host = 127.0.0.1 and SLN = no.')
    # ETHEOS_* can override file values. Strip inherited overrides for predictable local configuration.
    env={k:v for k,v in os.environ.items() if not k.startswith('ETHEOS_')}
    os.chdir(runtime);os.execve(str(runtime/'etheos'),['etheos'],env)
if __name__=='__main__':main()
