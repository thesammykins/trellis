#!/usr/bin/env python3
"""Local-only native UI dogfood endpoint. Never forwards context to a provider."""
import http.server
import json

class Fixture(http.server.BaseHTTPRequestHandler):
    def do_POST(self):
        size = int(self.headers.get('Content-Length', '0'))
        if not 0 < size <= 160_000:
            self.send_error(413)
            return
        body = json.loads(self.rfile.read(size))
        if self.headers.get('Authorization') != 'Bearer fixture-only' or body.get('model') != 'trellis-fixture':
            self.send_error(401)
            return
        if body.get('tools') != [] or body.get('store') is not False:
            self.send_error(400)
            return
        prompt = body.get('input') or body.get('messages', [{}])[0].get('content', '')
        if prompt.startswith('Review only the approved project-memory snapshot'):
            output = json.dumps({'proposals': [{'title': 'Fixture: review before applying', 'kind': 'lesson', 'body': 'This localhost fixture confirms Dreaming creates a pending proposal. It is not a real model recommendation.'}]})
        else:
            output = 'Localhost fixture explanation: echo prints the supplied text. This response verifies the native Learning request and display, not model quality.'
        if self.path.endswith('/responses'):
            response = {'status': 'completed', 'output': [{'type': 'message', 'content': [{'type': 'output_text', 'text': output}]}]}
        elif self.path.endswith('/chat/completions'):
            response = {'choices': [{'finish_reason': 'stop', 'message': {'content': output}}]}
        else:
            self.send_error(404)
            return
        data = json.dumps(response).encode()
        self.send_response(200)
        self.send_header('Content-Type', 'application/json')
        self.send_header('Content-Length', str(len(data)))
        self.end_headers()
        self.wfile.write(data)
        print('PASS fixture request ' + self.path, flush=True)
    def log_message(self, *_): pass

server = http.server.ThreadingHTTPServer(('127.0.0.1', 0), Fixture)
print(f'http://127.0.0.1:{server.server_port}/v1', flush=True)
server.serve_forever()
