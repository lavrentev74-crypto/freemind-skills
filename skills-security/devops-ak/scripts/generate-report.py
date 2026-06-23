#!/usr/bin/env python3
"""
PDF Report Generator — devops-ak skill.

Полностью data-driven. Никакой магии: если поля нет в JSON — нет в отчёте.

Usage:
    python3 generate-report.py data.json [output.pdf]

Ожидаемая структура data.json (все поля опциональные кроме помеченных REQUIRED):

{
  "date": "DD.MM.YYYY",                 # REQUIRED
  "domain": "example.com",              # REQUIRED
  "server_ip": "1.2.3.4",               # REQUIRED
  "email": "admin@example.com",
  "ssh_port": "22",
  "date_label": "Дата",
  "server_info": {                      # таблица «Конфигурация сервера»
     "Операционная система": "Ubuntu 22.04 LTS",
     "Процессор": "4 vCPU",
     ...
  },
  "done_tasks": ["Установка Docker", ...],   # список для «Выполненные работы»
                                             # если отсутствует — сгенерим
                                             # автоматически из services+dns
  "ssh_users": [                         # ЛЮБОЕ количество SSH-пользователей
    {
      "title": "root (полный доступ)",  # показать над таблицей
      "user": "root",
      "password": "...",
      "ip": "1.2.3.4",                  # опционально, по умолчанию server_ip
      "port": "22"                       # опционально, по умолчанию ssh_port
    },
    {
      "title": "openclaw (под ним работают OpenClaw и Paperclip)",
      "user": "openclaw",
      "password": "..."
    }
  ],
  "services": {                          # упорядоченный словарь — порядок JSON
    "openclaw": {
      "label": "OpenClaw",
      "description": "короткое описание курсивом, авто-переносится на новую строку",
      "url": "https://...",              # опционально → строка «URL» в таблице
      "login": "...",                    # опционально → «Логин»
      "password": "...",                 # опционально → «Пароль»
      "extra": {                         # упорядоченный dict — любые доп. поля
         "Gateway token": "...",
         "SSH tunnel": "ssh -N -L ..."
      },
      "note": "Примечание курсивом под таблицей"
    }
  },
  "dns_records": [
    {"subdomain": "pc.example.com", "type": "A", "service": "Paperclip"}
  ],
  "security_items": ["Файрвол UFW: ...", "SSL через Let's Encrypt", ...],
  "backup_items": ["Автоматический бэкап ежедневно 03:00", ...],
  "health_items": ["Caddy", "OpenClaw", ...]  # список названий — пройдут как «работает»
}
"""

import json
import os
import sys

from reportlab.lib import colors
from reportlab.lib.pagesizes import A4
from reportlab.lib.styles import ParagraphStyle
from reportlab.lib.units import mm
from reportlab.lib.enums import TA_LEFT
from reportlab.platypus import (
    SimpleDocTemplate, Paragraph, Spacer, Table, TableStyle, Flowable,
    CondPageBreak,
)
from reportlab.pdfbase import pdfmetrics
from reportlab.pdfbase.ttfonts import TTFont
from reportlab.pdfbase.pdfmetrics import stringWidth


# ──────────────────────────────────────────────────────────────────────────
# Шрифты (любой TTF с кириллицей на macOS / Linux)
# ──────────────────────────────────────────────────────────────────────────

FONT_CANDIDATES = {
    "regular": [
        "/System/Library/Fonts/Supplemental/Arial.ttf",
        "/Library/Fonts/Arial.ttf",
        "/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf",
        "/usr/share/fonts/truetype/liberation/LiberationSans-Regular.ttf",
    ],
    "bold": [
        "/System/Library/Fonts/Supplemental/Arial Bold.ttf",
        "/Library/Fonts/Arial Bold.ttf",
        "/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf",
        "/usr/share/fonts/truetype/liberation/LiberationSans-Bold.ttf",
    ],
}

def setup_fonts():
    reg = next((p for p in FONT_CANDIDATES["regular"] if os.path.exists(p)), None)
    bold = next((p for p in FONT_CANDIDATES["bold"] if os.path.exists(p)), reg)
    if not reg:
        sys.exit("ОШИБКА: не найден TTF-шрифт с кириллицей (Arial / DejaVu / Liberation).")
    pdfmetrics.registerFont(TTFont("Main", reg))
    pdfmetrics.registerFont(TTFont("Main-Bold", bold or reg))
    pdfmetrics.registerFontFamily("Main", normal="Main", bold="Main-Bold")


# ──────────────────────────────────────────────────────────────────────────
# Палитра
# ──────────────────────────────────────────────────────────────────────────

PRIMARY     = colors.HexColor("#1B2A4A")
ACCENT      = colors.HexColor("#2D6CDF")
TEXT        = colors.HexColor("#2C3E50")
MUTED       = colors.HexColor("#6C757D")
GREEN       = colors.HexColor("#28A745")
TABLE_HEAD  = colors.HexColor("#3A5BA0")
TABLE_ALT   = colors.HexColor("#F4F6F9")
BORDER      = colors.HexColor("#DEE2E6")

# A4 с полями → полезная ширина
MARGIN = 18 * mm
PAGE_W = A4[0] - 2 * MARGIN


# ──────────────────────────────────────────────────────────────────────────
# Стили параграфов
# ──────────────────────────────────────────────────────────────────────────

def make_styles():
    return {
        "H1":  ParagraphStyle("H1", fontName="Main-Bold", fontSize=22,
                              textColor=PRIMARY, leading=26, spaceAfter=4 * mm),
        "Meta": ParagraphStyle("Meta", fontName="Main", fontSize=10,
                               textColor=TEXT, leading=14),
        "Body": ParagraphStyle("Body", fontName="Main", fontSize=9.5,
                               textColor=TEXT, leading=13, alignment=TA_LEFT),
        "Note": ParagraphStyle("Note", fontName="Main", fontSize=8.5,
                               textColor=MUTED, leading=12, alignment=TA_LEFT),
        "Check": ParagraphStyle("Check", fontName="Main", fontSize=9.5,
                                textColor=TEXT, leading=14, leftIndent=16),
    }


# ──────────────────────────────────────────────────────────────────────────
# Вспомогательные flowables
# ──────────────────────────────────────────────────────────────────────────

class SectionHeader(Flowable):
    """Заголовок раздела — синяя вертикальная полоса + крупный текст."""
    def __init__(self, text, size=13):
        super().__init__()
        self.text = text
        self.size = size
    def wrap(self, aW, aH):
        self.width = aW
        self.height = 22
        return aW, self.height
    def draw(self):
        c = self.canv
        c.setFillColor(ACCENT)
        c.roundRect(0, 3, 4, 18, 1, fill=1, stroke=0)
        c.setFillColor(PRIMARY)
        c.setFont("Main-Bold", self.size)
        c.drawString(12, 6, self.text)


class SubHeader(Flowable):
    """Заголовок подраздела с описанием, описание авто-переносится."""
    FONT_DESC = 8.5
    LINE_H = 12
    INDENT = 10
    def __init__(self, title, description=""):
        super().__init__()
        self.title = title
        self.description = description
        self._lines = []
    def wrap(self, aW, aH):
        self.width = aW
        h = 16
        if self.description:
            max_w = aW - self.INDENT
            words = self.description.split()
            cur, out = "", []
            for w in words:
                cand = (cur + " " + w).strip()
                if stringWidth(cand, "Main", self.FONT_DESC) <= max_w:
                    cur = cand
                else:
                    if cur:
                        out.append(cur)
                    cur = w
            if cur:
                out.append(cur)
            self._lines = out
            h += self.LINE_H * len(out) + 2
        self.height = h
        return aW, h
    def draw(self):
        c = self.canv
        top = self.height - 14
        c.setFillColor(ACCENT)
        c.roundRect(0, top, 3, 14, 1, fill=1, stroke=0)
        c.setFillColor(PRIMARY)
        c.setFont("Main-Bold", 11)
        c.drawString(self.INDENT, top + 2, self.title)
        if self._lines:
            c.setFillColor(MUTED)
            c.setFont("Main", self.FONT_DESC)
            y = top - 2
            for line in self._lines:
                y -= self.LINE_H
                c.drawString(self.INDENT, y, line)


class HR(Flowable):
    def __init__(self, color=BORDER, thickness=0.5):
        super().__init__()
        self.color, self.t = color, thickness
    def wrap(self, aW, aH):
        self.width = aW
        self.height = self.t + 2 * mm
        return aW, self.height
    def draw(self):
        c = self.canv
        c.setStrokeColor(self.color)
        c.setLineWidth(self.t)
        y = self.height / 2
        c.line(0, y, self.width, y)


def gap(mm_):
    return Spacer(1, mm_ * mm)


# ──────────────────────────────────────────────────────────────────────────
# Универсальная таблица «параметр — значение»
# ──────────────────────────────────────────────────────────────────────────

import re as _re
_URL_RE = _re.compile(r"(https?://[^\s<>\"']+)", _re.IGNORECASE)

def linkify(text):
    """XML-escape + превращает http(s)://... в кликабельные <a> для Paragraph.

    Возвращает готовый inline-HTML для reportlab Paragraph.
    """
    if text is None:
        return ""
    s = str(text).replace("&", "&amp;").replace("<", "&lt;").replace(">", "&gt;")
    def _sub(m):
        url = m.group(1)
        return (f'<a href="{url}" color="#2D6CDF"><u>{url}</u></a>')
    return _URL_RE.sub(_sub, s)


def kv_table(rows, col_ratio=(0.35, 0.65), styles=None):
    """rows = [[key, value], ...]. Value может быть строкой или Paragraph.

    Строковые значения автоматически linkify — URL-ы становятся кликабельными.
    """
    styles = styles or make_styles()
    body = [[
        Paragraph("<b>Параметр</b>", ParagraphStyle("th", fontName="Main-Bold",
                   fontSize=9.5, textColor=colors.white, leading=12)),
        Paragraph("<b>Значение</b>", ParagraphStyle("th", fontName="Main-Bold",
                   fontSize=9.5, textColor=colors.white, leading=12)),
    ]]
    value_style = ParagraphStyle("val", fontName="Main", fontSize=9.5,
                                  textColor=TEXT, leading=13, wordWrap="CJK")
    key_style = ParagraphStyle("key", fontName="Main-Bold", fontSize=9.5,
                                textColor=TEXT, leading=13)
    for k, v in rows:
        if not isinstance(v, Paragraph):
            v = Paragraph(linkify(v), value_style)
        body.append([Paragraph(str(k), key_style), v])

    t = Table(body,
              colWidths=[PAGE_W * col_ratio[0], PAGE_W * col_ratio[1]],
              repeatRows=1)
    t.setStyle(TableStyle([
        ("BACKGROUND", (0, 0), (-1, 0), TABLE_HEAD),
        ("TEXTCOLOR", (0, 0), (-1, 0), colors.white),
        ("ALIGN", (0, 0), (-1, -1), "LEFT"),
        ("VALIGN", (0, 0), (-1, -1), "MIDDLE"),
        ("FONTNAME", (0, 0), (-1, 0), "Main-Bold"),
        ("FONTSIZE", (0, 0), (-1, 0), 9.5),
        ("BOTTOMPADDING", (0, 0), (-1, 0), 6),
        ("TOPPADDING", (0, 0), (-1, 0), 6),
        ("ROWBACKGROUNDS", (0, 1), (-1, -1), [colors.white, TABLE_ALT]),
        ("GRID", (0, 0), (-1, -1), 0.25, BORDER),
        ("LEFTPADDING", (0, 0), (-1, -1), 8),
        ("RIGHTPADDING", (0, 0), (-1, -1), 8),
        ("TOPPADDING", (0, 1), (-1, -1), 5),
        ("BOTTOMPADDING", (0, 1), (-1, -1), 5),
    ]))
    return t


# ──────────────────────────────────────────────────────────────────────────
# Header/footer на каждой странице
# ──────────────────────────────────────────────────────────────────────────

def make_page_template(domain, date_str):
    """Без колонтитулов и футера — юзер просил чистые страницы."""
    def draw(canvas, doc):
        pass
    return draw


# ──────────────────────────────────────────────────────────────────────────
# Построители секций
# ──────────────────────────────────────────────────────────────────────────

def build_title_block(data, styles):
    out = []
    out.append(Paragraph("Отчёт по выполненным работам и<br/>"
                          "административная информация по системе",
                          styles["H1"]))
    out.append(Paragraph(f"<b>Дата:</b> {data['date']}", styles["Meta"]))
    out.append(Paragraph("<b>Исполнитель:</b> devops-ak", styles["Meta"]))
    out.append(gap(3))
    ip    = data.get("server_ip", "")
    dom   = data.get("domain", "")
    email = data.get("email", "")
    parts = []
    if ip:    parts.append(f"<b>Сервер:</b> {ip}")
    if dom:   parts.append(f"<b>Домен:</b> {dom}")
    if email: parts.append(f"<b>Email:</b> {email}")
    if parts:
        out.append(Paragraph(" | ".join(parts), styles["Meta"]))
    out.append(gap(3))
    out.append(HR(color=ACCENT, thickness=1.2))
    out.append(gap(5))
    return out


def build_done_tasks(data, styles):
    """Автогенерируем или берём из data['done_tasks']."""
    tasks = data.get("done_tasks")
    if tasks is None:
        tasks = ["Установка Docker и Docker Compose"]
        for svc in data.get("services", {}).values():
            tasks.append(f"Установка и настройка {svc.get('label', '')}".strip())
        if data.get("dns_records"):
            tasks.append("Настройка субдоменов с SSL-сертификатами Let's Encrypt")
            tasks.append("Создание DNS-записей в Cloudflare")
        tasks.append("Настройка файрвола (UFW)")
        tasks.append("Проверка работоспособности всех сервисов")
    out = [SectionHeader("Выполненные работы"), gap(2)]
    for t in tasks:
        out.append(Paragraph(
            f'<font color="#28A745"><b>[OK]</b></font> {t}', styles["Check"]
        ))
    out.append(gap(6))
    out.append(HR())
    out.append(gap(4))
    return out


def build_server_info(data, styles):
    info = data.get("server_info") or {}
    if not info:
        return []
    # Канонический порядок ключей, если они есть
    pref = [
        "Операционная система", "os",
        "Процессор", "cpu",
        "Оперативная память", "ram",
        "Диск", "disk",
        "Docker", "docker_version",
        "Docker Compose", "docker_compose_version",
    ]
    rename = {
        "os": "Операционная система",
        "cpu": "Процессор",
        "ram": "Оперативная память",
        "disk": "Диск",
        "docker_version": "Docker",
        "docker_compose_version": "Docker Compose",
    }
    rows = []
    # Сначала в каноническом порядке, затем всё остальное
    seen = set()
    for k in pref:
        if k in info:
            rows.append([rename.get(k, k), info[k]])
            seen.add(k)
    for k, v in info.items():
        if k not in seen:
            rows.append([rename.get(k, k), v])

    out = [SectionHeader("Конфигурация сервера"), gap(2),
           kv_table(rows, styles=styles), gap(6), HR(), gap(4)]
    return out


def build_ssh_access(data, styles):
    users = data.get("ssh_users") or []
    if not users:
        return []
    out = [SectionHeader("Данные для доступа"), gap(2),
           SubHeader("SSH-доступ к серверу",
                     "Системные пользователи для подключения по SSH. "
                     "Пароли актуальные — подходят и для ssh-логина, "
                     "и для ssh-туннелей к внутренним портам.")]
    out.append(gap(2))
    default_ip = data.get("server_ip", "")
    default_port = str(data.get("ssh_port", "22"))
    for i, u in enumerate(users, 1):
        title = u.get("title") or u.get("user", "")
        ip = u.get("ip") or default_ip
        port = str(u.get("port") or default_port)
        user = u.get("user", "")
        pw = u.get("password", "")
        out.append(gap(2))
        out.append(Paragraph(f"<b>{i}. {title}</b>", styles["Body"]))
        out.append(gap(1))
        rows = [["IP-адрес", ip], ["Пользователь", user], ["Порт", port]]
        if pw:
            rows.append(["Пароль", pw])
        out.append(kv_table(rows, styles=styles))
        cmd = f"ssh {user}@{ip}" if port == "22" else f"ssh -p {port} {user}@{ip}"
        out.append(gap(1))
        out.append(Paragraph(
            f'Команда подключения: <font name="Main-Bold">{cmd}</font>',
            styles["Note"]
        ))
    out.append(gap(4))
    out.append(Paragraph(
        '<b>Рекомендуемый SSH-клиент:</b> '
        '<a href="https://www.termius.com/" color="#2D6CDF"><u>Termius</u></a> — '
        'бесплатного аккаунта достаточно. Добавь хосты из данных выше.',
        styles["Body"]
    ))
    out.append(gap(5))
    return out


def build_services(data, styles):
    services = data.get("services") or {}
    if not services:
        return []
    out = []
    for _, svc in services.items():
        label = svc.get("label", "")
        description = svc.get("description", "")
        url = svc.get("url", "")
        login = svc.get("login", "")
        password = svc.get("password", "")
        extra = svc.get("extra") or {}
        note = svc.get("note") or svc.get("notes") or ""

        rows = []
        if url:      rows.append(["URL", url])
        if login:    rows.append(["Логин", login])
        if password: rows.append(["Пароль", password])
        for k, v in extra.items():
            rows.append([k, v])

        # Блок сервиса = заголовок + (опц. таблица) + (опц. примечание)
        block = [gap(4), SubHeader(label, description), gap(1)]
        if rows:
            block.append(kv_table(rows, styles=styles))
        if note:
            block.append(gap(1))
            block.append(Paragraph(f"Примечание: {note}", styles["Note"]))
        # Если нет ни таблицы ни примечания — оставляем только заголовок+описание
        out.append(CondPageBreak(40 * mm))
        out.extend(block)
    out.append(gap(6))
    out.append(HR())
    out.append(gap(4))
    return out


def build_security(data, styles):
    items = data.get("security_items")
    if items is None:
        # Автогенерация: порты = 22, 80, 443 + 222 если есть gitea
        ports = ["22", "80", "443"]
        if "gitea" in (data.get("services") or {}):
            ports.append("222 (Gitea SSH)")
        items = [
            f"Файрвол UFW: открыты только порты {', '.join(ports)}",
            "Все сервисы доступны только через reverse proxy (Caddy)",
            "SSL-сертификаты автоматически обновляются через Let's Encrypt",
            "Все пароли сгенерированы криптографически (openssl rand)",
        ]
    out = [SectionHeader("Безопасность"), gap(2)]
    for t in items:
        out.append(Paragraph(
            f'<font color="#28A745"><b>[OK]</b></font> {t}', styles["Check"]
        ))
    out.append(gap(6))
    out.append(HR())
    out.append(gap(4))
    return out


def build_backups(data, styles):
    """Бэкапы: скрипты уже есть, автоматизация и проверка — через агента.

    Рендерит 3 готовых промпта, которые юзер копирует в Claude Code /
    Claude Desktop / Paperclip. Каждый промпт начинается с `/devops-ak`
    и адресован агенту с доступом к скиллу.

    В data.json можно переопределить массив `backup_prompts`:
        [{"title": "...", "why": "...", "prompt": "..."}, ...]
    """
    ip = data.get("server_ip", "SERVER_IP")
    domain = data.get("domain", "example.com")
    slug = domain.split(".")[0] if "." in domain else domain

    prompts = data.get("backup_prompts") or [
        {
            "title": "1. Чтобы бэкапы делались сами каждую ночь",
            "why": "Защита от «случайно удалил что-то важное». Бэкапы остаются на том же сервере.",
            "prompt": (
                f"/devops-ak настрой ежедневный автоматический бэкап на моём сервере {ip}. "
                f"Каждую ночь в 3:00 должен сам запускаться /root/skill-scripts/backup.sh all 2 — "
                f"делать копии всех сервисов и хранить две последние версии. Пароль root и "
                f"остальные данные — из моего отчёта. Проверь что расписание реально встало и "
                f"покажи мне результат."
            ),
        },
        {
            "title": "2. Чтобы копии бэкапов ещё и скачивались на мой ноутбук",
            "why": "Защита от «сервер целиком умер / взломан / провайдер пропал». Копии лежат у тебя локально.",
            "prompt": (
                f"/devops-ak настрой ежедневное скачивание бэкапов с моего сервера {ip} на этот "
                f"ноутбук — в папку ~/backups. Делать каждую ночь в 4:00 (через час после "
                f"серверного бэкапа). Хранить локально 7 последних копий, старые удалять. Сначала "
                f"проверь что вручную всё скачивается, потом поставь на расписание."
            ),
        },
        {
            "title": "3. Сразу после установки — проверь что бэкапы вообще разворачиваются",
            "why": "Бывает так: файл в /root/backups/ есть, а развернуть нельзя (битый дамп, "
                   "missed-volume и т.п.). Лучше словить это сейчас, а не в момент когда реально "
                   "что-то упало.",
            "prompt": (
                f"/devops-ak проверь прямо сейчас что бэкапы моего сервера {ip} реально "
                f"восстанавливаются. Возьми самый свежий бэкап n8n и gitea, подними из них "
                f"временные копии в отдельной сети, убедись что базы открываются и данные "
                f"на месте. Потом всё снеси и напиши одним предложением: «всё ок» или «сломалось "
                f"вот что»."
            ),
        },
    ]

    out = [SectionHeader("Бэкапы"), gap(2)]
    out.append(Paragraph(
        "На сервере уже лежат скрипты <b>backup.sh</b> (делает копии) и "
        "<b>restore.sh</b> (разворачивает обратно), но <b>сами они не запускаются</b>. "
        "Чтобы настроить автобэкапы, скачивание копий к себе и проверку что всё "
        "разворачивается — скопируй промпт ниже и отдай своему Claude-агенту "
        "(в Claude Code, Claude Desktop или через Paperclip). Он подключится "
        "к серверу и сделает всё сам.",
        styles["Body"]
    ))
    out.append(gap(3))

    # Стиль «код-блок» для самого промпта
    prompt_style = ParagraphStyle(
        "Prompt", fontName="Main", fontSize=9, textColor=TEXT,
        leading=12.5, leftIndent=8, rightIndent=8,
        spaceBefore=2, spaceAfter=2, wordWrap="CJK",
    )

    for p in prompts:
        # Подзаголовок + объяснение
        out.append(CondPageBreak(50 * mm))
        out.append(gap(3))
        out.append(Paragraph(f"<b>{p['title']}</b>", styles["Body"]))
        out.append(gap(1))
        out.append(Paragraph(f"<i>{p['why']}</i>", styles["Note"]))
        out.append(gap(2))
        # Сам промпт в рамке со слабой заливкой
        inner = Paragraph(p["prompt"], prompt_style)
        framed = Table([[inner]], colWidths=[PAGE_W])
        framed.setStyle(TableStyle([
            ("BACKGROUND", (0, 0), (-1, -1), colors.HexColor("#F4F6F9")),
            ("BOX", (0, 0), (-1, -1), 0.4, BORDER),
            ("LEFTPADDING", (0, 0), (-1, -1), 10),
            ("RIGHTPADDING", (0, 0), (-1, -1), 10),
            ("TOPPADDING", (0, 0), (-1, -1), 8),
            ("BOTTOMPADDING", (0, 0), (-1, -1), 8),
        ]))
        out.append(framed)

    # P.S. про снапшоты хостинга — на AdminVPS они включены в тариф Micro+.
    out.append(gap(4))
    out.append(Paragraph(
        "<b>P.S.</b> Если сервер на AdminVPS и тариф Micro или выше — "
        "еженедельный полный снапшот всего сервера уже делается автоматически "
        "самим хостингом (см. ЛК AdminVPS → Снапшоты). Для большинства задач "
        "этого уже достаточно, и три промпта выше можно не настраивать. "
        "Они нужны только если требуется более частая периодичность, локальная "
        "копия у тебя на ноутбуке или гарантия что бэкап разворачивается.",
        styles["Note"]
    ))
    out.append(gap(6))
    out.append(HR())
    out.append(gap(4))
    return out


# ──────────────────────────────────────────────────────────────────────────
# main
# ──────────────────────────────────────────────────────────────────────────

def generate(data_path, pdf_path):
    with open(data_path, encoding="utf-8") as f:
        data = json.load(f)

    # REQUIRED checks
    for req in ("date", "domain", "server_ip"):
        if not data.get(req):
            sys.exit(f"ОШИБКА: в data.json отсутствует обязательное поле '{req}'.")

    setup_fonts()
    styles = make_styles()

    doc = SimpleDocTemplate(
        pdf_path,
        pagesize=A4,
        leftMargin=MARGIN, rightMargin=MARGIN,
        topMargin=MARGIN, bottomMargin=MARGIN,
        title=f"Server Report — {data['domain']}",
        author="devops-ak",
    )

    story = []
    story += build_title_block(data, styles)
    story += build_server_info(data, styles)
    story += build_ssh_access(data, styles)
    story += build_services(data, styles)
    story += build_security(data, styles)
    story += build_backups(data, styles)

    draw = make_page_template(data["domain"], data["date"])
    doc.build(story, onFirstPage=draw, onLaterPages=draw)
    print(f"Отчёт сохранён: {pdf_path}")


def main():
    if len(sys.argv) < 2:
        sys.exit("Usage: generate-report.py data.json [output.pdf]")
    data_path = sys.argv[1]
    pdf_path = sys.argv[2] if len(sys.argv) >= 3 else "server-report.pdf"
    generate(data_path, pdf_path)


if __name__ == "__main__":
    main()
