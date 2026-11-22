# /// script
# requires-python = ">=3.11"
# dependencies = ["pyte"]
# ///
"""Exercise a Core-native TUI in an isolated fixture, never the default core."""
import argparse
import fcntl
import json
import os
from pathlib import Path
import pty
import select
import struct
import subprocess
import tempfile
import termios
import time
import uuid
import pyte

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--hct', required=True)
parser.add_argument('--launcher', action='store_true', help='Exercise hdr over simulated SSH instead of hct directly')
args = parser.parse_args()
with tempfile.TemporaryDirectory(prefix='hct-', dir='/tmp') as tmp:
    root = Path(tmp)
    env = {k: v for k, v in os.environ.items() if not k.startswith(('HC_', 'HERDR_')) and k not in ('TMUX', 'ZELLIJ', 'STY')}
    env.update(HC_SESSION='smoke-' + uuid.uuid4().hex[:12], TERM='xterm-256color', XDG_CONFIG_HOME=str(root/'config'), XDG_DATA_HOME=str(root/'data'), XDG_STATE_HOME=str(root/'state'), XDG_CACHE_HOME=str(root/'cache'))
    if args.launcher:
        env['SSH_TTY'] = '/dev/fixture'
    def core(*argv, **kw):
        result = subprocess.run(['herdr-core', *argv], env=env, capture_output=True, text=True, timeout=20, **kw)
        assert result.returncode == 0, result.stderr
        return result.stdout
    def rpc(method, params):
        reply = json.loads(core('connect', input=json.dumps(dict(jsonrpc='2.0',id=1,method=method,params=params))+'\n'))
        assert 'error' not in reply, reply
        return reply['result']
    proc = None
    master = None
    try:
        terminals=[]
        for label in ['Fixture Alpha', 'Fixture Beta']:
            result = json.loads(core('run','--bg','--no-parent','--no-notify','--cwd',tmp,'--','/usr/bin/python3','-u','-c',f'print({label!r}); input()'))
            terminals.append(result['address'])
        tabs=[dict(id=f'tab-{i}',name=label,root=dict(id=f'root-{i}',type='row',children=[dict(id=f'pane-{i}',type='block',content=dict(terminal=terminal))])) for i,(label,terminal) in enumerate(zip(['Alpha','Beta'],terminals))]
        doc=dict(spaces=[dict(id='fixture-space',name='Fixture',folder=tmp,tabs=tabs)])
        rpc('doc.set',dict(name='herdr-app',version=0,value=doc))
        master,slave=pty.openpty()
        fcntl.ioctl(slave,termios.TIOCSWINSZ,struct.pack('HHHH',24,60,0,0))
        def setup():
            os.setsid()
            fcntl.ioctl(0,termios.TIOCSCTTY,0)
        proc=subprocess.Popen([args.hct] if args.launcher else [args.hct,'--touch'],env=env,stdin=slave,stdout=slave,stderr=slave,preexec_fn=setup)
        os.close(slave)
        screen=pyte.Screen(60,24)
        stream=pyte.ByteStream(screen)
        def wait_for(text, absent=False):
            deadline=time.monotonic()+12
            while time.monotonic()<deadline:
                if select.select([master],[],[],0.1)[0]:
                    try:
                        chunk=os.read(master,65536)
                    except OSError:
                        break
                    if b"\x1b[6n" in chunk:
                        os.write(master, b"\x1b[1;1R")
                    stream.feed(chunk)
                if (text in '\n'.join(screen.display)) != absent:
                    return
                if proc.poll() is not None:
                    break
            raise AssertionError(f'Missing {text!r}; exit={proc.poll()}\n'+'\n'.join(screen.display))
        wait_for('Fixture Alpha')
        print('Initial existing Core terminal renders: PASS')
        os.write(master,b'\x1b[<0;10;1M\x1b[<0;10;1m')
        wait_for('New Space')
        print('Touch space menu opens: PASS')
        os.write(master,b'\x1b[<0;10;1M\x1b[<0;10;1m')
        wait_for('New Space', absent=True)
        os.write(master,b'\x02n')
        wait_for('Fixture Beta')
        print('Switch while attached: PASS')
        os.write(master,b'\x02w')
        wait_for('Quick Switch')
        print('Session switcher opens while attached: PASS')
        os.write(master,b'Alpha\r')
        wait_for('Fixture Alpha')
        print('Switch back: PASS')
        os.write(master,b'\x02q')
        deadline=time.monotonic()+10
        while proc.poll() is None and time.monotonic()<deadline:
            if select.select([master],[],[],0.1)[0]:
                try:
                    os.read(master,65536)
                except OSError:
                    break
        assert proc.poll()==0, proc.poll()
        rows=json.loads(core('ls'))
        # Detaching must preserve both real fixture processes.
        for terminal in terminals:
            info=json.loads(core('get',terminal))
            assert info['state']=='live', info
        print('Detach preserves running terminals: PASS')
        result=rpc('doc.get',dict(name='herdr-app'))['value']
        assert [t['id'] for t in result['spaces'][0]['tabs']]==['tab-0','tab-1']
        print('Shared desktop tab identities preserved: PASS')
    finally:
        if proc is not None and proc.poll() is None:
            proc.terminate()
            try:
                proc.wait(timeout=2)
            except subprocess.TimeoutExpired:
                proc.kill()
                proc.wait(timeout=2)
        if master is not None:
            os.close(master)
        # This is only the unique, isolated fixture core named above.
        subprocess.run(['herdr-core','server','stop'],env=env,capture_output=True,timeout=20)
