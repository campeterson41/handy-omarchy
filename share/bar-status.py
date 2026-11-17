#!/usr/bin/python3
"""Expose Handy's actual recording state and live microphone amplitude to the bar."""
import array,json,math,os,queue,select,signal,subprocess,threading,time
from pathlib import Path
root=Path(os.environ['XDG_RUNTIME_DIR']);state_file=root/'handy-bar.json'
events=queue.Queue();stopping=False;mic=None;phase='idle';stage='idle';phase_at=time.time();last_emit=0;levels=[0.0]*7

def logs():
 global journal
 journal=subprocess.Popen(['/usr/bin/journalctl','--user','-u','handy.service','-f','-n','0','-o','cat'],stdout=subprocess.PIPE,text=True)
 for line in journal.stdout:events.put(line)
def stop(*_):
 global stopping
 stopping=True
def stop_mic():
 global mic
 if mic is not None:
  mic.terminate()
  try:mic.wait(timeout=1)
  except subprocess.TimeoutExpired:mic.kill();mic.wait()
  mic=None
def start_mic():
 global mic
 stop_mic()
 # Match Handy's active capture source, including an explicitly selected mic.
 source='@DEFAULT_SOURCE@'
 try:
  pid=subprocess.check_output(['/usr/bin/systemctl','--user','show','handy','-p','MainPID','--value'],text=True).strip()
  outputs=json.loads(subprocess.check_output(['/usr/bin/pactl','-f','json','list','source-outputs']))
  own=next(x for x in outputs if x.get('properties',{}).get('application.name')=='cpal-pulseaudio-'+pid)
  if own['source']!=4294967295:source=str(own['source'])
 except Exception:pass
 mic=subprocess.Popen(['/usr/bin/parec','--device='+source,'--format=float32le','--rate=16000','--channels=1','--raw','--latency-msec=50'],stdout=subprocess.PIPE,stderr=subprocess.DEVNULL)
def write():
 obj={'phase':phase,'stage':stage if phase=='processing' else phase,'levels':levels,'at':time.time()}
 tmp=state_file.with_suffix('.tmp');tmp.write_text(json.dumps(obj));tmp.replace(state_file)

signal.signal(signal.SIGTERM,stop);signal.signal(signal.SIGINT,stop)
journal=None
threading.Thread(target=logs,daemon=True).start()
try:
 while not stopping:
  while True:
   try:line=events.get_nowait()
   except queue.Empty:break
   if 'Microphone stream initialized' in line:
    if phase!='recording':phase='recording';phase_at=time.time();write();last_emit=time.time();start_mic()
   elif 'recording stopped after' in line:
    phase='processing';stage='transcribing';phase_at=time.time();levels=[0.0]*7;write();last_emit=time.time();stop_mic()
   elif any(x in line for x in ('Failed to paste transcription','Transcription operation cancelled','Stopped Handy local','Stopping Handy local')):
    phase='idle';stop_mic();levels=[0.0]*7
  if phase=='recording' and mic is not None:
   if select.select([mic.stdout],[],[],.06)[0]:
    data=os.read(mic.stdout.fileno(),3200)
    if data:
     values=array.array('f');values.frombytes(data[:len(data)//4*4]);part=max(1,len(values)//7)
     levels=[min(1.0,math.sqrt(sum(v*v for v in values[i*part:(i+1)*part])/part)*12) for i in range(7)]
    elif mic.poll() is not None:stop_mic()
  else:time.sleep(.06)
  if phase=='processing':
   try:
    update=json.loads((root/'handy-cleanup-stage.json').read_text())
    if update.get('at',0)>phase_at and update.get('stage') in ('cleanup','pasting'):stage=update['stage']
   except Exception:pass
   try:done=json.loads((root/'handy-last-paste.json').read_text()).get('at',0)>phase_at
   except Exception:done=False
   if done or time.time()-phase_at>35:phase='idle'
  now=time.time()
  if now-last_emit>(.08 if phase in ('recording','processing') else .5):write();last_emit=now
finally:
 stop_mic()
 if journal is not None:
  journal.terminate()
  try:journal.wait(timeout=1)
  except subprocess.TimeoutExpired:journal.kill()
 phase='idle';levels=[0.0]*7;write()
