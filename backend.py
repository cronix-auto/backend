import sys, os, asyncio, re, time, zlib, contextlib, json, datetime, traceback
import aiohttp
import websockets
from websockets.exceptions import ConnectionClosed, ConnectionClosedOK, ConnectionClosedError

try:
    if sys.platform != 'win32':
        import uvloop; uvloop.install()
except Exception:
    pass

# ========= resource helper (loads from folder or PyInstaller bundle) =========
def res_path(name: str) -> str:
    base = getattr(sys, "_MEIPASS", os.path.dirname(__file__))
    return os.path.join(base, name)

# ========= regex & helpers =========
PLAYER_RE       = re.compile(r'(\d+)/8')
NUM_RE          = re.compile(r'(\d+(?:\.\d+)?)')
CODEFENCE_RE    = re.compile(r'```(?:\w+)?\s*([\s\S]*?)```')
GUID_RE         = re.compile(r'([0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12})')
PLACEID_RE      = re.compile(r'(?:games|place|places)/(\d+)')
PLACE_FIELD_RE  = re.compile(r'\bplace(?:\s*id)?\b', re.I)
TOKENLIKE_RE    = re.compile(r'^[A-Za-z0-9:_-]{32,256}$')
BOLD_RE         = re.compile(r'\*\*(.*?)\*\*')
ITALIC_RE       = re.compile(r'\*(.*?)\*')
CLEAN_TABLE     = str.maketrans('', '', ''.join(['\u200b','\u200c','\u200d','\ufeff']))
ZLIB_FLUSH      = b'\x00\x00\xff\xff'

def strip_md(s: str) -> str:
    if not s: return ''
    s = BOLD_RE.sub(r'\1', s)
    s = ITALIC_RE.sub(r'\1', s)
    return s.replace('*','').strip()

def clean_job_id(raw: str) -> str:
    if not raw: return ''
    s = CODEFENCE_RE.sub(r'\1', str(raw)).replace('`','')
    s = s.translate(CLEAN_TABLE).strip("\"' \t\r\n")
    s = re.sub(r'^[\[(<{\s]+', '', s)
    s = re.sub(r'[\])}>\s]+$', '', s)
    s = re.sub(r'\s+', '', s)
    s = re.sub(r'^[^A-Za-z0-9]+', '', s)
    s = re.sub(r'[^A-Za-z0-9:_-]+$', '', s)
    m = GUID_RE.search(s)
    return (m.group(1).lower() if m else s)

def extract_value(fields, name):
    ln = (name or '').lower()
    for f in fields or []:
        n = (f.get('name') or '')
        if ln in n.lower(): return f.get('value','')
    return ''

def pick_place_id(fields, join_script_raw, default_place):
    for f in (fields or []):
        n = (f.get('name') or ''); v = (f.get('value') or '')
        if PLACE_FIELD_RE.search(n):
            m = re.search(r'\d+', v or '')
            if m:
                try: return int(m.group(0))
                except: pass
    for f in (fields or []):
        v = (f.get('value') or '')
        m = PLACEID_RE.search(v)
        if m:
            try: return int(m.group(1))
            except: pass
    if join_script_raw:
        m = PLACEID_RE.search(join_script_raw)
        if m:
            try: return int(m.group(1))
            except: pass
    try: return int(default_place)
    except: return default_place

def iso_to_epoch(ts):
    try:
        if ts and ts.endswith('Z'): ts = ts[:-1] + '+00:00'
        return datetime.datetime.fromisoformat(ts).timestamp()
    except Exception:
        return time.time()

def parse_money_m(value: str) -> float:
    """Parse money strings like '25M', '0.8M', '800K', '1200000' -> return in millions."""
    if not value: return 0.0
    s = strip_md(value).upper()
    m = NUM_RE.search(s)
    if not m: return 0.0
    num = float(m.group(1))
    if 'M' in s:
        return num
    if 'K' in s:
        return num / 1000.0
    return num / 1_000_000.0

# ========= sniper =========
class CronixSniper:
    def __init__(self, ui_logger, ui_status=None, *,
                 token:str = None,
                 use_bot_token:bool=False,
                 channel_ids=None,
                 place_id:int=109983668079237,
                 local_ws_host:str='127.0.0.1',
                 local_ws_port:int=8765,
                 api_base:str='https://discord.com/api/v10',
                 min_money_m: float = 0.0):
        self.token = token or os.getenv('DISCORD_TOKEN') or ''
        self.use_bot_token = use_bot_token
        self.channel_ids = [str(x) for x in (channel_ids or ['1401775181025775738'])]
        self.place_id = place_id
        self.local_ws_host = local_ws_host
        self.local_ws_port = int(local_ws_port)
        self.api = api_base

        self._running = False
        self._tasks: list[asyncio.Task] = []
        self._local_ws_server = None
        self.LOCAL_WS_CLIENT = None
        self.last_job_hash = None
        self.LATEST = {"job_id": None, "ts": None}
        self._ui_logger = ui_logger
        self._ui_status = ui_status

        self.PRIORITY_CFG = {'1401775181025775738': {'sleep': 0.25, 'burst': 2, 'jitter_ms': 11}}
        self.DEFAULT_SLEEP = 0.85
        self.DEFAULT_BURST = 1

        self.min_money_m = float(min_money_m)

    def set_min_money(self, m: float):
        self.min_money_m = max(0.0, float(m))

    def _ui_line(self, fields, money_str):
        name = strip_md(
            extract_value(fields, 'Name') or
            extract_value(fields, 'Server') or
            extract_value(fields, 'Title') or
            extract_value(fields, 'Lobby') or
            'Unknown'
        )
        clean_money = strip_md(money_str or '')
        return f"<b style='color:#ff3141'>{name}</b> <span style='color:#ffb4bc'>- {clean_money}/s</span>"

    def log(self, msg:str):
        try:
            self._ui_logger(msg)
        except Exception:
            print(msg)

    def status(self, **kw):
        if not self._ui_status: return
        try:
            self._ui_status(kw)
        except Exception:
            pass

    async def push_local(self, payload: str):
        ws = self.LOCAL_WS_CLIENT
        if not ws: return
        try:
            await ws.send(payload)
        except (ConnectionClosed, ConnectionClosedOK, ConnectionClosedError, Exception):
            self.LOCAL_WS_CLIENT = None
            self.status(ws='down')

    def _maybe_emit_snipe(self, cleaned_id: str, money_txt: str, players_txt: str, msg_ts: float, join_script_raw: str, fields):
        money_m = parse_money_m(money_txt or '')
        if money_m < self.min_money_m:
            return

        job_hash = f"{cleaned_id}|{msg_ts:.2f}"
        if job_hash == self.last_job_hash:
            return
        self.last_job_hash = job_hash
        self.LATEST["job_id"] = cleaned_id; self.LATEST["ts"] = time.time()

        self.log(self._ui_line(fields, money_txt or ''))
        self.status(last='ok')

        asyncio.create_task(self.push_local(cleaned_id))

        players_disp = players_txt or '0/8'
        place = pick_place_id(fields, join_script_raw, self.place_id)
        print(f"[SNIPED] {money_txt or ''} | {players_disp} | {cleaned_id} | place={place} | minM={self.min_money_m}")

    def try_snipe_from_fields(self, fields, msg_ts):
        if not fields: return

        cleaned = ''
        players_txt = None
        money_txt = None
        join_script_raw = ''
        cand_vals_local = []

        for f in fields:
            n = (f.get('name') or '')
            v = (f.get('value') or '')
            ln = n.lower()

            if players_txt is None and 'players' in ln: players_txt = v
            if money_txt   is None and 'money per sec' in ln: money_txt = v

            if 'job id (pc)' in ln or ln == 'job id' or 'job id (mobile)' in ln or 'join script' in ln:
                if not join_script_raw and 'join script' in ln: join_script_raw = v
                m = GUID_RE.search(v or '')
                if m:
                    cleaned = m.group(1).lower()
                    self._maybe_emit_snipe(cleaned, money_txt, players_txt, msg_ts, join_script_raw, fields)
                    return
                else:
                    cand_vals_local.append(v)

        for blob in cand_vals_local:
            if not blob: continue
            s = blob.translate(CLEAN_TABLE).strip("\"' \t\r\n`")
            s = re.sub(r'[<>\[\](){}\s]', '', s)
            if TOKENLIKE_RE.match(s) and not GUID_RE.match(s):
                cleaned = s
                break
        if not cleaned: return

        self._maybe_emit_snipe(cleaned, money_txt, players_txt, msg_ts, join_script_raw, fields)

    async def rest_tail_loop(self):
        headers = {"Authorization": (f"Bot {self.token}" if self.use_bot_token else self.token),
                   "User-Agent": "CronixLocal/1.1"}
        seen_ids, timeout = set(), aiohttp.ClientTimeout(total=15)
        async with aiohttp.ClientSession(timeout=timeout) as session:
            while self._running:
                try:
                    for cid in self.channel_ids:
                        cfg = self.PRIORITY_CFG.get(str(cid), {})
                        sleep_s = float(cfg.get('sleep', self.DEFAULT_SLEEP)); burst = int(cfg.get('burst', self.DEFAULT_BURST))
                        for _ in range(max(1, burst)):
                            async with session.get(f"{self.api}/channels/{cid}/messages?limit=10", headers=headers) as resp:
                                if resp.status != 200:
                                    await asyncio.sleep(sleep_s * 2); break
                                msgs = await resp.json()
                            for m in msgs:
                                mid = m.get('id')
                                if not mid or mid in seen_ids: continue
                                seen_ids.add(mid)
                                ts = iso_to_epoch(m.get('timestamp'))
                                for e in (m.get('embeds') or []):
                                    fields = e.get('fields') or []
                                    if fields: self.try_snipe_from_fields(fields, ts)
                            await asyncio.sleep(0.02)
                        await asyncio.sleep(sleep_s + (cfg.get('jitter_ms', 0) / 1000.0))
                    await asyncio.sleep(0.05)
                except Exception as ex:
                    self.log(f"[REST] error: {ex}")
                    self.status(rest='down')
                    await asyncio.sleep(1.0)

    async def discord_gateway_loop(self):
        if not self.token:
            raise RuntimeError("Empty TOKEN. Enter your token in the GUI or set DISCORD_TOKEN.")
        url = "wss://gateway.discord.gg/?v=10&encoding=json&compress=zlib-stream"
        intents = (1 << 0) | (1 << 9) | (1 << 15)
        headers = {"Authorization": (f"Bot {self.token}" if self.use_bot_token else self.token),
                   "User-Agent": "CronixLocal/1.1"}
        pending_rest_fetch = {}

        async with aiohttp.ClientSession(headers=headers) as session:
            while self._running:
                try:
                    async with session.ws_connect(url, heartbeat=None, autoping=True, max_msg_size=0) as ws:
                        self.log("Discord GW connected")
                        self.status(gw='ok')
                        hb_interval, stopped, z, buf, seq, session_id = None, False, zlib.decompressobj(), bytearray(), None, None

                        async def heartbeat():
                            while not stopped and self._running:
                                if hb_interval is None:
                                    await asyncio.sleep(0.05); continue
                                await ws.send_str(json.dumps({"op": 1, "d": seq if seq is not None else None}))
                                await asyncio.sleep(hb_interval)

                        async def fetch_message_once(cid, mid):
                            key = f"{cid}:{mid}"
                            if pending_rest_fetch.get(key): return
                            pending_rest_fetch[key] = True
                            await asyncio.sleep(0.6)
                            try:
                                async with session.get(f"{self.api}/channels/{cid}/messages/{mid}") as resp:
                                    if resp.status == 200:
                                        m = await resp.json()
                                        embeds = m.get("embeds") or []
                                        if embeds:
                                            fields = (embeds[0] or {}).get("fields") or []
                                            if fields: self.try_snipe_from_fields(fields, time.time())
                            except Exception:
                                pass
                            finally:
                                pending_rest_fetch.pop(key, None)

                        hb = asyncio.create_task(heartbeat())
                        try:
                            async for msg in ws:
                                if not self._running: break
                                if msg.type == aiohttp.WSMsgType.BINARY:
                                    buf.extend(msg.data)
                                    if len(buf) >= 4 and buf[-4:] == ZLIB_FLUSH:
                                        try:
                                            payload = json.loads(z.decompress(bytes(buf)).decode('utf-8')); buf.clear()
                                        except Exception as e:
                                            self.log(f"decompress/parse err: {e}"); continue
                                    else: continue
                                elif msg.type == aiohttp.WSMsgType.TEXT:
                                    try: payload = json.loads(msg.data)
                                    except Exception: continue
                                else: continue

                                if payload.get("s") is not None: seq = payload["s"]
                                op = payload.get("op"); t = payload.get("t"); d = payload.get("d")

                                if op == 10:
                                    hb_interval = (d["heartbeat_interval"] / 1000.0)
                                    if session_id:
                                        await ws.send_str(json.dumps({"op": 6, "d": {"token": self.token, "session_id": session_id, "seq": seq}}))
                                    else:
                                        await ws.send_str(json.dumps({"op": 2, "d": {"token": self.token, "intents": intents,
                                                                                          "properties": {"$os":"windows","$browser":"cronix-local","$device":"cronix-local"}}}))
                                    continue
                                if op == 7: break
                                if op == 9: session_id = None; await asyncio.sleep(1.0); break
                                if t == "READY": session_id = d.get("session_id")

                                if t in ("MESSAGE_CREATE","MESSAGE_UPDATE"):
                                    cid = str(d.get("channel_id") or "")
                                    if cid not in self.channel_ids: continue
                                    mid = str(d.get("id") or "")
                                    embeds = d.get("embeds") or []
                                    if embeds:
                                        for e in embeds:
                                            fields = (e or {}).get("fields") or []
                                            if fields: self.try_snipe_from_fields(fields, time.time())
                                    elif mid:
                                        asyncio.create_task(fetch_message_once(cid, mid))
                        finally:
                            stopped = True; hb.cancel()
                            with contextlib.suppress(Exception): await hb
                except Exception as e:
                    self.log(f"⚠️ GW error: {e}")
                    self.status(gw='down')
                    await asyncio.sleep(1.0)

    async def start_local_ws(self):
        async def handler(ws):
            if self.LOCAL_WS_CLIENT is None:
                self.LOCAL_WS_CLIENT = ws; self.log(f"[LOCAL WS] ready at ws://{self.local_ws_host}:{self.local_ws_port} (Lua connected)")
                self.status(ws='ok')
            else:
                try: await ws.close()
                finally: return
            try:
                async for _ in ws: pass
            except (ConnectionClosed, ConnectionClosedOK, ConnectionClosedError):
                pass
            finally:
                if self.LOCAL_WS_CLIENT is ws:
                    self.LOCAL_WS_CLIENT = None; self.log("[LOCAL WS] Lua disconnected")
                    self.status(ws='down')
        srv = await websockets.serve(handler, self.local_ws_host, self.local_ws_port,
                                     ping_interval=20, ping_timeout=20,
                                     max_size=None, compression=None)
        self.log(f"[LOCAL WS] listening on ws://{self.local_ws_host}:{self.local_ws_port}")
        self._local_ws_server = srv
        return srv

    async def start(self):
        if self._running: return
        self._running = True
        await self.start_local_ws()
        self._tasks = [
            asyncio.create_task(self.discord_gateway_loop(), name='gw'),
            asyncio.create_task(self.rest_tail_loop(), name='rest'),
        ]
        self.log("Started")
        self.status(app='running')

    async def stop(self):
        if not self._running: return
        self._running = False
        for t in list(self._tasks):
            t.cancel()
        for t in list(self._tasks):
            with contextlib.suppress(asyncio.CancelledError):
                await t
        self._tasks.clear()
        if self._local_ws_server:
            self._local_ws_server.close()
            with contextlib.suppress(Exception):
                await self._local_ws_server.wait_closed()
        self._local_ws_server = None
        self.LOCAL_WS_CLIENT = None
        self.log("Stopped")
        self.status(app='stopped', gw='down', rest='down', ws='down')


# ========= Qt GUI =========
from PySide6 import QtCore, QtWidgets, QtGui

class LogSignal(QtCore.QObject):
    line = QtCore.Signal(str)

class StatusSignal(QtCore.QObject):
    update = QtCore.Signal(dict)

class AsyncWorker(QtCore.QThread):
    def __init__(self):
        super().__init__()
        self.loop = None

    def run(self):
        self.loop = asyncio.new_event_loop()
        asyncio.set_event_loop(self.loop)
        try:
            self.loop.run_forever()
        finally:
            pending = asyncio.all_tasks(self.loop)
            for t in pending:
                t.cancel()
            with contextlib.suppress(Exception):
                self.loop.run_until_complete(asyncio.gather(*pending, return_exceptions=True))
            self.loop.close()

    def call_soon_threadsafe(self, coro):
        if not self.loop:
            return
        return asyncio.run_coroutine_threadsafe(coro, self.loop)

class Badge(QtWidgets.QLabel):
    def __init__(self, text, tooltip):
        super().__init__(text)
        self.setToolTip(tooltip)
        self.setObjectName('badge')
        self.setAlignment(QtCore.Qt.AlignCenter)
        self.setFixedHeight(22)
        self.setMinimumWidth(52)
        self._apply_shadow()

    def set_state(self, ok: bool | None):
        if ok is None:
            self.setProperty('state', 'idle')
        else:
            self.setProperty('state', 'ok' if ok else 'down')
        self.style().unpolish(self); self.style().polish(self)

    def _apply_shadow(self):
        eff = QtWidgets.QGraphicsDropShadowEffect()
        eff.setBlurRadius(24)
        eff.setOffset(0, 2)
        eff.setColor(QtGui.QColor(0, 0, 0, 120))
        self.setGraphicsEffect(eff)

class Divider(QtWidgets.QFrame):
    def __init__(self):
        super().__init__()
        self.setObjectName('sep')
        self.setFrameShape(QtWidgets.QFrame.HLine)
        self.setFrameShadow(QtWidgets.QFrame.Plain)
        self.setFixedHeight(10)

class CronixWindow(QtWidgets.QMainWindow):
    MAX_LINES = 800

    def __init__(self):
        super().__init__()
        self.setWindowTitle("CRONIX")
        self.setMinimumSize(820, 520)
        self.setStyleSheet(self._style())
        self.setWindowIcon(self._icon())

        self.settings = QtCore.QSettings('Cronix', 'CronixGUI')

        central = QtWidgets.QWidget(); self.setCentralWidget(central)
        layout = QtWidgets.QVBoxLayout(central)
        layout.setContentsMargins(16, 14, 16, 14)
        layout.setSpacing(10)

        header = QtWidgets.QHBoxLayout(); header.setSpacing(8)
        title = QtWidgets.QLabel("CRONIX"); title.setObjectName("title")
        subtitle = QtWidgets.QLabel("Made by: Zenyical"); subtitle.setObjectName("subtitle")
        ttl = QtWidgets.QVBoxLayout(); ttl.setSpacing(0); ttl.addWidget(title); ttl.addWidget(subtitle)
        header.addLayout(ttl, 1)

        self.badge_gw = Badge("GW", "Discord Gateway")
        self.badge_rest = Badge("REST", "Discord REST poller")
        self.badge_ws = Badge("WS", "Local Lua WebSocket")
        for b in (self.badge_gw, self.badge_rest, self.badge_ws):
            b.set_state(None); header.addWidget(b)

        layout.addLayout(header)
        layout.addWidget(Divider())

        # --- token row + remember toggle ---
        form = QtWidgets.QHBoxLayout(); form.setSpacing(8)
        lbl = QtWidgets.QLabel("Token")
        self.token_edit = QtWidgets.QLineEdit()
        self.token_edit.setEchoMode(QtWidgets.QLineEdit.Password)
        self.token_edit.setPlaceholderText("Discord token…")
        saved_token = self.settings.value('token', '', type=str)
        env_token = os.getenv('DISCORD_TOKEN','')
        self.token_edit.setText(saved_token or env_token)
        self._apply_shadow(self.token_edit)
        eye = QtWidgets.QToolButton(); eye.setCheckable(True); eye.setObjectName('eye')
        eye.setToolTip("Show/Hide token")
        eye.clicked.connect(self._toggle_token)
        self.remember_chk = QtWidgets.QCheckBox("Remember token")
        self.remember_chk.setChecked(bool(saved_token))
        form.addWidget(lbl)
        form.addWidget(self.token_edit, 1)
        form.addWidget(eye)
        form.addWidget(self.remember_chk)
        layout.addLayout(form)

        # --- minimum money filter row (pretty pill) ---
        filterRow = QtWidgets.QHBoxLayout(); filterRow.setSpacing(8)

        self.filterCard = QtWidgets.QFrame()
        self.filterCard.setObjectName("filterCard")
        self.filterCard.setMinimumHeight(44)
        cardLay = QtWidgets.QHBoxLayout(self.filterCard)
        cardLay.setContentsMargins(12, 6, 12, 6)
        cardLay.setSpacing(10)

        minTitle = QtWidgets.QLabel("Min M/s")
        minTitle.setObjectName("filterTitle")

        self.min_spin = QtWidgets.QDoubleSpinBox()
        self.min_spin.setObjectName("minSpin")
        self.min_spin.setDecimals(2)  # <-- fixed indent
        self.min_spin.setRange(0.00, 9999.0)
        self.min_spin.setSingleStep(0.25)
        self.min_spin.setPrefix("")
        self.min_spin.setSuffix(" M/s")
        self.min_spin.setButtonSymbols(QtWidgets.QAbstractSpinBox.NoButtons)
        self.min_spin.setAlignment(QtCore.Qt.AlignCenter)
        saved_min = self.settings.value('min_money_m', 20.0, type=float)
        self.min_spin.setValue(max(20.0, float(saved_min)))  # clamp to 20+

        # presets (removed 0 and 10)
        def preset_btn(text, val):
            b = QtWidgets.QPushButton(text)
            b.setProperty("preset", True)
            b.setCursor(QtGui.QCursor(QtCore.Qt.PointingHandCursor))
            b.clicked.connect(lambda: self.min_spin.setValue(float(val)))
            return b

        presets = QtWidgets.QHBoxLayout(); presets.setSpacing(6)
        for label, val in [("20M", 20), ("50M", 50), ("100M", 100)]:
            presets.addWidget(preset_btn(label, val))

        cardLay.addWidget(minTitle)
        cardLay.addWidget(self.min_spin, 0)
        cardLay.addStretch(1)
        cardLay.addLayout(presets)

        filterRow.addWidget(self.filterCard)
        layout.addLayout(filterRow)

        layout.addWidget(Divider())

        controls = QtWidgets.QHBoxLayout(); controls.setSpacing(8)
        self.start_btn = QtWidgets.QPushButton("Start")
        self.stop_btn = QtWidgets.QPushButton("Stop"); self.stop_btn.setEnabled(False)
        self.clear_btn = QtWidgets.QPushButton("Clear Log")
        for btn in (self.start_btn, self.stop_btn, self.clear_btn):
            self._apply_shadow(btn)
        controls.addWidget(self.start_btn); controls.addWidget(self.stop_btn); controls.addStretch(1); controls.addWidget(self.clear_btn)
        layout.addLayout(controls)

        layout.addWidget(Divider())

        self.output = QtWidgets.QTextEdit(); self.output.setReadOnly(True); self.output.setObjectName("console")
        self.output.setPlaceholderText("Output…")
        self._apply_shadow(self.output, blur=28, y=4, alpha=140)
        layout.addWidget(self.output, 1)

        self.sniper: CronixSniper | None = None
        self.logger = LogSignal(); self.logger.line.connect(self._append_log)
        self.status_sig = StatusSignal(); self.status_sig.update.connect(self._apply_status)
        self.worker = AsyncWorker(); self.worker.start()

        self.start_btn.clicked.connect(self.on_start)
        self.stop_btn.clicked.connect(self.on_stop)
        self.clear_btn.clicked.connect(self._clear_log)
        self.min_spin.valueChanged.connect(self._on_min_changed)

        QtGui.QShortcut(QtGui.QKeySequence("Ctrl+L"), self, activated=self._clear_log)
        QtGui.QShortcut(QtGui.QKeySequence("Ctrl+R"), self, activated=self._restart_if_running)

        self.restoreGeometry(self.settings.value('geometry', b''))
        self.restoreState(self.settings.value('state', b''))

    def _icon(self):
        # Try Cronix logo .ico first
        ico = QtGui.QIcon(res_path("cronixlogo.ico"))
        if not ico.isNull():
            return ico
        # Fallback: draw a simple red check icon
        pm = QtGui.QPixmap(32,32); pm.fill(QtCore.Qt.transparent)
        p = QtGui.QPainter(pm)
        p.setRenderHint(QtGui.QPainter.Antialiasing)
        path = QtGui.QPainterPath(); path.addRoundedRect(2,2,28,28,6,6)
        p.fillPath(path, QtGui.QColor('#ff3141'))
        p.setPen(QtGui.QPen(QtGui.QColor('#0a0a0c'), 3))
        p.drawLine(8,16,16,24); p.drawLine(16,24,26,10)
        p.end()
        return QtGui.QIcon(pm)

    def _style(self):
        return """
        * { font-family: Inter, 'Segoe UI', Roboto, Arial; font-size: 12.5px; }
        /* slightly brighter base using a soft vignette */
        QMainWindow {
          background: qradialgradient(cx:0.5, cy:0.2, radius:1.0,
                       fx:0.5, fy:0.2, stop:0 #0d0a0b, stop:1 #100a0c);
        }

        /* headings */
        QLabel#title { color: #ffeef0; font-size: 23px; font-weight: 900; letter-spacing: .8px; }
        QLabel#subtitle { color: #ffb0b9; font-size: 10.5px; margin-top: -2px; }

        /* dividers a touch brighter */
        QFrame#sep { background: transparent; border: 0; border-top: 1px dashed #5a1a22; margin: 2px 0; }

        /* inputs */
        QLineEdit, QDoubleSpinBox#minSpin {
          background: #1a0f12;
          color: #ffe5e8;
          border: 1px solid #5a1a22;
          border-radius: 10px;
          padding: 7px 10px;
          selection-background-color: #ff4153;
          selection-color: #ffffff;
        }
        QLineEdit:focus, QDoubleSpinBox#minSpin:focus { border-color: #ff4153; }

        /* console */
        QTextEdit#console {
          background: #130c0e;
          color: #fff0f2;
          border: 1px solid #4b1820;
          border-radius: 12px;
          padding: 10px 12px;
          font-family: 'JetBrains Mono', Consolas, monospace;
          font-size: 12px;
          selection-background-color: #ff4153;
          selection-color: #ffffff;
        }

        /* buttons */
        QPushButton {
          background: qlineargradient(x1:0, y1:0, x2:0, y2:1, stop:0 #211115, stop:1 #1a0d10);
          color: #ffecf0;
          border: 1px solid #5a1a22;
          padding: 8px 13px;
          border-radius: 12px;
          font-weight: 800;
        }
        QPushButton:hover { border-color: #ff4153; }
        QPushButton:pressed { background: #261117; }
        QPushButton:disabled { color: #a6757d; border-color: #3a1218; }

        /* eye button */
        QToolButton#eye {
          background: #1a0d10;
          border: 1px solid #5a1a22;
          border-radius: 9px;
          padding: 0 8px;
          color: #ffdfe3;
        }
        QToolButton#eye:hover { border-color: #ff4153; }

        /* status badges */
        QLabel#badge { padding: 0 8px; font-weight: 800; }
        QLabel#badge[state="idle"] {
          background: #150b0d; color: #e6a7af; border: 1px solid #40131a; border-radius: 999px;
        }
        QLabel#badge[state="ok"] {
          background: #122016; color: #d2ffd9; border: 1px solid #2e6b3a; border-radius: 999px;
        }
        QLabel#badge[state="down"] {
          background: #2a0f12; color: #ffc0c8; border: 1px solid #6a1f2a; border-radius: 999px;
        }

        QStatusBar { color: #ffc0c8; background: transparent; border-top: 1px solid #3e141b; }

        /* filter card */
        QFrame#filterCard {
          background: #160c0f;
          border: 1px solid #5a1a22;
          border-radius: 12px;
        }
        QLabel#filterTitle { color: #ffc0c8; font-weight: 900; letter-spacing: .35px; }
        QDoubleSpinBox#minSpin { min-width: 120px; }

        /* preset chips */
        QPushButton[preset="true"] {
          background: #1e1013;
          color: #ffe3e7;
          border: 1px solid #5a1a22;
          border-radius: 10px;
          padding: 6px 10px;
          font-weight: 800;
        }
        QPushButton[preset="true"]:hover { border-color: #ff4153; }
        QPushButton[preset="true"]:pressed { background: #261217; }

        /* scrollbars */
        QScrollBar:vertical, QScrollBar:horizontal {
          background: #12090c;
          border: 1px solid #3a1218;
          border-radius: 8px;
          margin: 4px;
        }
        QScrollBar::handle:vertical, QScrollBar::handle:horizontal {
          background: #3a151c;
          border-radius: 8px;
          min-height: 24px; min-width: 24px;
        }
        QScrollBar::handle:hover { background: #4a1a22; }
        QScrollBar::add-line, QScrollBar::sub-line { background: transparent; border: 0; height: 0; width: 0; }
        """

    def _toggle_token(self, checked):
        self.token_edit.setEchoMode(QtWidgets.QLineEdit.Normal if checked else QtWidgets.QLineEdit.Password)

    def _apply_shadow(self, widget: QtWidgets.QWidget, *, blur=22, x=0, y=2, alpha=110):
        eff = QtWidgets.QGraphicsDropShadowEffect()
        eff.setBlurRadius(blur)
        eff.setOffset(x, y)
        eff.setColor(QtGui.QColor(0, 0, 0, alpha))
        widget.setGraphicsEffect(eff)

    def _append_log(self, line:str):
        ts = datetime.datetime.now().strftime('%H:%M:%S')
        self.output.append(f"<span style='color:#7a5156'>[{ts}]</span> {line}")
        doc = self.output.document()
        if doc.blockCount() > self.MAX_LINES * 2:
            self.output.clear()
        elif doc.blockCount() > self.MAX_LINES:
            cursor = self.output.textCursor()
            cursor.movePosition(QtGui.QTextCursor.Start)
            for _ in range(doc.blockCount() - self.MAX_LINES):
                cursor.select(QtGui.QTextCursor.LineUnderCursor)
                cursor.removeSelectedText()
                cursor.deleteChar()

    def log(self, line:str):
        self.logger.line.emit(line)

    def _apply_status(self, data: dict):
        if 'gw' in data:
            self.badge_gw.set_state(data['gw'] == 'ok')
        if 'rest' in data:
            self.badge_rest.set_state(data['rest'] == 'ok')
        if 'ws' in data:
            self.badge_ws.set_state(data['ws'] == 'ok')

    def _clear_log(self):
        self.output.clear()

    def _restart_if_running(self):
        if self.sniper:
            self.on_stop(); self.on_start()

    def _on_min_changed(self, val: float):
        self.settings.setValue('min_money_m', float(val))
        if self.sniper:
            self.sniper.set_min_money(float(val))

    def on_start(self):
        if self.sniper:
            return
        token = self.token_edit.text().strip()
        if not token or len(token) < 16:
            QtWidgets.QMessageBox.critical(self, "Missing token",
                "Please enter your Discord token. The guide is pinned in the Cronix Discord in #obtain-your-token.")
            return
        if self.remember_chk.isChecked():
            self.settings.setValue('token', token)
        else:
            self.settings.remove('token')

        min_m = float(self.min_spin.value())
        self.sniper = CronixSniper(self.log, self.status_sig.update.emit, token=token, use_bot_token=False, min_money_m=min_m)
        self.worker.call_soon_threadsafe(self.sniper.start())
        self.start_btn.setEnabled(False)
        self.stop_btn.setEnabled(True)
        self.badge_rest.set_state(None)

    def on_stop(self):
        if not self.sniper:
            return
        self.worker.call_soon_threadsafe(self.sniper.stop())
        self.sniper = None
        self.start_btn.setEnabled(True)
        self.stop_btn.setEnabled(False)

    def closeEvent(self, ev: QtGui.QCloseEvent):
        try:
            self.settings.setValue('geometry', self.saveGeometry())
            self.settings.setValue('state', self.saveState())
            if self.sniper:
                self.worker.call_soon_threadsafe(self.sniper.stop())
        finally:
            super().closeEvent(ev)

def main():
    try:
        QtWidgets.QApplication.setAttribute(QtCore.Qt.AA_EnableHighDpiScaling, True)
        app = QtWidgets.QApplication(sys.argv)
        app.setApplicationName("Cronix")
        # App-level icon (taskbar/dock)
        app.setWindowIcon(QtGui.QIcon(res_path("cronixlogo.ico")))
        if sys.platform == "win32":
            try:
                import ctypes
                ctypes.windll.shell32.SetCurrentProcessExplicitAppUserModelID("Cronix.CronixGUI")
            except Exception:
                pass
        w = CronixWindow(); w.show()
        ret = app.exec()
        return ret
    except Exception as e:
        err = traceback.format_exc()
        try:
            with open("cronix_error.log", "w", encoding="utf-8") as f:
                f.write(err)
        except Exception:
            pass
        try:
            QtWidgets.QMessageBox.critical(None, "Cronix crashed", f"Startup error:\n{e}\n\nFull trace saved to cronix_error.log")
        except Exception:
            pass
        print(err)
        return 1

if __name__ == '__main__':
    try:
        sys.exit(main())
    except KeyboardInterrupt:
        pass
