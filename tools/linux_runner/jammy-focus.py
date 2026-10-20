#!/usr/bin/env python3
"""Recover unassigned Xvfb focus only when the owned main window is the sole viewable window."""
import json
import os
import pathlib
import time
import importlib.util
_common_spec = importlib.util.spec_from_file_location('jammy_input_common', pathlib.Path(__file__).with_name('jammy-input-common.py'))
INPUT = importlib.util.module_from_spec(_common_spec)
_common_spec.loader.exec_module(INPUT)


def validate_focus_recovery(raw_focus, viewable_input_output, owned_xid):
    assert raw_focus in (0, 1), 'Focus belongs to a window; recovery refused'
    assert set(viewable_input_output) == {owned_xid}, 'Another viewable window exists; recovery refused'


observed_hidden_auxiliary = INPUT.observed_hidden_auxiliary

def main():
    INPUT.install_deadline(30)
    assert os.getuid() == 1000
    assert pathlib.Path('/.bdk-owned-jammy-root').read_text().strip() == 'jammy-056-20261016'
    qa = pathlib.Path('/home/runner/evidence/gui-softpipe')
    os.environ.update(json.loads((qa / 'environment.json').read_text()))
    saved = json.loads((qa / 'identity.json').read_text())
    pid, xid = saved['pid'], saved['xid']

    def identity():
        assert pathlib.Path(os.readlink('/proc/%s/exe' % pid)).resolve() == pathlib.Path(saved['executable']).resolve()
        assert int(INPUT.output(['xdotool', 'getwindowpid', str(xid)])) == pid
        assert INPUT.output(['xdotool', 'getwindowname', str(xid)], text=True).strip() == 'BDK Audio'
        assert 'com.bdkaudio.bdk_audio' in INPUT.output(['xprop', '-id', str(xid), 'WM_CLASS'], text=True)

    identity()
    last = json.loads((qa / 'last-capture.json').read_text())
    assert last['pid'] == pid and last['xid'] == xid and time.time() - last['captured_unix'] < 180
    raw = int(INPUT.output(['xdotool', 'getwindowfocus', '-f']))
    inventory = INPUT.window_inventory(xid)
    viewable = inventory['viewable']
    receipt = dict(inventory, pid=pid, xid=xid, raw_focus=raw, unix=time.time())
    target = qa / 'focus-recovery2.json'
    assert not target.exists(), 'Preserve prior focus receipt'
    target.write_text(json.dumps(receipt, indent=2))
    validate_focus_recovery(raw, viewable, xid)
    assert int(INPUT.output(['xdotool', 'getwindowfocus', '-f'])) == raw
    identity()
    assert INPUT.window_inventory(xid)['viewable'] == viewable
    assert INPUT.raw_focus() == raw
    INPUT.run(['xdotool', 'windowfocus', '--sync', str(xid)], check=True)
    identity()
    assert int(INPUT.output(['xdotool', 'getwindowfocus', '-f'])) == xid
    print(json.dumps({'focus_recovered': xid, 'sole_viewable_input_output': viewable}))


if __name__ == '__main__':
    main()
