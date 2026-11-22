"""Exercise the original TUI/Core bridge in isolated named runtimes."""
import argparse
import json
import os
from pathlib import Path
import select
import shutil
import signal
import subprocess
import tempfile
import time
import uuid

parser=argparse.ArgumentParser(description=__doc__)
parser.add_argument('--plugin',required=True)
args=parser.parse_args()
plugin=Path(args.plugin)
with tempfile.TemporaryDirectory(prefix='hb-',dir='/tmp') as tmp:
 root=Path(tmp)
 session='test'+uuid.uuid4().hex[:6]
 env={k:v for k,v in os.environ.items() if not k.startswith(('HC_','HERDR_'))}
 env.update(XDG_CONFIG_HOME=tmp+'/cfg',XDG_STATE_HOME=tmp+'/state',XDG_DATA_HOME=tmp+'/data',XDG_CACHE_HOME=tmp+'/cache',
            HC_SESSION=session,HERDR_SESSION=session,HC_BRIDGE_TUI_SESSION=session,HC_BRIDGE_CORE_LAYOUT='1',
            HC_BRIDGE_STATE_DIR=tmp+'/mapping',HC_BIN_PATH=shutil.which('herdr-core'),HERDR_BIN_PATH=shutil.which('herdr'),
            HC_REAL_SHELL='/bin/sh',HC_SYNC_MS='500',TERM='xterm-256color')
 config=root/'cfg/herdr/config.toml';config.parent.mkdir(parents=True)
 config.write_text('onboarding = false\n[terminal]\ndefault_shell = '+json.dumps(str(plugin/'bin/hc-shell'))+'\n[session]\nresume_agents_on_restore = false\n')
 env['HERDR_CONFIG_PATH']=str(config)
 def run(*argv,**kw):
  r=subprocess.run(argv,env=env,text=True,capture_output=True,timeout=30,**kw)
  assert r.returncode==0,(argv,r.stderr)
  return r.stdout
 def core(method,params):
  reply=json.loads(run('herdr-core','connect',input=json.dumps(dict(jsonrpc='2.0',id=1,method=method,params=params))+'\n'))
  assert 'error' not in reply,reply
  return reply['result']
 def tui(*argv):
  text=run('herdr','--session',session,*argv)
  return json.loads(text)['result'] if text.strip() else {}
 def wait(check,description):
  deadline=time.monotonic()+30
  while time.monotonic()<deadline:
   try:
    v=check()
    if v:return v
   except (OSError,ValueError,AssertionError):pass
   select.select([],[],[],0.1)
  raise AssertionError(description)
 server=None
 try:
  terminals=[]
  for name in ['Fixture Alpha','Fixture Beta']:
   t=core('terminal.run',dict(argv=['/usr/bin/python3','-u','-c',f'print({name!r}); [print("Echo:"+s.strip()) for s in __import__("sys").stdin]'],cwd=tmp,no_parent=True))
   terminals.append(t['address'])
  tabs=[dict(id='tb'+str(i),name=name,root=dict(id='r'+str(i),type='row',children=[dict(id='p'+str(i),type='block',content=dict(terminal=t))])) for i,(name,t) in enumerate(zip(['Alpha','Beta'],terminals))]
  core('doc.set',dict(name='herdr-app',version=0,value=dict(spaces=[dict(id='spfixture',name='Fixture',folder=tmp,tabs=tabs)])))
  run('herdr','plugin','link',str(plugin))
  log=open(root/'server.log','w')
  server=subprocess.Popen(['herdr','--session',session,'server'],env=env,stdout=log,stderr=log,start_new_session=True)
  wait(lambda:tui('workspace','list').get('workspaces'),'TUI startup')
  def mapping():
   return json.loads((root/'mapping/sync-state.json').read_text())
  def mirrored():
   state=mapping()
   return state if all(t in state['panes'] for t in terminals) else None
  state=wait(mirrored,'Core terminals mirrored')
  print('Core terminals mirrored into original TUI: PASS',flush=True)
  pane=state['panes'][terminals[0]]['paneId']
  wait(lambda:'Fixture Alpha' in run('herdr','--session',session,'pane','read',pane,'--source','visible'),'Original output attached')
  tui('pane','run',pane,'FromTUI')
  wait(lambda:'Echo:FromTUI' in run('herdr-core','read',terminals[0]),'Shared terminal input')
  print('TUI input reaches the same Core program: PASS',flush=True)
  saved=core('doc.get',dict(name='herdr-app'))
  saved['value']['spaces'][0]['tabs'][0]['name']='From Core'
  core('doc.set',dict(name='herdr-app',version=saved['version'],value=saved['value']))
  tab=state['tabs']['tb0']['tuiTabId']
  wait(lambda:any(t['tab_id']==tab and t['label']=='From Core' for t in tui('tab','list')['tabs']),'Core rename reaches TUI')
  tui('tab','rename',tab,'From TUI')
  wait(lambda:any(t['tab_id']==tab and t['label']=='From Core' for t in tui('tab','list')['tabs']),'Core name overrides TUI title')
  assert core('doc.get',dict(name='herdr-app'))['value']['spaces'][0]['tabs'][0]['name']=='From Core'
  print('Core-authoritative names resist TUI title changes: PASS',flush=True)
  workspace=state['spaces']['spfixture']
  new=tui('tab','create','--workspace',workspace,'--cwd',tmp,'--no-focus')
  wait(lambda:len(core('doc.get',dict(name='herdr-app'))['value']['spaces'][0]['tabs'])>2,'New TUI tab adopted by Core layout')
  print('Normal new TUI tab appears in desktop layout: PASS',flush=True)
  tui('pane','close',pane)
  wait(lambda:pane not in {p['pane_id'] for p in tui('pane','list')['panes']},'TUI pane closed')
  assert core('terminal.get',dict(terminal=terminals[0]))['state']=='live'
  print('Closing TUI view leaves Core program alive: PASS',flush=True)
 finally:
  try:run('herdr','--session',session,'server','stop')
  except Exception:pass
  pidfile=root/'mapping/sync.pid'
  if pidfile.exists():
   pid=int(pidfile.read_text())
   command=subprocess.run(['ps','-p',str(pid),'-o','command='],capture_output=True,text=True).stdout
   if str(plugin/'bin/sync.js') in command:
    try:os.kill(pid,signal.SIGTERM)
    except ProcessLookupError:pass
  if server:
   try:server.wait(timeout=5)
   except subprocess.TimeoutExpired:server.terminate();server.wait(timeout=5)
  try:run('herdr-core','server','stop')
  except Exception:pass
