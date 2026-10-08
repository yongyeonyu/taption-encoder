"""App Store Connect helper retained from the verified release workflow.

Usage: python3 Scripts/app_store_connect.py METHOD /v1/PATH INPUT_JSON_OR_- OUTPUT_JSON
Set APP_STORE_CONNECT_ISSUER_ID, APP_STORE_CONNECT_KEY_ID and
APP_STORE_CONNECT_KEY_PATH to override the project's public IDs/key location.
The private key stays outside Git; the JWT is created in memory and never printed.
Use GET for status checks. Any write requires authorization for that operation.
"""

import base64, json, os, subprocess, sys, time, urllib.request, urllib.error
from pathlib import Path

ISSUER = os.environ.get('APP_STORE_CONNECT_ISSUER_ID', '229c124e-7477-462c-b3f0-3180eb81ff25')
KEY_ID = os.environ.get('APP_STORE_CONNECT_KEY_ID', 'AGB82JKGT3')
KEY_PATH = Path(os.environ.get('APP_STORE_CONNECT_KEY_PATH', str(Path.home() / '.appstoreconnect' / 'private_keys' / ('AuthKey_' + KEY_ID + '.p8'))))

def b64(value):
    return base64.urlsafe_b64encode(value).decode().rstrip('=')

def token():
    now = int(time.time())
    head = b64(json.dumps({'alg':'ES256','kid':KEY_ID,'typ':'JWT'},separators=(',',':')).encode())
    body = b64(json.dumps({'iss':ISSUER,'iat':now-20,'exp':now+600,'aud':'appstoreconnect-v1'},separators=(',',':')).encode())
    message = (head + '.' + body).encode()
    der = subprocess.run(['openssl','dgst','-sha256','-sign',str(KEY_PATH)],input=message,capture_output=True,check=True).stdout
    offset = 2 if der[1] < 128 else 2 + (der[1] & 127)
    assert der[offset] == 2
    size = der[offset+1]
    r = int.from_bytes(der[offset+2:offset+2+size],'big')
    offset += 2 + size
    assert der[offset] == 2
    size = der[offset+1]
    s = int.from_bytes(der[offset+2:offset+2+size],'big')
    return message.decode() + '.' + b64(r.to_bytes(32,'big') + s.to_bytes(32,'big'))

def request(method, path, payload=None):
    headers = {'Authorization':'Bearer ' + token(), 'Content-Type':'application/json'}
    data = json.dumps(payload).encode() if payload is not None else None
    req = urllib.request.Request('https://api.appstoreconnect.apple.com' + path, data=data, headers=headers, method=method)
    try:
        with urllib.request.urlopen(req,timeout=60) as result:
            raw = result.read()
            return result.status, json.loads(raw) if raw else {}
    except urllib.error.HTTPError as e:
        raw = e.read()
        return e.code, json.loads(raw) if raw else {}

if __name__ == '__main__':
    method, path, input_path, output_path = sys.argv[1:5]
    payload = json.loads(Path(input_path).read_text()) if input_path != '-' else None
    status, result = request(method,path,payload)
    Path(output_path).write_text(json.dumps({'capturedUTC':time.strftime('%Y-%m-%dT%H:%M:%SZ',time.gmtime()),'status':status,'response':result},indent=2))
    print(json.dumps({'status':status,'saved':output_path,'count':len(result.get('data',[])) if isinstance(result.get('data'),list) else None,'errors':result.get('errors')}))
    if status >= 400: sys.exit(1)
