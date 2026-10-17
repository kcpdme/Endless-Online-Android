"""Compare exported music/maps with the original supplied files, not invented tracks."""
import hashlib,json,subprocess,unittest,zipfile
from pathlib import Path
from import_eo import decode_number
ROOT=Path(__file__).resolve().parents[1]
CONTENT=ROOT/'client/content'
RUNTIME=ROOT/'work/server-build/runtime'
ARCHIVE=ROOT/'work/eoserv-crawl/downloads/EOzipped028.zip'

@unittest.skipUnless(ARCHIVE.exists() and (CONTENT/'audio/music').exists(),'original resources unavailable')
class OriginalMusicTests(unittest.TestCase):
    def test_original_sources_and_portable_nonempty_audio(self):
        music=json.loads((CONTENT/'manifest.json').read_text())['music']
        self.assertEqual(len(music['tracks']),45)
        with zipfile.ZipFile(ARCHIVE) as source:
            for key,track in music['tracks'].items():
                with self.subTest(track=key):
                    self.assertEqual(hashlib.sha256(source.read(f'mfx/mfx{int(key):03}.mid')).hexdigest(),track['source_sha256'])
                    path=CONTENT/track['path'].removeprefix('res://content/')
                    self.assertEqual(hashlib.sha256(path.read_bytes()).hexdigest(),track['sha256'])
                    info=json.loads(subprocess.check_output(['ffprobe','-v','error','-show_streams','-show_format','-of','json',str(path)]))
                    audio=info['streams'][0]
                    self.assertEqual((audio['codec_name'],int(audio['sample_rate']),audio['channels']),('vorbis',44100,2))
                    self.assertAlmostEqual(float(info['format']['duration']),track['duration_seconds'],delta=.05)
                    # Decode the full track and inspect measured volume; silent/broken exports fail.
                    result=subprocess.run(['ffmpeg','-hide_banner','-i',str(path),'-af','volumedetect','-f','null','-'],capture_output=True,text=True,check=True)
                    self.assertIn('mean_volume:',result.stderr)
                    self.assertNotIn('mean_volume: -inf',result.stderr)
    def test_every_map_retains_original_music_controls(self):
        catalog=json.loads((CONTENT/'catalog.json').read_text())
        tracks=json.loads((CONTENT/'manifest.json').read_text())['music']['tracks']
        self.assertEqual(len(catalog['maps']),282)
        quiet=0
        for key,record in catalog['maps'].items():
            with self.subTest(map=key):
                raw=(RUNTIME/f'data/maps/{int(key):05}.emf').read_bytes()
                expected=(decode_number(raw[33:34]),decode_number(raw[34:35]),decode_number(raw[35:37]))
                world=json.loads((CONTENT/record['path'].removeprefix('res://content/')).read_text())
                for data in (world,record):
                    self.assertEqual(tuple(data[k] for k in ('music_id','music_control','ambient_sound')),expected)
                if expected[0]:self.assertIn(str(expected[0]),tracks)
                else:quiet+=1
        self.assertEqual(quiet,172)

if __name__=='__main__':unittest.main()
