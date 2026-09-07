#!/usr/bin/env python3
import http.server
import json
from pathlib import Path
import subprocess
import threading

root = Path(__file__).resolve().parents[1]
requests = []
class Fixture(http.server.BaseHTTPRequestHandler):
    def do_POST(self):
        data = json.loads(self.rfile.read(int(self.headers['Content-Length'])))
        assert self.headers['Authorization'] == 'Bearer fixture-only'
        assert data['tools'] == [] and data['store'] is False and data['stream'] is False
        assert data['model'] == 'fixture'
        requests.append(self.path)
        if '/redirect/' in self.path:
            self.send_response(302)
            self.send_header('Location', '/should-not-be-called')
            self.end_headers()
            return
        if self.path.endswith('/responses'):
            assert data['input'] == 'fixture context' and data['max_output_tokens'] == 128
            result = {'status':'completed','output':[{'type':'message','content':[{'type':'output_text','text':'Fixture response'}]}]}
        else:
            assert data['messages'][0]['content'] == 'fixture context' and data['max_completion_tokens'] == 128
            result = {'choices':[{'finish_reason':'stop','message':{'content':'Fixture response'}}]}
        body = json.dumps(result).encode()
        self.send_response(200)
        self.send_header('Content-Type','application/json')
        self.send_header('Content-Length', str(len(body)))
        self.end_headers()
        self.wfile.write(body)
    def log_message(self, *args): pass

binary = root / '.build-support/check-direct-http'
subprocess.run(['xcrun','swiftc','-swift-version','6','Trellis/DirectModelClient.swift','Checks/DirectModelHTTPCheck.swift','-o',str(binary)],cwd=root,check=True)
server = http.server.ThreadingHTTPServer(('127.0.0.1',0),Fixture)
threading.Thread(target=server.serve_forever,daemon=True).start()
try:
    subprocess.run([str(binary),f'http://127.0.0.1:{server.server_port}/v1'],check=True,timeout=20)
    assert requests == ['/v1/responses','/v1/chat/completions','/v1/redirect/responses']
finally:
    server.shutdown()
