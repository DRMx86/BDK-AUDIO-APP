#!/usr/bin/env python3
"""Private XTest click only at a freshly inspected point in the exact owned main window."""
import json
import ctypes
import os
import pathlib
import re
import sys
import time
import importlib.util
_common_spec = importlib.util.spec_from_file_location('jammy_input_common', pathlib.Path(__file__).with_name('jammy-input-common.py'))
INPUT = importlib.util.module_from_spec(_common_spec)
_common_spec.loader.exec_module(INPUT)


def require_owned_ancestry(ancestors, owned_xid):
    assert owned_xid in ancestors, 'Pointer belongs to another window; click refused'


def require_pointer_window(window):
    assert window > 0, 'No pointer window; never invoke interactive xwininfo -id 0'


def main():
    INPUT.install_deadline(30)
    assert os.getuid() == 1000 and pathlib.Path('/.bdk-owned-jammy-root').read_text().strip() == 'jammy-056-20261016'
    qa = pathlib.Path('/home/runner/evidence/gui-softpipe')
    os.environ.update(json.loads((qa / 'environment.json').read_text()))
    saved = json.loads((qa / 'identity.json').read_text())
    expected_exe = pathlib.Path('/home/runner/bdk-audio-056-jammy/build/linux/x64/debug/bundle/bdk_audio').resolve()
    assert pathlib.Path(saved['executable']).resolve() == expected_exe
    last = json.loads((qa / 'last-capture.json').read_text())
    pid, xid = saved['pid'], saved['xid']
    x, y = map(int, sys.argv[1:3])
    assert last['pid'] == pid and last['xid'] == xid and time.time() - last['captured_unix'] < 180
    assert 0 <= x < last['width'] and 0 <= y < last['height']
    geometry = INPUT.output(['xwininfo', '-id', str(xid)], text=True)
    assert int(re.search(r'Width:\s*(\d+)', geometry).group(1)) == last['width']
    assert int(re.search(r'Height:\s*(\d+)', geometry).group(1)) == last['height']
    origin_x = int(re.search(r'Absolute upper-left X:\s*(-?\d+)', geometry).group(1))
    origin_y = int(re.search(r'Absolute upper-left Y:\s*(-?\d+)', geometry).group(1))

    def identity():
        assert pathlib.Path(os.readlink('/proc/%s/exe' % pid)).resolve() == expected_exe
        assert int(INPUT.output(['xdotool', 'getwindowpid', str(xid)])) == pid
        assert INPUT.output(['xdotool', 'getwindowname', str(xid)], text=True).strip() == 'BDK Audio'
        assert 'com.bdkaudio.bdk_audio' in INPUT.output(['xprop', '-id', str(xid), 'WM_CLASS'], text=True)
        INPUT.require_input_state(xid)

    def pointer():
        xlib = ctypes.CDLL('libX11.so.6')
        xlib.XOpenDisplay.argtypes = [ctypes.c_char_p]
        xlib.XOpenDisplay.restype = ctypes.c_void_p
        xlib.XDefaultRootWindow.argtypes = [ctypes.c_void_p]
        xlib.XDefaultRootWindow.restype = ctypes.c_ulong
        xlib.XQueryPointer.argtypes = [ctypes.c_void_p, ctypes.c_ulong,
            ctypes.POINTER(ctypes.c_ulong), ctypes.POINTER(ctypes.c_ulong),
            *([ctypes.POINTER(ctypes.c_int)] * 4), ctypes.POINTER(ctypes.c_uint)]
        xlib.XQueryPointer.restype = ctypes.c_int
        xlib.XCloseDisplay.argtypes = [ctypes.c_void_p]
        xlib.XCloseDisplay.restype = ctypes.c_int
        display = xlib.XOpenDisplay(None)
        assert display
        root_return, child_return = ctypes.c_ulong(), ctypes.c_ulong()
        root_x, root_y, win_x, win_y = (ctypes.c_int() for _ in range(4))
        mask = ctypes.c_uint()
        try:
            assert xlib.XQueryPointer(display, xlib.XDefaultRootWindow(display),
                ctypes.byref(root_return), ctypes.byref(child_return),
                ctypes.byref(root_x), ctypes.byref(root_y), ctypes.byref(win_x), ctypes.byref(win_y), ctypes.byref(mask))
        finally:
            xlib.XCloseDisplay(display)
        location = {'X': str(root_x.value), 'Y': str(root_y.value), 'WINDOW': str(child_return.value)}
        assert int(location['X']) == origin_x + x and int(location['Y']) == origin_y + y
        node, ancestors = int(location['WINDOW']), []
        require_pointer_window(node)
        for _ in range(16):
            ancestors.append(node)
            if node == xid:
                break
            tree = INPUT.output(['xwininfo', '-id', str(node), '-tree'], text=True)
            node = int(re.search(r'Parent window id:\s*(0x[0-9a-fA-F]+)', tree).group(1), 16)
            if not node:
                break
        require_owned_ancestry(ancestors, xid)
        return {'location': location, 'ancestors': ancestors}

    identity()
    INPUT.run(['xdotool', 'mousemove', '--window', str(xid), str(x), str(y)], check=True)
    before = pointer()
    identity()
    assert pointer() == before, 'Pointer changed before click'
    INPUT.run(['xdotool', 'click', '--clearmodifiers', '1'], check=True)
    with (qa / 'pointer-actions.jsonl').open('a') as output:
        output.write(json.dumps(dict(saved, x=x, y=y, target=before, before=last['name'], unix=time.time())) + '\n')


if __name__ == '__main__':
    main()
