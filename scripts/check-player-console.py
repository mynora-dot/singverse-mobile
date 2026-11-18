#!/usr/bin/env python3
"""Validate a predefined suite on an explicitly selected physical Android phone.

Uses only the isolated .e2e package and a disposable loopback NAS on port 18181.
The player sample must come from setup-mobile-karaoke-fixtures.py. Library and
NAS UI suites use their existing controlled fixtures and need no voice sample.
"""
import argparse
import hashlib
import json
import os
from pathlib import Path
import queue
import re
import shutil
import subprocess
import threading
import time
from urllib.request import urlopen

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--device', required=True, help='Explicit adb serial of the physical phone')
parser.add_argument('--target', choices=('library_glass', 'nas_glass', 'player_console', 'apple_prototype'), default='player_console')
parser.add_argument('--voice-sample', type=Path, help='Required for player_console and apple_prototype')
parser.add_argument('--output', required=True, type=Path)
parser.add_argument('--adb', default=shutil.which('adb'))
parser.add_argument('--reuse-installed-apk', action='store_true', help='Skip installation only when the rebuilt APK exactly matches the installed .e2e base.apk SHA256')
args = parser.parse_args()
root = Path(__file__).resolve().parents[1]
output = args.output.resolve()
if output.exists():
    parser.error('Use a new output directory; previous reports are preserved.')
sample = args.voice_sample.resolve() if args.voice_sample else None
if args.target in ('player_console', 'apple_prototype') and sample is None:
    parser.error('--voice-sample is required for the native player suite.')
if sample is not None and (not sample.is_file() or not (sample.parent / '.singverse-karaoke-fixture').is_file()):
    parser.error('Provide the original sample from setup-mobile-karaoke-fixtures.py.')
if not args.adb:
    parser.error('adb is unavailable; provide --adb explicitly.')
output.mkdir(parents=True)
serial = args.device
adb = args.adb
device = [adb, '-s', serial]

def shell(*command):
    return subprocess.check_output(device + ['shell', *command], text=True).strip()

if serial.startswith('emulator-') or shell('getprop','ro.kernel.qemu') == '1':
    raise RuntimeError('Physical device required')
metadata = {'serial':serial,'model':shell('getprop','ro.product.model'), 'android':shell('getprop','ro.build.version.release'), 'api':shell('getprop','ro.build.version.sdk'),'size':shell('wm','size'),'density':shell('wm','density'),'fontScale':shell('settings','get','system','font_scale'),'physical':True,'build':'profile','package':'com.mynora.singverse.mobile.e2e'}
metadata['target'] = args.target
(output/'device.json').write_text(json.dumps(metadata,indent=2))
daily_before = shell('dumpsys','package','com.mynora.singverse.mobile')
(output/'daily-package-before.txt').write_text('\n'.join(line for line in daily_before.splitlines() if any(key in line for key in ['versionName=', 'lastUpdateTime='])))
rules = subprocess.check_output(device+['reverse','--list'], text=True)
matches = [line for line in rules.splitlines() if 'tcp:18181' in line]
if matches and not all(line.endswith('tcp:18181 tcp:18181') for line in matches):
    raise RuntimeError('Existing reverse port mapping is owned by another task')
added_reverse = not matches
if added_reverse:
    subprocess.run(device+['reverse','tcp:18181','tcp:18181'],check=True)
environment = dict(os.environ,ORG_GRADLE_PROJECT_singverseE2e='true',SINGVERSE_PROFILE_REPORT=str(output/'report.json'),SINGVERSE_LIBRARY_GLASS_OUTPUT=str(output),SINGVERSE_NAS_GLASS_OUTPUT=str(output))
flutter = shutil.which('flutter') or 'flutter'
target = f'integration_test/{args.target}_test.dart'
driver = {
    'player_console':'test_driver/liquid_glass_driver.dart',
    'library_glass':'test_driver/library_glass_driver.dart',
    'nas_glass':'test_driver/nas_glass_driver.dart',
    'apple_prototype':'test_driver/liquid_glass_driver.dart',
}[args.target]
screen_markers = {
    'player_console':{'PLAYER_SCREEN':''},
    'library_glass':{'LIBRARY_GLASS_SCREEN':''},
    'nas_glass':{'NAS_GLASS_SCREEN':''},
    'apple_prototype':{'LIBRARY_GLASS_SCREEN':'library','NAS_GLASS_SCREEN':'nas','PLAYER_SCREEN':'player'},
}[args.target]
screen_pattern = re.compile(r'('+'|'.join(re.escape(marker) for marker in screen_markers)+r'):([A-Za-z0-9_-]+)')
process = None
bridge = None
events = queue.Queue()
forward_port = None
record_pid = None
record_index = 0
remote_video = ''
seen = set()
handled_hooks = set()
voice = None

def read_output(source, stream):
    try:
        for line in stream:
            events.put((source,line))
    finally:
        events.put((source,None))

def finish_video():
    global record_pid
    if record_pid is None: return
    pid,record_pid = record_pid,None
    subprocess.run(device+['shell','kill','-INT',pid],stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL)
    time.sleep(.3)
    result = subprocess.run(device+['pull',remote_video,str(output/f'interactions-{record_index}.mp4')],capture_output=True,text=True)
    if result.returncode: (output/f'video-warning-{record_index}.txt').write_text(result.stderr)

def start_video():
    global record_pid,record_index,remote_video
    finish_video()
    record_index += 1
    remote_video = f'/sdcard/singverse-console-{os.getpid()}-{record_index}.mp4'
    record_pid = shell(f'screenrecord --size 640x1422 --time-limit 100 {remote_video} >/dev/null 2>&1 & echo $!')

summary = {'device':metadata,'target':args.target,'screenshots':[]}
try:
    # A rejected USB install must stop here. Flutter's automatic install retry
    # can uninstall an existing package, losing its retained test recordings.
    with (output/'build.log').open('w') as log:
        subprocess.run([flutter,'--no-version-check','build','apk','--profile','--no-pub',f'--target={target}','--dart-define=TEST_NAS=http://127.0.0.1:18181'],cwd=root,env=environment,stdout=log,stderr=subprocess.STDOUT,check=True)
    apk = root/'build/app/outputs/flutter-apk/app-profile.apk'
    if args.reuse_installed_apk:
        print(f'Verifying installed .e2e APK SHA256 against rebuilt {args.target}; installation will be skipped only on an exact match.', flush=True)
        digest = hashlib.sha256()
        with apk.open('rb') as package:
            for chunk in iter(lambda: package.read(1024*1024), b''):
                digest.update(chunk)
        local_sha256 = digest.hexdigest()
        paths = [line.removeprefix('package:') for line in shell('pm','path','com.mynora.singverse.mobile.e2e').splitlines() if line.startswith('package:')]
        bases = [path for path in paths if path.startswith('/') and path.endswith('/base.apk')]
        if len(bases) != 1:
            raise RuntimeError('Expected one installed .e2e base.apk; no installation fallback was attempted.')
        installed_digest = shell('sha256sum',bases[0]).split()
        if not installed_digest or not re.fullmatch(r'[0-9a-fA-F]{64}',installed_digest[0]):
            raise RuntimeError('Could not read installed .e2e SHA256; no installation fallback was attempted.')
        installed_sha256 = installed_digest[0].lower()
        summary['apkVerification'] = {'localSha256':local_sha256,'installedSha256':installed_sha256,'installedBaseApk':bases[0]}
        (output/'install.log').write_text(json.dumps(summary['apkVerification'],indent=2))
        if local_sha256 != installed_sha256:
            raise RuntimeError('Installed .e2e APK SHA256 differs from the rebuilt target; no installation, retry or uninstall was attempted.')
        summary['installation'] = 'reused-installed-apk-sha256-match'
    else:
        print(f'Installing isolated .e2e APK for {args.target}; confirm installation on the phone. Waiting up to 600 seconds.', flush=True)
        with (output/'install.log').open('w') as log:
            installed = subprocess.run(device+['install','-t','-r',str(apk)],stdout=log,stderr=subprocess.STDOUT,timeout=600)
        if installed.returncode or 'Failure' in (output/'install.log').read_text():
            raise RuntimeError('USB installation was rejected; no uninstall or retry was attempted.')
        summary['installation'] = 'single-replace-install'
    shell('am','force-stop','com.mynora.singverse.mobile.e2e')
    shell('am','start','-a','android.intent.action.MAIN','-c','android.intent.category.LAUNCHER','--ez','start-paused','true','--ez','enable-dart-profiling','true','--ez','enable-impeller','true','--ez','disable-service-auth-codes','true','com.mynora.singverse.mobile.e2e/com.mynora.singverse.mobile.MainActivity')
    pid = shell('pidof','com.mynora.singverse.mobile.e2e')
    if not pid or ' ' in pid: raise RuntimeError('Expected one isolated test process.')
    identity = re.search(r'\b(?:userId|appId)=(\d+)',shell('dumpsys','package','com.mynora.singverse.mobile.e2e'))
    if identity is None: raise RuntimeError('Could not identify the isolated package UID.')
    uid = identity[1]
    deadline = time.monotonic()+60
    address = None
    # Some vivo builds suppress process logcat. Discover only this package's
    # loopback listener and verify the VM protocol instead of relying on logs.
    while address is None and time.monotonic()<deadline:
        for row in shell('cat',f'/proc/{pid}/net/tcp').splitlines()[1:]:
            columns = row.split()
            if columns[3]!='0A' or columns[7]!=uid or not columns[1].startswith('0100007F:'): continue
            port = int(columns[1].split(':')[1],16)
            candidate = subprocess.check_output(device+['forward','tcp:0','tcp:'+str(port)],text=True).strip()
            try:
                with urlopen('http://127.0.0.1:'+candidate+'/getVM',timeout=2) as response:
                    vm = json.load(response)
                if vm.get('result',{}).get('type')!='VM': raise ValueError('Not a Dart VM service')
                forward_port = candidate
                address = 'http://127.0.0.1:'+candidate+'/'
                break
            except Exception:
                subprocess.run(device+['forward','--remove','tcp:'+candidate],check=True)
        if address is None: time.sleep(.2)
    if address is None: raise RuntimeError('Dart VM service did not start within 60 seconds.')
    # DDS takes ownership of the VM service and closes direct subscribers.
    # Keep the marker bridge and driver attached to the verified service.
    command = [flutter,'--no-version-check','drive','--profile','--no-dds','--no-pub',f'--driver={driver}',f'--target={target}','--use-existing-app='+address,'--keep-app-running','-d',serial]
    dart = Path(flutter).resolve().parent/'cache/dart-sdk/bin/dart'
    if not dart.is_file():
        raise RuntimeError('Could not locate Dart in the selected Flutter SDK.')
    with (output/'integration.log').open('w') as log, (output/'vm.log').open('w') as vm_log:
        bridge = subprocess.Popen([str(dart),str(root/'scripts/phone_vm_log_bridge.dart'),address],cwd=root,env=environment,stdout=subprocess.PIPE,stderr=subprocess.STDOUT,text=True,bufsize=1)
        threading.Thread(target=read_output,args=('vm',bridge.stdout),daemon=True).start()
        ready_deadline = time.monotonic()+30
        while True:
            try:
                source,line = events.get(timeout=max(.01,ready_deadline-time.monotonic()))
            except queue.Empty:
                raise RuntimeError('VM stdout/stderr subscription did not become ready within 30 seconds.')
            if line is None:
                raise RuntimeError('VM log bridge exited before subscribing; see vm.log.')
            vm_log.write(line); vm_log.flush()
            if line.strip() == 'PHONE_VM_LOG_BRIDGE_READY': break
            if time.monotonic() >= ready_deadline:
                raise RuntimeError('VM stdout/stderr subscription did not become ready within 30 seconds.')
        summary['vmLogBridge'] = {'ready':True,'streams':['Stdout','Stderr']}
        process = subprocess.Popen(command,cwd=root,env=environment,stdout=subprocess.PIPE,stderr=subprocess.STDOUT,text=True,bufsize=1)
        threading.Thread(target=read_output,args=('driver',process.stdout),daemon=True).start()
        while True:
            source,line = events.get()
            if line is None:
                if source == 'driver': break
                if process.poll() is None:
                    raise RuntimeError('VM log bridge disconnected while the driver was running; host hooks are not reliable.')
                continue
            destination = vm_log if source == 'vm' else log
            destination.write(line); destination.flush()
            match = screen_pattern.search(line)
            screenshot_name = str(Path(screen_markers[match[1]])/match[2]) if match else None
            if match and screenshot_name not in seen:
                name=match[2]; seen.add(screenshot_name)
                if name in ['01-video-playing','11-countdown']: start_video()
                screenshot = output/(screenshot_name+'.png')
                screenshot.parent.mkdir(parents=True,exist_ok=True)
                with screenshot.open('wb') as picture:
                    subprocess.run(device+['exec-out','screencap','-p'],stdout=picture,check=True)
                if name in ['06-more-tools', '13-recording-review']:
                    finish_video()
            elif 'PLAYER_MIC_GRANT' in line and 'PLAYER_MIC_GRANT' not in handled_hooks:
                handled_hooks.add('PLAYER_MIC_GRANT')
                for permission in ['android.permission.RECORD_AUDIO','android.permission.POST_NOTIFICATIONS']:
                    shell('pm','grant','com.mynora.singverse.mobile.e2e',permission)
            elif 'PLAYER_HOST_VOICE' in line and 'PLAYER_HOST_VOICE' not in handled_hooks:
                handled_hooks.add('PLAYER_HOST_VOICE')
                if shutil.which('afplay'):
                    voice = subprocess.Popen(['afplay',str(sample)],stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL)
            elif 'PLAYER_LARGE_FONT' in line and 'PLAYER_LARGE_FONT' not in handled_hooks:
                handled_hooks.add('PLAYER_LARGE_FONT')
                shell('settings','put','system','font_scale','2.0')
            elif 'PLAYER_NORMAL_FONT' in line and 'PLAYER_NORMAL_FONT' not in handled_hooks:
                handled_hooks.add('PLAYER_NORMAL_FONT')
                if metadata['fontScale']=='null': shell('settings','delete','system','font_scale')
                else: shell('settings','put','system','font_scale',metadata['fontScale'])
        summary['exitCode']=process.wait()
        if summary['exitCode'] == 0:
            report = json.loads((output/'report.json').read_text())
            if args.target in ('player_console','apple_prototype'):
                if len(report.get('checks', [])) < 21 or len(report.get('scenarios', {})) != 3:
                    summary.update(exitCode=1, failure='Expected all 21 native checks and three timing scenarios.')
                required_hooks = {'PLAYER_MIC_GRANT','PLAYER_HOST_VOICE','PLAYER_LARGE_FONT','PLAYER_NORMAL_FONT'}
                if not required_hooks <= handled_hooks:
                    summary.update(exitCode=1, failure='Missing native host hooks: '+', '.join(sorted(required_hooks-handled_hooks)))
            ui_reports = report.get('uiSuites',{}) if args.target == 'apple_prototype' else ({args.target:report} if args.target != 'player_console' else {})
            if args.target == 'apple_prototype' and set(ui_reports) != {'library_glass','nas_glass'}:
                summary.update(exitCode=1, failure='Expected both bundled UI suite reports.')
            for ui_name, ui_report in ui_reports.items():
                timings = ui_report.get('timings', [])
                if (ui_report.get('renderer') != 'Impeller' or len(timings) != 2
                        or {item.get('mode') for item in timings} != {'default','performance'}
                        or any(item.get('frames',0) <= 0 for item in timings)):
                    summary.update(exitCode=1, failure=f'{ui_name}: expected Impeller and nonempty default/performance UI timing samples.')
            if ui_reports:
                summary['uiSuites'] = ui_reports
            if not seen:
                summary['caveats'] = ['No Dart SCREEN markers were observed; no scenario screenshots are available. A post-run screenshot is independent after-run evidence only.']
                try:
                    picture = subprocess.run(device+['exec-out','screencap','-p'],capture_output=True,check=True)
                    if not picture.stdout.startswith(b'\x89PNG\r\n\x1a\n'):
                        raise RuntimeError('Post-run capture did not return a PNG.')
                    (output/'post-run.png').write_bytes(picture.stdout)
                    summary['postRunEvidence'] = {'path':'post-run.png','kind':'after-run-only','sceneCapture':False}
                except Exception as error:
                    summary['postRunCaptureFailure'] = f'{type(error).__name__}: {error}'
except Exception as error:
    summary.update(exitCode=1, failure=f'{type(error).__name__}: {error}')
finally:
    summary['functionalPassed'] = summary.get('exitCode') == 0
    if process and process.poll() is None:
        process.terminate()
        try:
            process.wait(timeout=15)
        except subprocess.TimeoutExpired:
            process.kill()
            process.wait(timeout=5)
    if bridge and bridge.poll() is None:
        bridge.terminate()
        try:
            bridge.wait(timeout=5)
        except subprocess.TimeoutExpired:
            bridge.kill()
            bridge.wait(timeout=5)
    if forward_port:
        removed = subprocess.run(device+['forward','--remove','tcp:'+forward_port],capture_output=True,text=True)
        if removed.returncode:
            summary.setdefault('cleanupWarnings',[]).append('VM forward removal: '+removed.stderr.strip())
    finish_video()
    if voice and voice.poll() is None: voice.terminate()
    if metadata['fontScale']=='null': shell('settings','delete','system','font_scale')
    else: shell('settings','put','system','font_scale',metadata['fontScale'])
    summary['fontScaleRestored'] = shell('settings','get','system','font_scale') == metadata['fontScale']
    if added_reverse:
        subprocess.run(device+['reverse','--remove','tcp:18181'],check=True)
    summary['screenshots']=sorted(seen)
    summary['handledHooks']=sorted(handled_hooks)
    summary['sceneCapture'] = {'available':bool(seen),'count':len(seen),'source':'Dart SCREEN markers'}
    after=shell('dumpsys','package','com.mynora.singverse.mobile')
    value='\n'.join(line for line in after.splitlines() if any(key in line for key in ['versionName=', 'lastUpdateTime=']))
    summary['dailyPackageUnchanged']=value==(output/'daily-package-before.txt').read_text()
    (output/'acceptance.json').write_text(json.dumps(summary,indent=2))
def compact_console(value):
    if isinstance(value, dict):
        return {
            key+'Count' if key in ('frameTimings','gestures') and isinstance(item,list) else key:
            len(item) if key in ('frameTimings','gestures') and isinstance(item,list) else compact_console(item)
            for key,item in value.items()
        }
    if isinstance(value, list):
        return [compact_console(item) for item in value]
    return value

print(json.dumps(compact_console(summary)))
raise SystemExit(summary.get('exitCode',1))
