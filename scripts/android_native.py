"""Stage the small first-party Android Keystore plugin in the Godot Gradle template."""
from pathlib import Path
import re,shutil
ROOT=Path(__file__).resolve().parents[1]
def stage():
    build=ROOT/'client/android/build'
    if not (build/'build.gradle').exists():raise RuntimeError('Install the Godot Android build template first')
    source=ROOT/'platform/android/com/cloudgameboy/astervale';target=build/'src/main/java/com/cloudgameboy/astervale';target.mkdir(parents=True,exist_ok=True)
    for path in source.glob('*.java'):shutil.copy2(path,target/path.name)
    manifest=build/'src/main/AndroidManifest.xml';text=manifest.read_text()
    if 'org.godotengine.plugin.v2.AsterCredentials' not in text:
        text=re.sub(r'(<application\b[^>]*>)',r'\1\n        <meta-data android:name="org.godotengine.plugin.v2.AsterCredentials" android:value="com.cloudgameboy.astervale.AsterCredentials" />',text,count=1)
    manifest.write_text(text)
