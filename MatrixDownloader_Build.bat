@echo off
setlocal enabledelayedexpansion
cd /d "%~dp0"
title MatrixDownloader Builder

echo ===============================================================
echo   MATRIX DOWNLOADER - Compilador todo-en-uno
echo ===============================================================
echo.
echo Este archivo unico hace todo el proceso:
echo   1. Extrae main.py (el programa) desde si mismo
echo   2. Crea un entorno virtual e instala yt-dlp y pyinstaller
echo   3. Descarga ffmpeg portable
echo   4. Compila MatrixDownloader.exe
echo.
echo Solo necesitas tener Python instalado. Internet se usa una vez.
echo El archivo MatrixDownloader.exe final no necesitara nada mas.
echo.
pause

where python >nul 2>nul
if errorlevel 1 goto no_python
goto have_python

:no_python
echo.
echo [ERROR] No se encontro Python en el PATH.
echo Instalalo desde https://www.python.org/downloads/
echo Marca la casilla "Add python.exe to PATH" durante la instalacion.
echo.
pause
exit /b 1

:have_python
echo.
echo [1/6] Extrayendo main.py...
powershell -NoProfile -Command "$c = Get-Content -Raw -LiteralPath '%~f0'; $marker = '@@PYCODE_MARKER@@'; $idx = $c.LastIndexOf($marker); if ($idx -lt 0) { exit 1 }; $code = $c.Substring($idx + $marker.Length); $code = $code -replace '^(\r\n|\n)+', ''; $utf8NoBom = New-Object System.Text.UTF8Encoding($false); [System.IO.File]::WriteAllText('main.py', $code, $utf8NoBom)"
if errorlevel 1 goto extract_failed
if not exist main.py goto extract_failed
goto extract_ok

:extract_failed
echo [ERROR] No se pudo extraer main.py desde este archivo.
pause
exit /b 1

:extract_ok
echo.
echo [2/6] Creando entorno virtual...
if not exist venv_build python -m venv venv_build

echo.
echo [3/6] Instalando dependencias, yt-dlp y pyinstaller...
venv_build\Scripts\pip.exe install --upgrade pip >nul
venv_build\Scripts\pip.exe install "yt-dlp>=2024.1.1" pyinstaller
if errorlevel 1 goto deps_failed
goto deps_ok

:deps_failed
echo [ERROR] Fallo instalando dependencias. Revisa tu conexion a internet.
pause
exit /b 1

:deps_ok
echo.
echo [4/6] Preparando ffmpeg...
if exist ffmpeg.exe goto ffmpeg_ready

echo Descargando ffmpeg portable, build estatico, unos 80 MB...
powershell -NoProfile -Command "try { Invoke-WebRequest -Uri 'https://github.com/BtbN/FFmpeg-Builds/releases/latest/download/ffmpeg-master-latest-win64-gpl.zip' -OutFile 'ffmpeg_temp.zip' -UseBasicParsing } catch { exit 1 }"
if errorlevel 1 goto ffmpeg_manual

powershell -NoProfile -Command "Expand-Archive -Path 'ffmpeg_temp.zip' -DestinationPath 'ffmpeg_temp' -Force"

for /f "delims=" %%F in ('dir /s /b ffmpeg_temp\ffmpeg.exe') do copy /y "%%F" "ffmpeg.exe" >nul

if exist ffmpeg_temp rmdir /s /q ffmpeg_temp
if exist ffmpeg_temp.zip del /q ffmpeg_temp.zip

:ffmpeg_ready
if exist ffmpeg.exe goto ffmpeg_done

:ffmpeg_manual
echo.
echo [ERROR] No se pudo obtener ffmpeg.exe automaticamente.
echo Descargalo a mano desde https://www.gyan.dev/ffmpeg/builds/  build "essentials"
echo Copia el archivo ffmpeg.exe extraido a esta misma carpeta y vuelve a ejecutar este script.
echo.
pause
exit /b 1

:ffmpeg_done
echo.
echo [5/6] Compilando MatrixDownloader.exe...
if exist build rmdir /s /q build
if exist dist rmdir /s /q dist
if exist MatrixDownloader.spec del /q MatrixDownloader.spec
venv_build\Scripts\pyinstaller.exe --onefile --windowed --name MatrixDownloader --add-binary "ffmpeg.exe;." main.py
if errorlevel 1 goto build_failed
goto build_ok

:build_failed
echo [ERROR] PyInstaller fallo. Revisa el mensaje de arriba.
pause
exit /b 1

:build_ok
echo.
echo [6/6] Finalizando...
if exist dist\MatrixDownloader.exe copy /y dist\MatrixDownloader.exe MatrixDownloader.exe >nul
if exist MatrixDownloader.exe goto all_done
echo.
echo [ERROR] La compilacion parece haber fallado.
pause
exit /b 1

:all_done
echo.
echo ===============================================================
echo   EXITO
echo   Ejecutable portable listo: MatrixDownloader.exe
echo   Copia solo ese archivo a cualquier PC Windows.
echo ===============================================================
echo.
pause
exit /b 0

@@PYCODE_MARKER@@
#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
===============================================================
  MATRIX DOWNLOADER // 動画抽出システム
===============================================================

Requisitos:
    pip install -r requirements.txt
    ffmpeg instalado y en el PATH del sistema

NOTA LEGAL:
    Úsala únicamente para descargar contenido del que tengas derechos.
    No está pensada para saltar restricciones de copyright de contenido protegido.
"""

import os
import re
import sys
import shutil
import queue
import random
import threading
import tkinter as tk
from tkinter import ttk, filedialog, messagebox

try:
    import yt_dlp
except ImportError:
    yt_dlp = None


# =========================================================
#  COMPATIBILIDAD CON EJECUTABLE COMPILADO (PyInstaller)
# =========================================================
def app_base_dir() -> str:
    """
    Directorio base de la aplicación:
    - Compilado (.exe, sys.frozen): carpeta donde está el .exe.
    - Script .py: carpeta donde está main.py.
    """
    if getattr(sys, "frozen", False):
        return os.path.dirname(os.path.abspath(sys.executable))
    return os.path.dirname(os.path.abspath(__file__))


def resource_path(relative_path: str) -> str:
    """
    Ruta a un recurso embebido en el ejecutable (ffmpeg.exe, etc.).
    PyInstaller --onefile descomprime los binarios añadidos con --add-binary
    en una carpeta temporal (sys._MEIPASS) en tiempo de ejecución.
    """
    base_path = getattr(sys, "_MEIPASS", app_base_dir())
    return os.path.join(base_path, relative_path)


# =========================================================
#  TEMA VISUAL — MATRIX / CYBERPUNK / JAPONÉS
# =========================================================
BG_COLOR        = "#000000"
PANEL_COLOR     = "#050805"
FG_GREEN        = "#00FF41"
FG_GREEN_DIM    = "#0B6623"
FG_CYAN         = "#00FFF7"
FG_MAGENTA      = "#FF00E6"
FONT_MONO       = ("Consolas", 10)
FONT_MONO_BOLD  = ("Consolas", 10, "bold")
FONT_TITLE      = ("Consolas", 20, "bold")
FONT_JP         = ("MS Gothic", 12)  # fallback gestionado más abajo

KATAKANA = list("ァアィイゥウェエォオカガキギクグケゲコゴサザシジスズセゼソゾタダチヂッツヅテデトドナニヌネノハバパヒビピフブプヘベペホボポマミムメモャヤュユョヨラリルレロワヲンヴ0123456789")

FORMAT_OPTIONS = [
    "動画 (Vídeo) - MP4",
    "動画 (Vídeo) - WEBM",
    "音声 (Audio) - MP3",
    "音声 (Audio) - M4A",
    "音声 (Audio) - WAV",
    "音声 (Audio) - FLAC",
]

VIDEO_QUALITIES = ["最高 (Máxima)", "1080p", "720p", "480p", "360p"]
AUDIO_BITRATES = ["320 kbps", "256 kbps", "192 kbps", "128 kbps"]


def is_playlist_url(url: str) -> bool:
    return "list=" in url


def sanitize_filename(name: str) -> str:
    return re.sub(r'[\\/*?:"<>|]', "_", name)


# =========================================================
#  LLUVIA MATRIX (decorativa, canvas ligero)
# =========================================================
class MatrixRain(tk.Canvas):
    def __init__(self, master, width, height, **kwargs):
        super().__init__(master, width=width, height=height,
                          bg=BG_COLOR, highlightthickness=0, **kwargs)
        self.width = width
        self.height = height
        self.font_size = 14
        self.columns = max(1, width // self.font_size)
        self.drops = [random.randint(-20, 0) for _ in range(self.columns)]
        self.running = True
        self._animate()

    def _animate(self):
        if not self.running:
            return
        self.delete("all")
        for i in range(self.columns):
            x = i * self.font_size
            y = self.drops[i] * self.font_size
            ch = random.choice(KATAKANA)
            color = FG_CYAN if random.random() < 0.05 else FG_GREEN
            self.create_text(x, y, text=ch, fill=color,
                              font=("Consolas", self.font_size), anchor="nw")
            if y > self.height and random.random() > 0.975:
                self.drops[i] = 0
            else:
                self.drops[i] += 1
        self.after(90, self._animate)

    def stop(self):
        self.running = False


# =========================================================
#  APLICACIÓN PRINCIPAL
# =========================================================
class MatrixDownloaderApp(tk.Tk):
    def __init__(self):
        super().__init__()
        self.title("MATRIX DOWNLOADER // 動画抽出システム")
        self.geometry("980x760")
        self.minsize(900, 680)
        self.configure(bg=BG_COLOR)

        self.log_queue = queue.Queue()
        self.entries = {}          # video_id -> dict(title, duration, checked, row_iid)
        self.playlist_title = None
        self.output_dir = os.path.join(os.getcwd(), "descargas")
        os.makedirs(self.output_dir, exist_ok=True)
        self.is_downloading = False
        self.stop_requested = False

        self._check_dependencies()
        self._build_style()
        self._build_ui()
        self._boot_sequence()
        self.after(100, self._poll_queue)

    # -----------------------------------------------------
    def _check_dependencies(self):
        self.ffmpeg_path = self._locate_ffmpeg()
        self.ffmpeg_ok = self.ffmpeg_path is not None
        if yt_dlp is None:
            messagebox.showerror(
                "错误 // ERROR",
                "No se encontró el paquete 'yt-dlp'.\n\n"
                "Instálalo con:\n    pip install -r requirements.txt"
            )

    @staticmethod
    def _locate_ffmpeg():
        """
        Busca ffmpeg en este orden:
        1. Embebido dentro del propio .exe (PyInstaller --add-binary), la
           forma normal cuando se usa el ejecutable portable compilado.
        2. Un ffmpeg.exe/ffmpeg colocado a mano junto al .exe o a main.py
           (permite sustituirlo sin recompilar).
        3. El PATH del sistema (caso de ejecutar desde código fuente).
        Devuelve la ruta completa al binario, o None si no se encuentra.
        """
        exe_name = "ffmpeg.exe" if os.name == "nt" else "ffmpeg"

        embedded = resource_path(exe_name)
        if os.path.isfile(embedded):
            return embedded

        beside_app = os.path.join(app_base_dir(), exe_name)
        if os.path.isfile(beside_app):
            return beside_app

        return shutil.which("ffmpeg")

    # -----------------------------------------------------
    def _build_style(self):
        style = ttk.Style(self)
        try:
            style.theme_use("clam")
        except tk.TclError:
            pass

        style.configure("Treeview",
                         background=PANEL_COLOR,
                         fieldbackground=PANEL_COLOR,
                         foreground=FG_GREEN,
                         rowheight=26,
                         font=FONT_MONO,
                         borderwidth=0)
        style.configure("Treeview.Heading",
                         background="#001a00",
                         foreground=FG_CYAN,
                         font=FONT_MONO_BOLD,
                         borderwidth=0)
        style.map("Treeview",
                  background=[("selected", "#003300")],
                  foreground=[("selected", FG_CYAN)])

        style.configure("TProgressbar",
                         troughcolor=PANEL_COLOR,
                         background=FG_GREEN,
                         bordercolor=BG_COLOR,
                         lightcolor=FG_GREEN,
                         darkcolor=FG_GREEN)

        style.configure("TCombobox",
                         fieldbackground=PANEL_COLOR,
                         background=PANEL_COLOR,
                         foreground=FG_GREEN)

    # -----------------------------------------------------
    def _build_ui(self):
        # --- Cabecera con lluvia Matrix ---
        header = tk.Frame(self, bg=BG_COLOR, height=70)
        header.pack(fill="x", side="top")
        rain = MatrixRain(header, width=980, height=70)
        rain.place(x=0, y=0)
        title_lbl = tk.Label(header, text="MATRIX DOWNLOADER",
                              font=FONT_TITLE, fg=FG_GREEN, bg=BG_COLOR)
        title_lbl.place(relx=0.5, rely=0.35, anchor="center")
        sub_lbl = tk.Label(header, text="動画抽出システム // v1.0 // ローカル実行専用",
                            font=("Consolas", 10), fg=FG_CYAN, bg=BG_COLOR)
        sub_lbl.place(relx=0.5, rely=0.72, anchor="center")

        # --- Bloque URL ---
        url_frame = tk.Frame(self, bg=BG_COLOR, pady=8)
        url_frame.pack(fill="x", padx=14)

        tk.Label(url_frame, text="URL >", font=FONT_MONO_BOLD,
                 fg=FG_CYAN, bg=BG_COLOR).pack(side="left")

        self.url_var = tk.StringVar()
        url_entry = tk.Entry(url_frame, textvariable=self.url_var,
                              font=FONT_MONO, bg=PANEL_COLOR, fg=FG_GREEN,
                              insertbackground=FG_GREEN, relief="flat",
                              highlightthickness=1, highlightbackground=FG_GREEN_DIM,
                              highlightcolor=FG_CYAN)
        url_entry.pack(side="left", fill="x", expand=True, padx=8, ipady=4)
        url_entry.bind("<Return>", lambda e: self.analyze_url())

        self.analyze_btn = self._make_button(url_frame, "解析 ANALIZAR", self.analyze_url)
        self.analyze_btn.pack(side="left")

        # --- Opciones de formato/calidad/carpeta ---
        opts_frame = tk.Frame(self, bg=BG_COLOR, pady=6)
        opts_frame.pack(fill="x", padx=14)

        tk.Label(opts_frame, text="形式 Formato:", font=FONT_MONO,
                 fg=FG_GREEN, bg=BG_COLOR).grid(row=0, column=0, sticky="w", padx=(0, 6))
        self.format_var = tk.StringVar(value=FORMAT_OPTIONS[0])
        format_cb = ttk.Combobox(opts_frame, textvariable=self.format_var,
                                  values=FORMAT_OPTIONS, state="readonly",
                                  font=FONT_MONO, width=22)
        format_cb.grid(row=0, column=1, padx=(0, 16))
        format_cb.bind("<<ComboboxSelected>>", self._on_format_change)

        tk.Label(opts_frame, text="品質 Calidad:", font=FONT_MONO,
                 fg=FG_GREEN, bg=BG_COLOR).grid(row=0, column=2, sticky="w", padx=(0, 6))
        self.quality_var = tk.StringVar(value=VIDEO_QUALITIES[0])
        self.quality_cb = ttk.Combobox(opts_frame, textvariable=self.quality_var,
                                        values=VIDEO_QUALITIES, state="readonly",
                                        font=FONT_MONO, width=16)
        self.quality_cb.grid(row=0, column=3, padx=(0, 16))

        tk.Label(opts_frame, text="出力 Carpeta:", font=FONT_MONO,
                 fg=FG_GREEN, bg=BG_COLOR).grid(row=1, column=0, sticky="w", pady=(8, 0))
        self.folder_var = tk.StringVar(value=self.output_dir)
        folder_entry = tk.Entry(opts_frame, textvariable=self.folder_var,
                                 font=FONT_MONO, bg=PANEL_COLOR, fg=FG_GREEN,
                                 insertbackground=FG_GREEN, relief="flat",
                                 highlightthickness=1, highlightbackground=FG_GREEN_DIM,
                                 width=50)
        folder_entry.grid(row=1, column=1, columnspan=2, sticky="we", pady=(8, 0))
        browse_btn = self._make_button(opts_frame, "選択", self._choose_folder, small=True)
        browse_btn.grid(row=1, column=3, sticky="w", pady=(8, 0))

        # --- Lista de vídeos (playlist o único) ---
        list_frame = tk.Frame(self, bg=BG_COLOR, pady=8)
        list_frame.pack(fill="both", expand=True, padx=14)

        toolbar = tk.Frame(list_frame, bg=BG_COLOR)
        toolbar.pack(fill="x")
        tk.Label(toolbar, text="リスト // Elementos detectados",
                 font=FONT_MONO_BOLD, fg=FG_CYAN, bg=BG_COLOR).pack(side="left")
        self._make_button(toolbar, "全選択", self.select_all, small=True).pack(side="right", padx=2)
        self._make_button(toolbar, "全解除", self.select_none, small=True).pack(side="right", padx=2)

        tree_container = tk.Frame(list_frame, bg=BG_COLOR)
        tree_container.pack(fill="both", expand=True, pady=(4, 0))

        columns = ("check", "title", "duration")
        self.tree = ttk.Treeview(tree_container, columns=columns, show="headings",
                                  selectmode="none")
        self.tree.heading("check", text="✓")
        self.tree.heading("title", text="タイトル / Título")
        self.tree.heading("duration", text="時間 / Duración")
        self.tree.column("check", width=40, anchor="center", stretch=False)
        self.tree.column("title", width=620, anchor="w")
        self.tree.column("duration", width=100, anchor="center", stretch=False)
        self.tree.pack(side="left", fill="both", expand=True)

        scrollbar = ttk.Scrollbar(tree_container, orient="vertical", command=self.tree.yview)
        scrollbar.pack(side="right", fill="y")
        self.tree.configure(yscrollcommand=scrollbar.set)
        self.tree.bind("<Button-1>", self._on_tree_click)

        # --- Progreso y log ---
        progress_frame = tk.Frame(self, bg=BG_COLOR, pady=6)
        progress_frame.pack(fill="x", padx=14)

        self.progress_label = tk.Label(progress_frame, text="待機中 // En espera",
                                        font=FONT_MONO, fg=FG_GREEN, bg=BG_COLOR)
        self.progress_label.pack(anchor="w")
        self.progress_bar = ttk.Progressbar(progress_frame, style="TProgressbar",
                                             mode="determinate", maximum=100)
        self.progress_bar.pack(fill="x", pady=(2, 8))

        self.download_btn = self._make_button(progress_frame, "▶ ダウンロード開始 DESCARGAR",
                                                self.start_download)
        self.download_btn.pack(side="left")
        self.cancel_btn = self._make_button(progress_frame, "■ CANCELAR",
                                             self.cancel_download, small=True)
        self.cancel_btn.pack(side="left", padx=8)
        self.cancel_btn.configure(state="disabled")

        log_frame = tk.Frame(self, bg=BG_COLOR)
        log_frame.pack(fill="both", expand=False, padx=14, pady=(0, 12))
        tk.Label(log_frame, text="ログ // Consola", font=FONT_MONO_BOLD,
                 fg=FG_CYAN, bg=BG_COLOR).pack(anchor="w")
        self.log_text = tk.Text(log_frame, height=9, bg="#000500", fg=FG_GREEN,
                                 insertbackground=FG_GREEN, font=("Consolas", 9),
                                 relief="flat", highlightthickness=1,
                                 highlightbackground=FG_GREEN_DIM)
        self.log_text.pack(fill="both", expand=True)
        self.log_text.configure(state="disabled")

        if not self.ffmpeg_ok:
            self._log("[AVISO] ffmpeg no detectado en el PATH. La conversión de "
                       "audio/remux de vídeo puede fallar. Instálalo antes de descargar.")

    # -----------------------------------------------------
    def _make_button(self, parent, text, command, small=False):
        pad = (8, 4) if small else (14, 8)
        btn = tk.Button(parent, text=text, command=command,
                         bg="#001a00", fg=FG_GREEN, activebackground="#003300",
                         activeforeground=FG_CYAN, font=FONT_MONO_BOLD,
                         relief="flat", cursor="hand2",
                         highlightthickness=1, highlightbackground=FG_GREEN_DIM,
                         padx=pad[0], pady=pad[1])
        btn.bind("<Enter>", lambda e: btn.configure(fg=FG_CYAN))
        btn.bind("<Leave>", lambda e: btn.configure(fg=FG_GREEN))
        return btn

    def _on_format_change(self, event=None):
        fmt = self.format_var.get()
        if "動画" in fmt:
            self.quality_cb.configure(values=VIDEO_QUALITIES)
            self.quality_var.set(VIDEO_QUALITIES[0])
        else:
            self.quality_cb.configure(values=AUDIO_BITRATES)
            self.quality_var.set(AUDIO_BITRATES[0])

    def _choose_folder(self):
        folder = filedialog.askdirectory(initialdir=self.output_dir)
        if folder:
            self.output_dir = folder
            self.folder_var.set(folder)

    # -----------------------------------------------------
    def _boot_sequence(self):
        lines = [
            "SYSTEM BOOT // システム起動中...",
            "初期化 Inicializando módulos...",
            "yt-dlp エンジン ロード完了" if yt_dlp else "[ERROR] yt-dlp no cargado",
            "READY. Pega una URL de YouTube (vídeo o playlist) y pulsa ANALIZAR.",
        ]
        for l in lines:
            self._log(l)

    def _log(self, msg):
        self.log_text.configure(state="normal")
        self.log_text.insert("end", f"> {msg}\n")
        self.log_text.see("end")
        self.log_text.configure(state="disabled")

    def _poll_queue(self):
        try:
            while True:
                kind, payload = self.log_queue.get_nowait()
                if kind == "log":
                    self._log(payload)
                elif kind == "progress":
                    percent, label = payload
                    self.progress_bar["value"] = percent
                    self.progress_label.configure(text=label)
                elif kind == "done":
                    self._on_download_finished(payload)
                elif kind == "tree_populate":
                    self._populate_tree(payload)
                elif kind == "analyze_error":
                    messagebox.showerror("エラー // Error", payload)
                    self.analyze_btn.configure(state="normal", text="解析 ANALIZAR")
        except queue.Empty:
            pass
        self.after(100, self._poll_queue)

    # -----------------------------------------------------
    #  ANÁLISIS DE URL (vídeo suelto o playlist)
    # -----------------------------------------------------
    def analyze_url(self):
        if yt_dlp is None:
            messagebox.showerror("エラー", "yt-dlp no está instalado.")
            return
        url = self.url_var.get().strip()
        if not url:
            messagebox.showwarning("警告 // Aviso", "Introduce una URL de YouTube.")
            return

        self.analyze_btn.configure(state="disabled", text="解析中...")
        self.tree.delete(*self.tree.get_children())
        self.entries.clear()
        self._log(f"URL 解析中 // Analizando: {url}")

        threading.Thread(target=self._analyze_worker, args=(url,), daemon=True).start()

    def _analyze_worker(self, url):
        try:
            ydl_opts = {
                "quiet": True,
                "no_warnings": True,
                "extract_flat": "in_playlist",
                "skip_download": True,
            }
            with yt_dlp.YoutubeDL(ydl_opts) as ydl:
                info = ydl.extract_info(url, download=False)

            items = []
            if "entries" in info and info["entries"]:
                self.playlist_title = info.get("title", "playlist")
                for entry in info["entries"]:
                    if entry is None:
                        continue
                    vid = entry.get("id")
                    title = entry.get("title") or vid
                    duration = entry.get("duration")
                    items.append({
                        "id": vid,
                        "title": title,
                        "duration": self._format_duration(duration),
                    })
            else:
                self.playlist_title = None
                items.append({
                    "id": info.get("id"),
                    "title": info.get("title") or info.get("id"),
                    "duration": self._format_duration(info.get("duration")),
                })

            self.log_queue.put(("log", f"{len(items)} elemento(s) encontrado(s)."))
            self.log_queue.put(("tree_populate", items))

        except Exception as exc:
            self.log_queue.put(("analyze_error", f"No se pudo analizar la URL:\n{exc}"))
        finally:
            self.log_queue.put(("log", "解析完了 // Análisis finalizado."))
            self.after(0, lambda: self.analyze_btn.configure(state="normal", text="解析 ANALIZAR"))

    @staticmethod
    def _format_duration(seconds):
        if not seconds:
            return "--:--"
        seconds = int(seconds)
        h, rem = divmod(seconds, 3600)
        m, s = divmod(rem, 60)
        if h:
            return f"{h}:{m:02d}:{s:02d}"
        return f"{m}:{s:02d}"

    def _populate_tree(self, items):
        for item in items:
            vid = item["id"]
            iid = self.tree.insert("", "end", values=("☑", item["title"], item["duration"]))
            self.entries[iid] = {
                "id": vid,
                "title": item["title"],
                "checked": True,
            }

    # -----------------------------------------------------
    def _on_tree_click(self, event):
        region = self.tree.identify("region", event.x, event.y)
        if region != "cell":
            return
        col = self.tree.identify_column(event.x)
        row = self.tree.identify_row(event.y)
        if not row:
            return
        if col == "#1":  # columna checkbox
            self._toggle_row(row)

    def _toggle_row(self, row):
        entry = self.entries.get(row)
        if entry is None:
            return
        entry["checked"] = not entry["checked"]
        mark = "☑" if entry["checked"] else "☐"
        vals = list(self.tree.item(row, "values"))
        vals[0] = mark
        self.tree.item(row, values=vals)

    def select_all(self):
        for row in self.entries:
            self.entries[row]["checked"] = True
            vals = list(self.tree.item(row, "values"))
            vals[0] = "☑"
            self.tree.item(row, values=vals)

    def select_none(self):
        for row in self.entries:
            self.entries[row]["checked"] = False
            vals = list(self.tree.item(row, "values"))
            vals[0] = "☐"
            self.tree.item(row, values=vals)

    # -----------------------------------------------------
    #  CONSTRUCCIÓN DE OPCIONES yt-dlp
    # -----------------------------------------------------
    def _build_ydl_opts(self, output_template):
        fmt = self.format_var.get()
        quality = self.quality_var.get()
        is_video = "動画" in fmt

        opts = {
            "outtmpl": output_template,
            "noplaylist": True,
            "quiet": True,
            "no_warnings": True,
            "progress_hooks": [self._progress_hook],
            "postprocessor_hooks": [],
        }
        if self.ffmpeg_path:
            opts["ffmpeg_location"] = self.ffmpeg_path

        if is_video:
            height_map = {
                "最高 (Máxima)": None,
                "1080p": 1080,
                "720p": 720,
                "480p": 480,
                "360p": 360,
            }
            height = height_map.get(quality)
            ext = "mp4" if "MP4" in fmt else "webm"

            if height:
                opts["format"] = (
                    f"bestvideo[height<={height}][ext={ext}]+bestaudio[ext=m4a]/"
                    f"bestvideo[height<={height}]+bestaudio/"
                    f"best[height<={height}]"
                )
            else:
                opts["format"] = (
                    f"bestvideo[ext={ext}]+bestaudio[ext=m4a]/bestvideo+bestaudio/best"
                )
            opts["merge_output_format"] = ext

        else:
            codec_map = {
                "音声 (Audio) - MP3": "mp3",
                "音声 (Audio) - M4A": "m4a",
                "音声 (Audio) - WAV": "wav",
                "音声 (Audio) - FLAC": "flac",
            }
            codec = codec_map.get(fmt, "mp3")
            bitrate = quality.split()[0] if quality else "192"

            opts["format"] = "bestaudio/best"
            opts["postprocessors"] = [{
                "key": "FFmpegExtractAudio",
                "preferredcodec": codec,
                "preferredquality": bitrate,
            }]

        return opts

    # -----------------------------------------------------
    #  DESCARGA
    # -----------------------------------------------------
    def start_download(self):
        if yt_dlp is None:
            messagebox.showerror("エラー", "yt-dlp no está instalado.")
            return
        if not self.entries:
            messagebox.showwarning("警告", "Primero analiza una URL.")
            return
        if not self.ffmpeg_ok:
            if not messagebox.askyesno(
                "ffmpeg no encontrado",
                "No se detectó ffmpeg en el PATH. Algunas conversiones pueden fallar.\n"
                "¿Continuar de todas formas?"
            ):
                return

        selected = [e for e in self.entries.values() if e["checked"]]
        if not selected:
            messagebox.showwarning("警告", "No hay ningún elemento seleccionado.")
            return

        self.is_downloading = True
        self.stop_requested = False
        self.download_btn.configure(state="disabled")
        self.cancel_btn.configure(state="normal")
        os.makedirs(self.folder_var.get(), exist_ok=True)

        threading.Thread(target=self._download_worker, args=(selected,), daemon=True).start()

    def cancel_download(self):
        self.stop_requested = True
        self._log("キャンセル要求 // Cancelación solicitada, terminando el elemento actual...")

    def _download_worker(self, selected):
        total = len(selected)
        out_dir = self.folder_var.get()

        for idx, entry in enumerate(selected, start=1):
            if self.stop_requested:
                self.log_queue.put(("log", "ダウンロード中止 // Descarga cancelada por el usuario."))
                break

            title = entry["title"]
            vid = entry["id"]
            url = f"https://www.youtube.com/watch?v={vid}"
            safe_title = sanitize_filename(title)
            out_tmpl = os.path.join(out_dir, f"{safe_title}.%(ext)s")

            self.log_queue.put(("log", f"[{idx}/{total}] 開始 Iniciando: {title}"))
            self.log_queue.put(("progress", (0, f"[{idx}/{total}] {title}")))

            ydl_opts = self._build_ydl_opts(out_tmpl)
            try:
                with yt_dlp.YoutubeDL(ydl_opts) as ydl:
                    ydl.download([url])
                self.log_queue.put(("log", f"[{idx}/{total}] 完了 Completado: {title}"))
            except Exception as exc:
                self.log_queue.put(("log", f"[{idx}/{total}] 失敗 ERROR en '{title}': {exc}"))

        self.log_queue.put(("done", total))

    def _progress_hook(self, d):
        if d.get("status") == "downloading":
            total = d.get("total_bytes") or d.get("total_bytes_estimate")
            downloaded = d.get("downloaded_bytes", 0)
            if total:
                percent = downloaded / total * 100
            else:
                percent = 0
            speed = d.get("speed")
            speed_str = f"{speed/1024:.0f} KB/s" if speed else ""
            self.log_queue.put(("progress", (percent, f"{percent:.1f}%  {speed_str}")))
        elif d.get("status") == "finished":
            self.log_queue.put(("progress", (100, "後処理中 // Procesando (ffmpeg)...")))

    def _on_download_finished(self, total):
        self.is_downloading = False
        self.download_btn.configure(state="normal")
        self.cancel_btn.configure(state="disabled")
        self.progress_bar["value"] = 0
        self.progress_label.configure(text="完了 // Finalizado")
        self._log(f"すべて完了 // Proceso terminado ({total} elemento(s) procesados).")
        messagebox.showinfo("完了 // Completado", "Descarga finalizada. Revisa la carpeta de salida.")


# =========================================================
if __name__ == "__main__":
    app = MatrixDownloaderApp()
    app.mainloop()
