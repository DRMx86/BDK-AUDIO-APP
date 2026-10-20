#!/usr/bin/env python3
"""Shared raw-focus, complete-window and owned subprocess guards for guest QA."""
import os
import re
import signal
import subprocess
import sys


class HelperDeadlineExpired(TimeoutError):
    pass


def install_deadline(seconds):
    def expired(_signal, _frame):
        # Raising unwinds run() so its active owned child is killed and reaped.
        raise HelperDeadlineExpired('Owned input helper deadline exceeded')
    signal.signal(signal.SIGALRM, expired)
    signal.alarm(seconds)


def run(args, *, timeout=5, check=False, capture_output=False, **kwargs):
    """Each command owns a new process group; every exceptional exit reaps it."""
    assert timeout > 0
    if capture_output:
        assert 'stdout' not in kwargs and 'stderr' not in kwargs
        kwargs.update(stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    process = None
    previous_mask = signal.pthread_sigmask(signal.SIG_BLOCK, {signal.SIGALRM})
    try:
        process = subprocess.Popen(args, start_new_session=True, **kwargs)
    finally:
        # A pending deadline can raise here only after process ownership is set.
        try:
            signal.pthread_sigmask(signal.SIG_SETMASK, previous_mask)
        except BaseException:
            if process is not None:
                _kill_and_reap(process)
            raise
    try:
        stdout, stderr = process.communicate(timeout=timeout)
    except BaseException:
        _kill_and_reap(process)
        raise
    result = subprocess.CompletedProcess(args, process.returncode, stdout, stderr)
    if check and result.returncode:
        raise subprocess.CalledProcessError(result.returncode, args, stdout, stderr)
    return result


def _kill_and_reap(process):
    # The group was created exclusively for this diagnostic command.
    previous_mask = signal.pthread_sigmask(signal.SIG_BLOCK, {signal.SIGALRM})
    try:
        try:
            os.killpg(process.pid, signal.SIGKILL)
        except ProcessLookupError:
            pass
        process.communicate()
    finally:
        signal.pthread_sigmask(signal.SIG_SETMASK, previous_mask)


def output(args, *, timeout=5, **kwargs):
    result = run(args, timeout=timeout, capture_output=True, check=True, **kwargs)
    if result.stderr:
        sys.stderr.write(result.stderr if isinstance(result.stderr, str) else result.stderr.decode(errors='replace'))
    return result.stdout


def raw_focus():
    return int(output(['xdotool', 'getwindowfocus', '-f']))


def require_raw_focus(owned_xid):
    focus = raw_focus()
    assert focus == owned_xid, 'Raw focus belongs to another window; input refused'
    return focus


def observed_hidden_auxiliary(window, owned_xid):
    return (owned_xid == 2097155 and window['xid'] == 2097161
            and window['width'] == 1 and window['height'] == 1
            and window['x'] == -100 and window['y'] == -100
            and window['override_redirect'] == 'yes' and window['properties'].strip() == ''
            and window['unnamed'] and window['xid'] & ~0x1fffff == owned_xid & ~0x1fffff)


def window_inventory(owned_xid):
    tree = output(['xwininfo', '-root', '-children'], text=True)
    children = [int(value, 16) for value in re.findall(r'^\s+(0x[0-9a-fA-F]+)\s', tree, re.MULTILINE)]
    assert children
    windows = []
    for child in children:
        assert child > 0, 'Never invoke interactive xwininfo -id 0'
        details = output(['xwininfo', '-id', str(child)], text=True)
        value = lambda name: int(re.search(r'^\s+' + name + r':\s*(-?\d+)', details, re.MULTILINE).group(1))
        window = {'xid': child, 'details': details,
                  'class': re.search(r'^\s+Class:\s*(\S+)', details, re.MULTILINE).group(1),
                  'map_state': re.search(r'Map State:\s*(\S+)', details).group(1),
                  'x': value('Absolute upper-left X'), 'y': value('Absolute upper-left Y'),
                  'width': value('Width'), 'height': value('Height'),
                  'override_redirect': re.search(r'Override Redirect State:\s*(\S+)', details).group(1),
                  'unnamed': '(has no name)' in details,
                  'properties': output(['xprop', '-id', str(child)], text=True)}
        window['excluded_measured_hidden_auxiliary'] = observed_hidden_auxiliary(window, owned_xid)
        windows.append(window)
    root_details = output(['xwininfo', '-root'], text=True)
    assert re.search(r'Width:\s*1280\b', root_details) and re.search(r'Height:\s*900\b', root_details)
    viewable = [window['xid'] for window in windows
                if window['class'] == 'InputOutput' and window['map_state'] == 'IsViewable'
                and not window['excluded_measured_hidden_auxiliary']]
    return {'tree': tree, 'windows': windows, 'viewport_details': root_details, 'viewable': viewable}


def require_input_state(owned_xid):
    require_raw_focus(owned_xid)
    inventory = window_inventory(owned_xid)
    assert set(inventory['viewable']) == {owned_xid}, 'Another viewable InputOutput window exists; input refused'
    require_raw_focus(owned_xid)
    return inventory
