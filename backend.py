import asyncio
import contextlib
import datetime
import json
import os
import re
import sys
import time
import traceback
import zlib
from collections import deque
from dataclasses import dataclass
from typing import Callable, Deque, Iterable, Optional

import aiohttp
import websockets
from websockets.exceptions import ConnectionClosed, ConnectionClosedError, ConnectionClosedOK

try:
    if sys.platform != "win32":
        import uvloop  # type: ignore

        uvloop.install()
except Exception:
    pass


# ========= resource helper (loads from folder or PyInstaller bundle) =========
def res_path(name: str) -> str:
    base = getattr(sys, "_MEIPASS", os.path.dirname(__file__))
    return os.path.join(base, name)


# ========= regex & helpers =========
PLAYER_RE = re.compile(r"(\d+)/8")
NUM_RE = re.compile(r"(\d+(?:\.\d+)?)")
CODEFENCE_RE = re.compile(r"```(?:\w+)?\s*([\s\S]*?)```")
GUID_RE = re.compile(r"([0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12})")
PLACEID_RE = re.compile(r"(?:games|place|places)/(\d+)")
PLACE_FIELD_RE = re.compile(r"\bplace(?:\s*id)?\b", re.I)
TOKENLIKE_RE = re.compile(r"^[A-Za-z0-9:_-]{32,256}$")
BOLD_RE = re.compile(r"\*\*(.*?)\*\*")
ITALIC_RE = re.compile(r"\*(.*?)\*")
CLEAN_TABLE = str.maketrans("", "", "".join(["\u200b", "\u200c", "\u200d", "\ufeff"]))
ZLIB_FLUSH = b"\x00\x00\xff\xff"
MONEY_CANDIDATE_RE = re.compile(r"\$?\s*\d+(?:\.\d+)?\s*(?:M|K)(?:/?S(?:/?S)?)?", re.IGNORECASE)


def strip_md(s: str) -> str:
    if not s:
        return ""
    s = BOLD_RE.sub(r"\1", s)
    s = ITALIC_RE.sub(r"\1", s)
    return s.replace("*", "").strip()


def clean_job_id(raw: str) -> str:
    if not raw:
        return ""
    s = CODEFENCE_RE.sub(r"\1", str(raw)).replace("`", "")
    s = s.translate(CLEAN_TABLE).strip("\"' \t\r\n")
    s = re.sub(r"^[\[(<{\s]+", "", s)
    s = re.sub(r"[\])}>\s]+$", "", s)
    s = re.sub(r"\s+", "", s)
    s = re.sub(r"^[^A-Za-z0-9]+", "", s)
    s = re.sub(r"[^A-Za-z0-9:_-]+$", "", s)
    m = GUID_RE.search(s)
    return m.group(1).lower() if m else s


def extract_value(fields: Iterable[dict], name: str) -> str:
    target = (name or "").lower()
    for field in fields or []:
        label = (field.get("name") or "").lower()
        if target in label:
            return field.get("value", "")
    return ""


def pick_place_id(fields, join_script_raw, default_place):
    for field in fields or []:
        name = field.get("name") or ""
        value = field.get("value") or ""
        if PLACE_FIELD_RE.search(name):
            match = re.search(r"\d+", value or "")
            if match:
                try:
                    return int(match.group(0))
                except Exception:
                    pass
    for field in fields or []:
        value = field.get("value") or ""
        match = PLACEID_RE.search(value)
        if match:
            try:
                return int(match.group(1))
            except Exception:
                pass
    if join_script_raw:
        match = PLACEID_RE.search(join_script_raw)
        if match:
            try:
                return int(match.group(1))
            except Exception:
                pass
    try:
        return int(default_place)
    except Exception:
        return default_place


def iso_to_epoch(ts: Optional[str]) -> float:
    try:
        if ts and ts.endswith("Z"):
            ts = ts[:-1] + "+00:00"
        return datetime.datetime.fromisoformat(ts).timestamp()
    except Exception:
        return time.time()


def parse_money_m(value: str) -> float:
    """Parse money strings like '25M', '0.8M', '800K', '1200000' -> millions."""
    if not value:
        return 0.0
    text = strip_md(value).upper()
    match = NUM_RE.search(text)
    if not match:
        return 0.0
    num = float(match.group(1))
    if "M" in text:
        return num
    if "K" in text:
        return num / 1000.0
    return num / 1_000_000.0


def pick_job_id_from_sources(sources: Iterable[str]) -> tuple[str, str]:
    for raw in sources:
        if not raw:
            continue
        cleaned = clean_job_id(raw)
        if not cleaned:
            continue
        if GUID_RE.match(cleaned) or TOKENLIKE_RE.match(cleaned):
            return cleaned.lower(), raw
    return "", ""


def pick_money_from_sources(sources: Iterable[str]) -> str:
    for raw in sources:
        if not raw:
            continue
        text = strip_md(raw)
        if not text:
            continue
        if MONEY_CANDIDATE_RE.search(text) and parse_money_m(text) > 0:
            return raw
    return ""


def pick_players_from_sources(sources: Iterable[str]) -> str:
    for raw in sources:
        if not raw:
            continue
        match = PLAYER_RE.search(strip_md(raw))
        if match:
            return match.group(0)
    return ""


@dataclass(slots=True)
class BrainrotRecord:
    name: str
    money: str
    players: str
    job_id: str
    place_id: int
    captured_at: float

    def display(self) -> str:
        players = self.players or "0/8"
        clean_name = strip_md(self.name or "Unknown") or "Unknown"
        return f"{clean_name} | {self.money} | {players} | {self.job_id} | place={self.place_id}"


class GatewayZlibStream:
    """Minimal zlib-stream helper for Discord gateway payloads."""

    def __init__(self, logger: Callable[[str], None]):
        self._inflator = zlib.decompressobj()
        self._buffer = bytearray()
        self._log = logger

    def reset(self) -> None:
        self._inflator = zlib.decompressobj()
        self._buffer.clear()

    def feed(self, chunk: bytes) -> Optional[dict]:
        self._buffer.extend(chunk)
        if len(self._buffer) < 4 or self._buffer[-4:] != ZLIB_FLUSH:
            return None
        try:
            raw = self._inflator.decompress(bytes(self._buffer))
        except Exception as exc:
            self._log(f"decompress err: {exc}")
            self.reset()
            return None
        finally:
            self._buffer.clear()
        try:
            return json.loads(raw.decode("utf-8"))
        except Exception as exc:
            self._log(f"payload parse err: {exc}")
            return None


# ========= sniper =========
class CronixSniper:
    MAX_BRAINROT_HISTORY = 75

    def __init__(
        self,
        ui_logger,
        ui_status=None,
        *,
        token: str | None = None,
        use_bot_token: bool = False,
        channel_ids=None,
        place_id: int = 109983668079237,
        local_ws_host: str = "127.0.0.1",
        local_ws_port: int = 8765,
        min_money_m: float = 0.0,
    ) -> None:
        self.token = token or os.getenv("DISCORD_TOKEN") or ""
        self.use_bot_token = use_bot_token
        self.channel_ids = [str(x) for x in (channel_ids or ["1401775181025775738"])]
        self.place_id = place_id
        self.local_ws_host = local_ws_host
        self.local_ws_port = int(local_ws_port)

        self._running = False
        self._tasks: list[asyncio.Task] = []
        self._local_ws_server = None
        self.LOCAL_WS_CLIENT = None
        self._ui_logger = ui_logger
        self._ui_status = ui_status

        self.min_money_m = float(min_money_m)
        self.recent_brainrots: Deque[BrainrotRecord] = deque(maxlen=self.MAX_BRAINROT_HISTORY)
        self._brainrot_hashes: Deque[str] = deque(maxlen=512)

    # ---- UI helpers -------------------------------------------------
    def set_min_money(self, m: float) -> None:
        self.min_money_m = max(0.0, float(m))

    def _ui_line(self, *, name: str, money: str) -> str:
        clean_name = strip_md(name or "Unknown") or "Unknown"
        clean_money = strip_md(money or "") or ""
        suffix = "" if clean_money.lower().endswith("/s") else "/s"
        return (
            f"<b style='color:#ff3141'>{clean_name}</b> "
            f"<span style='color:#ffb4bc'>- {clean_money}{suffix}</span>"
        )

    def log(self, msg: str) -> None:
        try:
            self._ui_logger(msg)
        except Exception:
            print(msg)

    def status(self, **kw) -> None:
        if not self._ui_status:
            return
        try:
            self._ui_status(kw)
        except Exception:
            pass

    async def push_local(self, payload: str) -> None:
        ws = self.LOCAL_WS_CLIENT
        if not ws:
            return
        try:
            await ws.send(payload)
        except (ConnectionClosed, ConnectionClosedOK, ConnectionClosedError, Exception):
            self.LOCAL_WS_CLIENT = None
            self.status(ws="down")

    # ---- sniping ----------------------------------------------------
    def _emit_brainrot(
        self,
        *,
        cleaned_id: str,
        money_txt: str,
        players_txt: str,
        msg_ts: float,
        join_script_raw: str,
        name_txt: str,
        fields,
    ) -> None:
        money_m = parse_money_m(money_txt or "")
        if money_m < self.min_money_m:
            return

        job_hash = f"{cleaned_id}|{msg_ts:.2f}"
        if job_hash in self._brainrot_hashes:
            return
        self._brainrot_hashes.append(job_hash)

        place = pick_place_id(fields, join_script_raw, self.place_id)
        record = BrainrotRecord(
            name_txt or "Unknown",
            money_txt or "",
            players_txt or "0/8",
            cleaned_id,
            place,
            time.time(),
        )
        self.recent_brainrots.append(record)

        self.log(self._ui_line(name=name_txt, money=money_txt or ""))
        history = list(self.recent_brainrots)[-5:]
        if history:
            self.log(
                "<span style='color:#f8c2ca'>Recent brainrots:</span> "
                + "; ".join(r.display() for r in history)
            )
        self.status(last="ok", speed="ok")

        asyncio.create_task(self.push_local(cleaned_id))

        print(f"[SNIPED] {record.display()} | minM={self.min_money_m}")
        print("[BRAINROT LIST]", "; ".join(r.display() for r in self.recent_brainrots))

    def _collect_name(self, fields, *, embed_title: str, embed_author: str, content: str) -> str:
        candidates = [
            extract_value(fields, "Name"),
            extract_value(fields, "Server"),
            extract_value(fields, "Title"),
            extract_value(fields, "Lobby"),
            embed_title,
            embed_author,
            content.splitlines()[0] if content else "",
        ]
        for candidate in candidates:
            clean = strip_md(candidate or "")
            if clean:
                return clean
        return "Unknown"

    def _process_embed(self, embed: dict, *, content: str, msg_ts: float) -> bool:
        embed = embed or {}
        fields = embed.get("fields") or []
        description = embed.get("description") or ""
        title = embed.get("title") or ""
        footer_text = ((embed.get("footer") or {}).get("text")) or ""
        author_name = ((embed.get("author") or {}).get("name")) or ""

        prioritized_job_sources: list[str] = []
        for field in fields:
            value = field.get("value") or ""
            if not value:
                continue
            label = (field.get("name") or "").lower()
            if any(key in label for key in ("job", "join", "server", "id")):
                prioritized_job_sources.insert(0, value)
            else:
                prioritized_job_sources.append(value)

        job_sources = prioritized_job_sources + [description, footer_text, content, title, author_name]
        job_id, join_source = pick_job_id_from_sources(job_sources)
        if not job_id:
            return False

        money_sources: list[str] = []
        for field in fields:
            value = field.get("value") or ""
            label = (field.get("name") or "").lower()
            if any(key in label for key in ("money", "cash", "earn", "profit", "m/s", "per sec")):
                money_sources.insert(0, value)
            else:
                money_sources.append(value)
        money_sources.extend([description, footer_text, content, title])
        if join_source:
            money_sources.append(join_source)
        money_txt = pick_money_from_sources(money_sources)
        if not money_txt:
            return False

        players_sources: list[str] = []
        for field in fields:
            value = field.get("value") or ""
            label = (field.get("name") or "").lower()
            if "player" in label or "slot" in label:
                players_sources.insert(0, value)
            else:
                players_sources.append(value)
        players_sources.extend([description, footer_text, content])
        players_txt = pick_players_from_sources(players_sources)

        name_txt = self._collect_name(fields, embed_title=title, embed_author=author_name, content=content)
        self._emit_brainrot(
            cleaned_id=job_id,
            money_txt=money_txt,
            players_txt=players_txt or "",
            msg_ts=msg_ts,
            join_script_raw=join_source,
            name_txt=name_txt,
            fields=fields,
        )
        return True

    def _process_plaintext(self, content: str, *, msg_ts: float) -> bool:
        if not content:
            return False
        job_id, join_source = pick_job_id_from_sources([content])
        if not job_id:
            return False
        money_txt = pick_money_from_sources([content])
        if not money_txt:
            return False
        players_txt = pick_players_from_sources([content])
        name_txt = strip_md(content.splitlines()[0] if content else "") or "Unknown"
        self._emit_brainrot(
            cleaned_id=job_id,
            money_txt=money_txt,
            players_txt=players_txt,
            msg_ts=msg_ts,
            join_script_raw=join_source or content,
            name_txt=name_txt,
            fields=[],
        )
        return True

    def _handle_message_payload(self, payload: dict) -> None:
        cid = str(payload.get("channel_id") or "")
        if cid not in self.channel_ids:
            return

        ts = payload.get("timestamp") or payload.get("edited_timestamp")
        msg_ts = iso_to_epoch(ts) if ts else time.time()
        content = payload.get("content") or ""
        embeds = payload.get("embeds") or []

        handled = False
        for embed in embeds:
            if self._process_embed(embed or {}, content=content, msg_ts=msg_ts):
                handled = True

        if not handled and content:
            self._process_plaintext(content, msg_ts=msg_ts)

    # ---- discord gateway loop --------------------------------------
    async def discord_gateway_loop(self) -> None:
        if not self.token:
            raise RuntimeError("Empty TOKEN. Enter your token in the GUI or set DISCORD_TOKEN.")

        url = "wss://gateway.discord.gg/?v=10&encoding=json&compress=zlib-stream"
        intents = (1 << 0) | (1 << 9) | (1 << 15)
        headers = {
            "Authorization": f"Bot {self.token}" if self.use_bot_token else self.token,
            "User-Agent": "CronixLocal/1.1",
        }

        async with aiohttp.ClientSession(headers=headers) as session:
            while self._running:
                try:
                    async with session.ws_connect(
                        url,
                        heartbeat=None,
                        autoping=True,
                        max_msg_size=0,
                    ) as ws:
                        self.log("Discord GW connected")
                        self.status(gw="ok")

                        hb_interval = None
                        stopped = False
                        seq = None
                        session_id = None
                        zstream = GatewayZlibStream(self.log)

                        async def heartbeat() -> None:
                            while not stopped and self._running:
                                if hb_interval is None:
                                    await asyncio.sleep(0.05)
                                    continue
                                payload = json.dumps({"op": 1, "d": seq if seq is not None else None})
                                await ws.send_str(payload)
                                await asyncio.sleep(hb_interval)

                        hb_task = asyncio.create_task(heartbeat())
                        try:
                            async for msg in ws:
                                if not self._running:
                                    break
                                payload = None
                                if msg.type == aiohttp.WSMsgType.BINARY:
                                    payload = zstream.feed(msg.data)
                                    if payload is None:
                                        continue
                                elif msg.type == aiohttp.WSMsgType.TEXT:
                                    try:
                                        payload = json.loads(msg.data)
                                    except Exception:
                                        continue
                                else:
                                    continue

                                if payload is None:
                                    continue

                                if payload.get("s") is not None:
                                    seq = payload["s"]

                                op = payload.get("op")
                                t = payload.get("t")
                                d = payload.get("d") or {}

                                if op == 10:
                                    hb_interval = d["heartbeat_interval"] / 1000.0
                                    identify = {
                                        "token": self.token,
                                        "intents": intents,
                                        "properties": {
                                            "$os": "windows",
                                            "$browser": "cronix-local",
                                            "$device": "cronix-local",
                                        },
                                    }
                                    if session_id:
                                        await ws.send_str(
                                            json.dumps(
                                                {
                                                    "op": 6,
                                                    "d": {
                                                        "token": self.token,
                                                        "session_id": session_id,
                                                        "seq": seq,
                                                    },
                                                }
                                            )
                                        )
                                    else:
                                        await ws.send_str(json.dumps({"op": 2, "d": identify}))
                                    continue

                                if op == 7:
                                    break
                                if op == 9:
                                    session_id = None
                                    await asyncio.sleep(1.0)
                                    break
                                if t == "READY":
                                    session_id = d.get("session_id")
                                    continue

                                if t in {"MESSAGE_CREATE", "MESSAGE_UPDATE"}:
                                    self._handle_message_payload(d)
                        finally:
                            stopped = True
                            hb_task.cancel()
                            with contextlib.suppress(Exception):
                                await hb_task
                except Exception as exc:
                    self.log(f"⚠️ GW error: {exc}")
                    self.status(gw="down", speed="down")
                    await asyncio.sleep(1.0)

    # ---- local websocket -------------------------------------------
    async def start_local_ws(self):
        async def handler(ws):
            if self.LOCAL_WS_CLIENT is None:
                self.LOCAL_WS_CLIENT = ws
                self.log(
                    f"[LOCAL WS] ready at ws://{self.local_ws_host}:{self.local_ws_port} (Lua connected)"
                )
                self.status(ws="ok")
            else:
                with contextlib.suppress(Exception):
                    await ws.close()
                return
            try:
                async for _ in ws:
                    pass
            except (ConnectionClosed, ConnectionClosedOK, ConnectionClosedError):
                pass
            finally:
                if self.LOCAL_WS_CLIENT is ws:
                    self.LOCAL_WS_CLIENT = None
                    self.log("[LOCAL WS] Lua disconnected")
                    self.status(ws="down")

        server = await websockets.serve(
            handler,
            self.local_ws_host,
            self.local_ws_port,
            ping_interval=20,
            ping_timeout=20,
            max_size=None,
            compression=None,
        )
        self.log(f"[LOCAL WS] listening on ws://{self.local_ws_host}:{self.local_ws_port}")
        self._local_ws_server = server
        return server

    # ---- lifecycle --------------------------------------------------
    async def start(self) -> None:
        if self._running:
            return
        self._running = True
        await self.start_local_ws()
        self._tasks = [asyncio.create_task(self.discord_gateway_loop(), name="gw")]
        self.log("Started")
        self.status(app="running", speed="ok")

    async def stop(self) -> None:
        if not self._running:
            return
        self._running = False
        for task in list(self._tasks):
            task.cancel()
        for task in list(self._tasks):
            with contextlib.suppress(asyncio.CancelledError):
                await task
        self._tasks.clear()
        if self._local_ws_server:
            self._local_ws_server.close()
            with contextlib.suppress(Exception):
                await self._local_ws_server.wait_closed()
        self._local_ws_server = None
        self.LOCAL_WS_CLIENT = None
        self.log("Stopped")
        self.status(app="stopped", gw="down", speed="down", ws="down")


# ========= Qt GUI =========
from PySide6 import QtCore, QtGui, QtWidgets


class LogSignal(QtCore.QObject):
    line = QtCore.Signal(str)


class StatusSignal(QtCore.QObject):
    update = QtCore.Signal(dict)


class AsyncWorker(QtCore.QThread):
    def __init__(self):
        super().__init__()
        self.loop: Optional[asyncio.AbstractEventLoop] = None

    def run(self) -> None:
        self.loop = asyncio.new_event_loop()
        asyncio.set_event_loop(self.loop)
        try:
            self.loop.run_forever()
        finally:
            pending = asyncio.all_tasks(self.loop)
            for task in pending:
                task.cancel()
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
        self.setObjectName("badge")
        self.setAlignment(QtCore.Qt.AlignCenter)
        self.setFixedHeight(22)
        self.setMinimumWidth(52)
        self._apply_shadow()

    def set_state(self, ok: Optional[bool]):
        if ok is None:
            self.setProperty("state", "idle")
        else:
            self.setProperty("state", "ok" if ok else "down")
        self.style().unpolish(self)
        self.style().polish(self)

    def _apply_shadow(self) -> None:
        eff = QtWidgets.QGraphicsDropShadowEffect()
        eff.setBlurRadius(24)
        eff.setOffset(0, 2)
        eff.setColor(QtGui.QColor(0, 0, 0, 120))
        self.setGraphicsEffect(eff)


class Divider(QtWidgets.QFrame):
    def __init__(self):
        super().__init__()
        self.setObjectName("sep")
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

        self.settings = QtCore.QSettings("Cronix", "CronixGUI")

        central = QtWidgets.QWidget()
        self.setCentralWidget(central)
        layout = QtWidgets.QVBoxLayout(central)
        layout.setContentsMargins(16, 14, 16, 14)
        layout.setSpacing(10)

        header = QtWidgets.QHBoxLayout()
        header.setSpacing(8)
        title = QtWidgets.QLabel("CRONIX")
        title.setObjectName("title")
        subtitle = QtWidgets.QLabel("Made by: Zenyical")
        subtitle.setObjectName("subtitle")
        ttl = QtWidgets.QVBoxLayout()
        ttl.setSpacing(0)
        ttl.addWidget(title)
        ttl.addWidget(subtitle)
        header.addLayout(ttl, 1)

        self.badge_gw = Badge("GW", "Discord Gateway")
        self.badge_speed = Badge("SPD", "Speed sniping pipeline")
        self.badge_ws = Badge("WS", "Local Lua WebSocket")
        for badge in (self.badge_gw, self.badge_speed, self.badge_ws):
            badge.set_state(None)
            header.addWidget(badge)

        layout.addLayout(header)
        layout.addWidget(Divider())

        # --- token row + remember toggle ---
        form = QtWidgets.QHBoxLayout()
        form.setSpacing(8)
        lbl = QtWidgets.QLabel("Token")
        self.token_edit = QtWidgets.QLineEdit()
        self.token_edit.setEchoMode(QtWidgets.QLineEdit.Password)
        self.token_edit.setPlaceholderText("Discord token…")
        saved_token = self.settings.value("token", "", type=str)
        env_token = os.getenv("DISCORD_TOKEN", "")
        self.token_edit.setText(saved_token or env_token)
        self._apply_shadow(self.token_edit)
        eye = QtWidgets.QToolButton()
        eye.setCheckable(True)
        eye.setObjectName("eye")
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
        filter_row = QtWidgets.QHBoxLayout()
        filter_row.setSpacing(8)

        self.filterCard = QtWidgets.QFrame()
        self.filterCard.setObjectName("filterCard")
        self.filterCard.setMinimumHeight(44)
        card_layout = QtWidgets.QHBoxLayout(self.filterCard)
        card_layout.setContentsMargins(12, 6, 12, 6)
        card_layout.setSpacing(10)

        min_title = QtWidgets.QLabel("Min M/s")
        min_title.setObjectName("filterTitle")

        self.min_spin = QtWidgets.QDoubleSpinBox()
        self.min_spin.setObjectName("minSpin")
        self.min_spin.setDecimals(2)
        self.min_spin.setRange(0.00, 9999.0)
        self.min_spin.setSingleStep(0.25)
        self.min_spin.setSuffix(" M/s")
        self.min_spin.setButtonSymbols(QtWidgets.QAbstractSpinBox.NoButtons)
        self.min_spin.setAlignment(QtCore.Qt.AlignCenter)
        saved_min = self.settings.value("min_money_m", 20.0, type=float)
        self.min_spin.setValue(max(20.0, float(saved_min)))

        def preset_btn(text: str, val: float):
            btn = QtWidgets.QPushButton(text)
            btn.setProperty("preset", True)
            btn.setCursor(QtGui.QCursor(QtCore.Qt.PointingHandCursor))
            btn.clicked.connect(lambda: self.min_spin.setValue(float(val)))
            return btn

        presets = QtWidgets.QHBoxLayout()
        presets.setSpacing(6)
        for label, value in [("20M", 20), ("50M", 50), ("100M", 100)]:
            presets.addWidget(preset_btn(label, value))

        card_layout.addWidget(min_title)
        card_layout.addWidget(self.min_spin, 0)
        card_layout.addStretch(1)
        card_layout.addLayout(presets)

        filter_row.addWidget(self.filterCard)
        layout.addLayout(filter_row)

        layout.addWidget(Divider())

        controls = QtWidgets.QHBoxLayout()
        controls.setSpacing(8)
        self.start_btn = QtWidgets.QPushButton("Start")
        self.stop_btn = QtWidgets.QPushButton("Stop")
        self.stop_btn.setEnabled(False)
        self.clear_btn = QtWidgets.QPushButton("Clear Log")
        for btn in (self.start_btn, self.stop_btn, self.clear_btn):
            self._apply_shadow(btn)
        controls.addWidget(self.start_btn)
        controls.addWidget(self.stop_btn)
        controls.addStretch(1)
        controls.addWidget(self.clear_btn)
        layout.addLayout(controls)

        layout.addWidget(Divider())

        self.output = QtWidgets.QTextEdit()
        self.output.setReadOnly(True)
        self.output.setObjectName("console")
        self.output.setPlaceholderText("Output…")
        self._apply_shadow(self.output, blur=28, y=4, alpha=140)
        layout.addWidget(self.output, 1)

        self.sniper: Optional[CronixSniper] = None
        self.logger = LogSignal()
        self.logger.line.connect(self._append_log)
        self.status_sig = StatusSignal()
        self.status_sig.update.connect(self._apply_status)
        self.worker = AsyncWorker()
        self.worker.start()

        self.start_btn.clicked.connect(self.on_start)
        self.stop_btn.clicked.connect(self.on_stop)
        self.clear_btn.clicked.connect(self._clear_log)
        self.min_spin.valueChanged.connect(self._on_min_changed)

        QtGui.QShortcut(QtGui.QKeySequence("Ctrl+L"), self, activated=self._clear_log)
        QtGui.QShortcut(QtGui.QKeySequence("Ctrl+R"), self, activated=self._restart_if_running)

        self.restoreGeometry(self.settings.value("geometry", b""))
        self.restoreState(self.settings.value("state", b""))

    def _icon(self):
        ico = QtGui.QIcon(res_path("cronixlogo.ico"))
        if not ico.isNull():
            return ico
        pm = QtGui.QPixmap(32, 32)
        pm.fill(QtCore.Qt.transparent)
        painter = QtGui.QPainter(pm)
        painter.setRenderHint(QtGui.QPainter.Antialiasing)
        path = QtGui.QPainterPath()
        path.addRoundedRect(2, 2, 28, 28, 6, 6)
        painter.fillPath(path, QtGui.QColor("#ff3141"))
        painter.setPen(QtGui.QPen(QtGui.QColor("#0a0a0c"), 3))
        painter.drawLine(8, 16, 16, 24)
        painter.drawLine(16, 24, 26, 10)
        painter.end()
        return QtGui.QIcon(pm)

    def _style(self) -> str:
        return """
        * { font-family: Inter, 'Segoe UI', Roboto, Arial; font-size: 12.5px; }
        QMainWindow {
          background: qradialgradient(cx:0.5, cy:0.2, radius:1.0,
                       fx:0.5, fy:0.2, stop:0 #0d0a0b, stop:1 #100a0c);
        }
        QLabel#title { color: #ffeef0; font-size: 23px; font-weight: 900; letter-spacing: .8px; }
        QLabel#subtitle { color: #ffb0b9; font-size: 10.5px; margin-top: -2px; }
        QFrame#sep { background: transparent; border: 0; border-top: 1px dashed #5a1a22; margin: 2px 0; }
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
        QToolButton#eye {
          background: #1a0d10;
          border: 1px solid #5a1a22;
          border-radius: 9px;
          padding: 0 8px;
          color: #ffdfe3;
        }
        QToolButton#eye:hover { border-color: #ff4153; }
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
        QFrame#filterCard {
          background: #160c0f;
          border: 1px solid #5a1a22;
          border-radius: 12px;
        }
        QLabel#filterTitle { color: #ffc0c8; font-weight: 900; letter-spacing: .35px; }
        QDoubleSpinBox#minSpin { min-width: 120px; }
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

    def _toggle_token(self, checked: bool) -> None:
        self.token_edit.setEchoMode(
            QtWidgets.QLineEdit.Normal if checked else QtWidgets.QLineEdit.Password
        )

    def _apply_shadow(
        self,
        widget: QtWidgets.QWidget,
        *,
        blur: int = 22,
        x: int = 0,
        y: int = 2,
        alpha: int = 110,
    ) -> None:
        eff = QtWidgets.QGraphicsDropShadowEffect()
        eff.setBlurRadius(blur)
        eff.setOffset(x, y)
        eff.setColor(QtGui.QColor(0, 0, 0, alpha))
        widget.setGraphicsEffect(eff)

    def _append_log(self, line: str) -> None:
        ts = datetime.datetime.now().strftime("%H:%M:%S")
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

    def log(self, line: str) -> None:
        self.logger.line.emit(line)

    def _apply_status(self, data: dict) -> None:
        if "gw" in data:
            self.badge_gw.set_state(data["gw"] == "ok")
        if "speed" in data:
            self.badge_speed.set_state(data["speed"] == "ok")
        if "ws" in data:
            self.badge_ws.set_state(data["ws"] == "ok")

    def _clear_log(self) -> None:
        self.output.clear()

    def _restart_if_running(self) -> None:
        if self.sniper:
            self.on_stop()
            self.on_start()

    def _on_min_changed(self, val: float) -> None:
        self.settings.setValue("min_money_m", float(val))
        if self.sniper:
            self.sniper.set_min_money(float(val))

    def on_start(self) -> None:
        if self.sniper:
            return
        token = self.token_edit.text().strip()
        if not token or len(token) < 16:
            QtWidgets.QMessageBox.critical(
                self,
                "Missing token",
                "Please enter your Discord token. The guide is pinned in the Cronix Discord in #obtain-your-token.",
            )
            return
        if self.remember_chk.isChecked():
            self.settings.setValue("token", token)
        else:
            self.settings.remove("token")

        min_m = float(self.min_spin.value())
        self.sniper = CronixSniper(
            self.log,
            self.status_sig.update.emit,
            token=token,
            use_bot_token=False,
            min_money_m=min_m,
        )
        self.worker.call_soon_threadsafe(self.sniper.start())
        self.start_btn.setEnabled(False)
        self.stop_btn.setEnabled(True)
        self.badge_speed.set_state(None)

    def on_stop(self) -> None:
        if not self.sniper:
            return
        self.worker.call_soon_threadsafe(self.sniper.stop())
        self.sniper = None
        self.start_btn.setEnabled(True)
        self.stop_btn.setEnabled(False)

    def closeEvent(self, ev: QtGui.QCloseEvent) -> None:  # type: ignore[override]
        try:
            self.settings.setValue("geometry", self.saveGeometry())
            self.settings.setValue("state", self.saveState())
            if self.sniper:
                self.worker.call_soon_threadsafe(self.sniper.stop())
        finally:
            super().closeEvent(ev)


def main() -> int:
    try:
        QtWidgets.QApplication.setAttribute(QtCore.Qt.AA_EnableHighDpiScaling, True)
        app = QtWidgets.QApplication(sys.argv)
        app.setApplicationName("Cronix")
        app.setWindowIcon(QtGui.QIcon(res_path("cronixlogo.ico")))
        if sys.platform == "win32":
            try:
                import ctypes

                ctypes.windll.shell32.SetCurrentProcessExplicitAppUserModelID("Cronix.CronixGUI")
            except Exception:
                pass
        window = CronixWindow()
        window.show()
        return app.exec()
    except Exception as exc:
        err = traceback.format_exc()
        try:
            with open("cronix_error.log", "w", encoding="utf-8") as fh:
                fh.write(err)
        except Exception:
            pass
        try:
            QtWidgets.QMessageBox.critical(
                None,
                "Cronix crashed",
                f"Startup error:\n{exc}\n\nFull trace saved to cronix_error.log",
            )
        except Exception:
            pass
        print(err)
        return 1


if __name__ == "__main__":
    try:
        sys.exit(main())
    except KeyboardInterrupt:
        pass
