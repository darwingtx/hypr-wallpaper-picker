#!/usr/bin/env python3
"""Galeria de wallpapers online (wallhaven.cc) para el shell de illogical-impulse.

Muestra miniaturas ligeras (no descarga la imagen completa), y solo cuando
eliges una se descarga en su resolucion original, se ajusta a la pantalla y
se aplica junto con el tema Material You.

Uso: wallpaper_gallery.py [consulta]
"""

import gi

gi.require_version("Gtk", "4.0")
gi.require_version("Gdk", "4.0")
from gi.repository import Gtk, Gdk, GLib, Gio  # noqa: E402

import json
import os
import shutil
import subprocess
import sys
import threading
import urllib.parse
import urllib.request

API = "https://wallhaven.cc/api/v1/search"
CACHE = os.path.expanduser("~/.cache/wallpaper-gallery")
DEST = os.path.expanduser("~/Pictures/Wallpapers")
SCRIPTS = os.path.dirname(os.path.abspath(__file__))
APPLY_SCRIPT = os.path.join(SCRIPTS, "wallpaper_apply.sh")

PURITY = "100"  # solo SFW
MIN_RES = "1920x1200"

CATEGORIES = [("general", "100"), ("anime", "010"), ("personas", "001"), ("todo", "111")]
SORTS = [("aleatorio", "random"), ("toplist", "toplist"), ("relevancia", "relevance"),
         ("mas vistos", "views"), ("nuevos", "date_added")]

UA = "Mozilla/5.0 (X11; Linux x86_64) wallpaper-gallery/1.0"


def http_get(url, timeout=30):
    req = urllib.request.Request(url, headers={"User-Agent": UA})
    with urllib.request.urlopen(req, timeout=timeout) as r:
        return r.read()


def http_get_file(url, dest, timeout=120):
    req = urllib.request.Request(url, headers={"User-Agent": UA})
    with urllib.request.urlopen(req, timeout=timeout) as r, open(dest, "wb") as f:
        shutil.copyfileobj(r, f)


class Gallery(Gtk.Application):
    def __init__(self):
        super().__init__(application_id="io.github.chewi.wallpapergallery",
                         flags=Gio.ApplicationFlags.FLAGS_NONE)
        self.results = []
        self.thumbs = {}   # id -> ruta de la miniatura
        self.selected = None
        self.busy = False
        self.window = None

    # --- UI ---------------------------------------------------------------
    def do_activate(self):
        if self.window is None:
            self.window = self.build_window()
            self.window.present()
            GLib.idle_add(self.do_search)
        else:
            self.window.present()

    def build_window(self):
        win = Gtk.ApplicationWindow(application=self, title="Wallpapers")
        win.set_default_size(1400, 820)

        # --- cabecera ---
        header = Gtk.HeaderBar()
        win.set_titlebar(header)

        self.search_entry = Gtk.SearchEntry()
        self.search_entry.set_placeholder_text("Buscar por etiquetas...")
        self.search_entry.set_hexpand(True)
        self.search_entry.connect("activate", lambda *_: self.do_search())
        header.props.title_widget = self.search_entry

        self.cat_dd = Gtk.DropDown.new_from_strings([c[0] for c in CATEGORIES])
        self.sort_dd = Gtk.DropDown.new_from_strings([s[0] for s in SORTS])
        self.count_spin = Gtk.SpinButton.new_with_range(4, 48, 4)
        self.count_spin.set_value(24)
        self.count_spin.set_tooltip_text("Cuantas miniaturas mostrar")

        for w in (self.cat_dd, self.sort_dd, self.count_spin):
            w.set_valign(Gtk.Align.CENTER)
        header.pack_start(self.cat_dd)
        header.pack_start(self.sort_dd)
        header.pack_end(self.count_spin)

        btn = Gtk.Button(label="Buscar")
        btn.set_tooltip_text("Buscar wallpapers")
        btn.connect("clicked", lambda *_: self.do_search())
        header.pack_end(btn)

        # --- cuerpo ---
        paned = Gtk.Paned(orientation=Gtk.Orientation.HORIZONTAL)
        paned.set_position(880)

        self.flow = Gtk.FlowBox()
        self.flow.set_selection_mode(Gtk.SelectionMode.SINGLE)
        self.flow.set_homogeneous(True)
        self.flow.set_max_children_per_line(5)
        self.flow.set_min_children_per_line(3)
        scroller = Gtk.ScrolledWindow()
        scroller.set_child(self.flow)
        paned.set_start_child(scroller)

        # panel derecho: preview grande + aplicar
        right = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=10)
        right.set_margin_top(12)
        right.set_margin_bottom(12)
        right.set_margin_end(12)
        right.set_size_request(360, -1)
        self.preview = Gtk.Picture()
        self.preview.set_content_fit(Gtk.ContentFit.COVER)
        self.preview.set_size_request(380, 480)
        right.append(self.preview)

        self.info = Gtk.Label(label="Elige una miniatura")
        self.info.set_wrap(True)
        self.info.set_justify(Gtk.Justification.CENTER)
        right.append(self.info)

        self.apply_btn = Gtk.Button(label="Aplicar como fondo")
        self.apply_btn.add_css_class("suggested-action")
        self.apply_btn.set_sensitive(False)
        self.apply_btn.connect("clicked", lambda *_: self.do_apply())
        right.append(self.apply_btn)

        paned.set_end_child(right)

        self.status = Gtk.Label(label="")
        self.status.set_margin_start(12)
        self.status.set_margin_end(12)
        self.status.set_margin_bottom(8)

        box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL)
        box.append(paned)
        box.append(self.status)
        win.set_child(box)
        return win

    # --- datos ------------------------------------------------------------
    def do_search(self):
        if self.busy:
            return
        self.busy = True
        self.apply_btn.set_sensitive(False)
        self.status.set_text("Buscando...")
        self.flow.remove_all()
        self.results = []
        self.thumbs = {}

        query = self.search_entry.get_text().strip()
        cats = CATEGORIES[self.cat_dd.get_selected()][1]
        sort = SORTS[self.sort_dd.get_selected()][1]
        count = int(self.count_spin.get_value())

        url = (f"{API}?purity={PURITY}&categories={cats}&atleast={MIN_RES}"
               f"&sorting={sort}")
        if query:
            url += "&q=" + urllib.parse.quote(query)

        def worker():
            try:
                data = json.loads(http_get(url).decode())
                items = data.get("data", [])[:count]
            except Exception as e:  # noqa: BLE001
                GLib.idle_add(self.search_failed, str(e))
                return
            GLib.idle_add(self.on_results, items)

        threading.Thread(target=worker, daemon=True).start()

    def search_failed(self, error):
        self.busy = False
        self.status.set_text(f"Error: {error}")
        return False

    def on_results(self, items):
        self.results = items
        self.status.set_text(f"{len(items)} resultados. Descargando miniaturas...")
        os.makedirs(CACHE, exist_ok=True)
        for item in items:
            threading.Thread(target=self.load_thumb, args=(item,), daemon=True).start()
        return False

    def load_thumb(self, item):
        wid = item["id"]
        url = item.get("thumbs", {}).get("large") or item.get("thumbs", {}).get("original")
        if not url:
            return
        path = os.path.join(CACHE, f"{wid}.jpg")
        try:
            if not os.path.exists(path):
                http_get_file(url, path)
        except Exception:  # noqa: BLE001
            return
        GLib.idle_add(self.add_thumb, item, path)

    def add_thumb(self, item, path):
        self.thumbs[item["id"]] = path
        pic = Gtk.Picture()
        try:
            pic.set_paintable(Gdk.Texture.new_from_filename(path))
        except GLib.Error:
            return False
        pic.set_content_fit(Gtk.ContentFit.COVER)
        pic.set_size_request(230, 130)

        btn = Gtk.ToggleButton()
        btn.set_child(pic)
        btn.set_tooltip_text(f"{item['id']}  {item.get('resolution', '')}\nDoble clic para aplicar")
        btn.connect("clicked", lambda _b, it=item: self.on_click(it))
        gesture = Gtk.GestureClick()
        gesture.set_button(1)
        gesture.connect("pressed", self.on_double_click, item)
        btn.add_controller(gesture)
        self.flow.append(btn)
        btn.set_visible(True)
        self.flow.set_visible(True)

        if len(self.thumbs) == len(self.results):
            self.busy = False
            self.status.set_text(f"{len(self.results)} miniaturas. Elige una para ver y aplicar.")
        return False

    def on_click(self, item):
        self.selected = item
        self.apply_btn.set_sensitive(True)
        self.info.set_text(f"{item['id']}  -  {item.get('resolution', '')}  -  {item.get('category', '')}")
        # preview grande: descarga la version 1280 solo al pasar el raton
        threading.Thread(target=self.load_preview, args=(item,), daemon=True).start()

    def on_double_click(self, gesture, n_press, x, y, item):
        if n_press == 2:
            self.on_click(item)
            self.do_apply()
        return False

    def load_preview(self, item):
        url = item.get("thumbs", {}).get("large")
        if not url:
            return
        path = os.path.join(CACHE, f"big-{item['id']}.jpg")
        try:
            if not os.path.exists(path):
                http_get_file(url, path)
        except Exception:  # noqa: BLE001
            return
        GLib.idle_add(self.show_preview, path)

    def show_preview(self, path):
        try:
            self.preview.set_paintable(Gdk.Texture.new_from_filename(path))
        except GLib.Error:
            pass
        return False

    def on_selected(self, flow):
        pass

    # --- aplicar ----------------------------------------------------------    def do_apply(self):
        if not self.selected or self.busy:
            return
        self.busy = True
        self.apply_btn.set_sensitive(False)
        self.status.set_text("Descargando imagen original...")
        item = self.selected
        threading.Thread(target=self.apply_worker, args=(item,), daemon=True).start()

    def apply_worker(self, item):
        wid = item["id"]
        url = item["path"]
        ext = url.rsplit(".", 1)[-1].lower()
        if ext not in ("jpg", "jpeg", "png", "webp"):
            ext = "jpg"
        os.makedirs(DEST, exist_ok=True)
        dest = os.path.join(DEST, f"wallhaven-{wid}.{ext}")
        try:
            http_get_file(url, dest)
        except Exception as e:  # noqa: BLE001
            GLib.idle_add(self.apply_failed, str(e))
            return

        # ajusta a la resolucion de la pantalla
        if shutil.which("magick"):
            tmp = f"{dest}.tmp.{ext}"
            args = ["magick", dest, "-resize", f"{MIN_RES}^", "-gravity", "center",
                    "-extent", MIN_RES]
            if ext in ("jpg", "jpeg"):
                args += ["-quality", "90"]
            args.append(tmp)
            if subprocess.run(args, capture_output=True).returncode == 0:
                os.replace(tmp, dest)
            elif os.path.exists(tmp):
                os.remove(tmp)

        subprocess.run([APPLY_SCRIPT, dest], capture_output=True)
        GLib.idle_add(self.apply_done, os.path.basename(dest))

    def apply_failed(self, error):
        self.busy = False
        self.status.set_text(f"Error al aplicar: {error}")
        self.apply_btn.set_sensitive(True)
        return False

    def apply_done(self, name):
        self.status.set_text(f"Wallpaper aplicado: {name}")
        self.apply_btn.set_sensitive(True)
        GLib.timeout_add(1200, self.close)
        return False

    def close(self):
        if self.window:
            self.window.close()
        return False


def main():
    app = Gallery()
    if len(sys.argv) > 1:
        app.connect("activate", lambda a: None)
    sys.exit(app.run(sys.argv))


if __name__ == "__main__":
    main()
