#!/usr/bin/env python3
"""Identity-guarded native screenshots/input for the private Jammy QA session."""
import json
import os
import pathlib
import signal
import subprocess
import sys
import time
import importlib.util
_common_spec = importlib.util.spec_from_file_location('jammy_input_common', pathlib.Path(__file__).with_name('jammy-input-common.py'))
INPUT = importlib.util.module_from_spec(_common_spec)
_common_spec.loader.exec_module(INPUT)

PROFILE = os.environ.get('BDK_JAMMY_QA_PROFILE', 'gui')
assert PROFILE in ('gui', 'gui-softpipe'), 'Unknown isolated GUI profile'
QA = pathlib.Path('/home/runner/evidence') / PROFILE
BUNDLE = pathlib.Path('/home/runner/bdk-audio-056-jammy/build/linux/x64/debug/bundle')
EXE = BUNDLE / 'bdk_audio'
assert pathlib.Path('/.bdk-owned-jammy-root').read_text().strip() == 'jammy-056-20261016'
assert os.getuid() == 1000


def identity():
    saved = json.loads((QA / 'identity.json').read_text())
    pid, xid = saved['pid'], saved['xid']
    assert pathlib.Path(os.readlink('/proc/%s/exe' % pid)).resolve() == EXE.resolve()
    assert int(INPUT.output(['xdotool', 'getwindowpid', str(xid)])) == pid
    assert INPUT.output(['xdotool', 'getwindowname', str(xid)], text=True).strip() == 'BDK Audio'
    properties = INPUT.output(['xprop', '-id', str(xid), 'WM_CLASS', '_NET_WM_PID'], text=True)
    assert 'com.bdkaudio.bdk_audio' in properties
    return saved


def capture(name):
    assert name and all(character.isalnum() or character in '-_' for character in name)
    saved = identity()
    import gi
    for module in ('Gtk', 'Gdk', 'GdkX11'):
        gi.require_version(module, '3.0')
    from gi.repository import Gtk, Gdk, GdkX11
    Gtk.init([])
    display = Gdk.Display.get_default()
    display.sync()
    window = GdkX11.X11Window.foreign_new_for_display(display, saved['xid'])
    geometry = window.get_geometry()
    image = Gdk.pixbuf_get_from_window(window, 0, 0, geometry.width, geometry.height)
    assert image is not None
    target = QA / (name + '.png')
    assert not target.exists(), 'Preserve every earlier native screenshot'
    image.savev(str(target), 'png', [], [])
    receipt = dict(saved, name=name, captured_unix=time.time(), width=geometry.width, height=geometry.height)
    (QA / (name + '.json')).write_text(json.dumps(receipt, indent=2))
    (QA / 'last-capture.json').write_text(json.dumps(receipt))
    print(json.dumps(receipt))


def require_main_focus(saved):
    focus = INPUT.require_raw_focus(saved['xid'])
    assert focus == saved['xid'], 'Main input refused: another window has focus'
    return focus


if len(sys.argv) > 1:
    INPUT.install_deadline(30)
    os.environ.update(json.loads((QA / 'environment.json').read_text()))
    if sys.argv[1] == 'capture':
        capture(sys.argv[2])
    elif sys.argv[1] in ('click', 'key'):
        saved = identity()
        last = json.loads((QA / 'last-capture.json').read_text())
        assert last['pid'] == saved['pid'] and last['xid'] == saved['xid']
        assert time.time() - last['captured_unix'] < 180, 'Inspect a fresh screenshot before input'
        action = {'action': sys.argv[1]}
        if sys.argv[1] == 'click':
            x, y = map(int, sys.argv[2:4])
            assert 0 <= x < last['width'] and 0 <= y < last['height']
            INPUT.require_input_state(saved['xid'])
            INPUT.run(['xdotool', 'mousemove', '--window', str(saved['xid']), str(x), str(y)], check=True)
            INPUT.require_input_state(saved['xid'])
            # XSendEvent is explicitly scoped to the reviewed app window; no global click.
            INPUT.run(['xdotool', 'click', '--window', str(saved['xid']), '1'], check=True)
            action.update(x=x, y=y)
        else:
            key = sys.argv[2]
            assert key in ('Tab', 'shift+Tab', 'Return'), 'Unreviewed main-window key'
            require_main_focus(saved)
            inventory = INPUT.require_input_state(saved['xid'])
            require_main_focus(saved)
            # XTest routes keyboard events to the exact validated input focus.
            INPUT.run(['xdotool', 'key', key], check=True)
            require_main_focus(saved)
            action.update(key=key, input_method='XTest to exact validated focus')
        with (QA / 'actions.jsonl').open('a') as log:
            log.write(json.dumps(dict(saved, **action, before=last['name'], unix=time.time())) + '\n')
    elif sys.argv[1] == 'finish':
        identity()
        (QA / 'done').write_text('done')
    else:
        raise ValueError('Unknown GUI operation')
    raise SystemExit(0)

QA.mkdir(exist_ok=False)
os.environ.update(XDG_DATA_HOME=str(QA / 'data'), XDG_CONFIG_HOME=str(QA / 'config'),
                  XDG_CACHE_HOME=str(QA / 'cache'), XDG_CURRENT_DESKTOP='GTK')
names = ('DISPLAY', 'XAUTHORITY', 'DBUS_SESSION_BUS_ADDRESS', 'XDG_RUNTIME_DIR',
         'XDG_DATA_HOME', 'XDG_CONFIG_HOME', 'XDG_CACHE_HOME', 'XDG_CURRENT_DESKTOP')
(QA / 'environment.json').write_text(json.dumps({name: os.environ[name] for name in names}, indent=2))
(QA / 'renderer-environment.json').write_text(json.dumps({name: os.environ.get(name) for name in
    ('LIBGL_ALWAYS_SOFTWARE', 'GALLIUM_DRIVER', 'GDK_BACKEND')}, indent=2))
INPUT.run(['dbus-update-activation-environment', *names], check=True)
INPUT.run(['bash', str(BUNDLE / 'register-launcher.sh')], check=True)
desktop = QA / 'data/applications/com.bdkaudio.bdk_audio.desktop'
INPUT.run(['desktop-file-validate', str(desktop)], check=True)
with (QA / 'renderer.txt').open('w') as output:
    INPUT.run(['glxinfo', '-B'], stdout=output, stderr=subprocess.STDOUT, check=True, timeout=60)
import gi
gi.require_version('Gio', '2.0')
from gi.repository import Gio, GLib
app = Gio.DesktopAppInfo.new_from_filename(str(desktop))
assert app is not None
pids = []
assert app.launch_uris_as_manager([], None, GLib.SpawnFlags.DO_NOT_REAP_CHILD, None, None,
                                  lambda _app, pid, _data: pids.append(int(pid)), None)
assert len(pids) == 1
pid = pids[0]
result = {'pid': pid, 'executable': str(EXE), 'stage': 'startup'}
try:
    deadline = time.monotonic() + 240
    while time.monotonic() < deadline:
        child, status = os.waitpid(pid, os.WNOHANG)
        assert not child, 'App exited during startup: %s' % status
        found = INPUT.run(['xdotool', 'search', '--onlyvisible', '--pid', str(pid),
                                '--name', '^BDK Audio$'], capture_output=True, text=True)
        if found.returncode == 0:
            ids = found.stdout.split()
            assert len(ids) == 1
            result.update(xid=int(ids[0]), title='BDK Audio', display=os.environ['DISPLAY'])
            (QA / 'identity.json').write_text(json.dumps(result, indent=2))
            identity()
            break
        time.sleep(2)
    assert 'xid' in result, 'No exact native window before startup deadline'
    capture('startup-first')
    result['stage'] = 'ready'
    (QA / 'ready').write_text('ready')
    deadline = time.monotonic() + 700
    while not (QA / 'done').exists() and time.monotonic() < deadline:
        child, status = os.waitpid(pid, os.WNOHANG)
        assert not child, 'App exited during QA: %s' % status
        time.sleep(1)
    assert (QA / 'done').exists(), 'GUI QA deadline reached'
    result['stage'] = 'qa-ended'
except Exception as error:
    result.update(stage='failed', error=repr(error))
    raise
finally:
    (QA / 'result.json').write_text(json.dumps(result, indent=2))
    try:
        child, status = os.waitpid(pid, os.WNOHANG)
        if not child and pathlib.Path(os.readlink('/proc/%s/exe' % pid)).resolve() == EXE.resolve():
            os.kill(pid, signal.SIGTERM)
            until = time.monotonic() + 10
            while time.monotonic() < until:
                child, status = os.waitpid(pid, os.WNOHANG)
                if child:
                    break
                time.sleep(.1)
            if not child:
                os.kill(pid, signal.SIGKILL)
                child, status = os.waitpid(pid, 0)
            (QA / 'teardown.json').write_text(json.dumps({'pid': pid, 'waitstatus': status}))
    except (ChildProcessError, FileNotFoundError, ProcessLookupError):
        pass
