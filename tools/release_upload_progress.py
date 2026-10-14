"""GitHub draft asset upload with byte progress; credentials stay in memory."""
import http.client,json,ssl,subprocess,time
from urllib.parse import urlsplit,quote

def upload(assets,repo,tag,env):
    def api(path):
        return json.loads(subprocess.check_output(['gh','api',path],env=env,text=True,encoding='utf-8'))
    release=api(f'repos/{repo}/releases/tags/{tag}')
    if not release['draft']:raise RuntimeError('Refusing to replace public release attachments.')
    token=env.get('GH_TOKEN') or env.get('GITHUB_TOKEN')
    if not token:token=subprocess.check_output(['gh','auth','token'],env=env,text=True).strip()
    endpoint=release['upload_url'].split('{',1)[0]
    if urlsplit(endpoint).hostname!='uploads.github.com':raise RuntimeError('Unexpected upload host.')
    remote={a['name']:a for a in release['assets']}
    import sys
    sys.path.insert(0,str(__import__('pathlib').Path(__file__).resolve().parent.parent/'launcher'))
    import core
    for index,file in enumerate(assets,1):
        digest='sha256:'+core.sha(file)
        previous=remote.get(file.name)
        if previous and previous.get('state')=='uploaded' and previous.get('digest')==digest and previous['size']==file.stat().st_size:
            print(f'[{index}/{len(assets)}] Already verified: {file.name}',flush=True);continue
        if previous:
            subprocess.run(['gh','api','--method','DELETE',f"repos/{repo}/releases/assets/{previous['id']}"],env=env,check=True,capture_output=True)
        url=urlsplit(endpoint+'?name='+quote(file.name))
        conn=http.client.HTTPSConnection(url.hostname,timeout=30,context=ssl.create_default_context())
        size=file.stat().st_size;sent=0;start=time.monotonic();last=0
        print(f'[{index}/{len(assets)}] Upload: {file.name}',flush=True)
        try:
            conn.putrequest('POST',url.path+'?'+url.query)
            conn.putheader('Authorization','Bearer '+token)
            conn.putheader('User-Agent','Swamphen-VTT-Release')
            conn.putheader('Accept','application/vnd.github+json')
            conn.putheader('Content-Type','application/octet-stream')
            conn.putheader('Content-Length',str(size));conn.endheaders()
            with file.open('rb') as stream:
                for block in iter(lambda:stream.read(128*1024),b''):
                    conn.send(block);sent+=len(block);now=time.monotonic()
                    if now-last>=0.2 or sent==size:
                        seconds=max(now-start,0.001);speed=sent/seconds;fraction=sent/size
                        bar='#'*int(fraction*30)+'-'*(30-int(fraction*30))
                        eta=(size-sent)/max(speed,1)
                        print(f'\r[{bar}] {fraction*100:5.1f}% {sent/1048576:.2f}/{size/1048576:.2f} MiB  {speed/1048576:.2f} MiB/s  ETA {eta:.0f}s   ',end='',flush=True);last=now
            print('\nSent; waiting for GitHub verification...',flush=True)
            response=conn.getresponse();body=response.read()
            if response.status!=201:raise RuntimeError('GitHub upload failed: HTTP '+str(response.status))
            result=json.loads(body)
            if result.get('state')!='uploaded' or result['size']!=size or result.get('digest')!=digest:
                raise RuntimeError('GitHub asset digest/size mismatch: '+file.name)
            print(f'Verified: {file.name} ({time.monotonic()-start:.1f}s)',flush=True)
        finally:conn.close()
