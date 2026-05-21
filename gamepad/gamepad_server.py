#!/usr/bin/env python3
import asyncio
import json
import evdev
from evdev import UInput, AbsInfo, ecodes as e
import websockets
from http.server import HTTPServer, BaseHTTPRequestHandler
import threading

cap = {
    e.EV_KEY: [
        e.BTN_SOUTH, e.BTN_EAST, e.BTN_NORTH, e.BTN_WEST,
        e.BTN_TL, e.BTN_TR, e.BTN_SELECT, e.BTN_START,
        e.BTN_DPAD_UP, e.BTN_DPAD_DOWN, e.BTN_DPAD_LEFT, e.BTN_DPAD_RIGHT,
    ],
    e.EV_ABS: [
        (e.ABS_X,  AbsInfo(0, -32768, 32767, 16, 128, 0)),
        (e.ABS_Y,  AbsInfo(0, -32768, 32767, 16, 128, 0)),
    ],
}

BUTTON_MAP = {
    'a':      e.BTN_SOUTH,
    'b':      e.BTN_EAST,
    'x':      e.BTN_NORTH,
    'y':      e.BTN_WEST,
    'l':      e.BTN_TL,
    'r':      e.BTN_TR,
    'select': e.BTN_SELECT,
    'start':  e.BTN_START,
    'up':     e.BTN_DPAD_UP,
    'down':   e.BTN_DPAD_DOWN,
    'left':   e.BTN_DPAD_LEFT,
    'right':  e.BTN_DPAD_RIGHT,
}

ui = UInput(cap, name='WebGamepad', version=0x3)

async def handler(ws):
    async for msg in ws:
        try:
            data = json.loads(msg)
            btn = data.get('btn')
            pressed = int(data.get('pressed', 0))
            if btn in BUTTON_MAP:
                ui.write(e.EV_KEY, BUTTON_MAP[btn], pressed)
                ui.syn()
        except Exception:
            pass

HTML = open('/opt/gamepad.html').read()

class HTMLHandler(BaseHTTPRequestHandler):
    def do_GET(self):
        self.send_response(200)
        self.send_header('Content-Type', 'text/html; charset=utf-8')
        self.end_headers()
        self.wfile.write(HTML.encode())
    def log_message(self, *a): pass

def serve_http():
    HTTPServer(('0.0.0.0', 8080), HTMLHandler).serve_forever()

async def main():
    threading.Thread(target=serve_http, daemon=True).start()
    print('Web controller ready: http://192.168.2.147:8080')
    async with websockets.serve(handler, '0.0.0.0', 8765):
        await asyncio.Future()

asyncio.run(main())
