#!/usr/bin/env python3
"""Convierte un extracto de OpenStreetMap (.osm.pbf) en el archivo de mapa de MotoLink (.cfmap).

Uso: build_cfmap.py entrada.osm.pbf salida.cfmap [--bbox lon0,lat0,lon1,lat1] [--date AAAA-MM-DDTHH:MM:SSZ]

El archivo guarda, por cuadros de 0,01° (unos 1,1 km), las calles (clase, sentido, nombre y
puntos), los parques, el agua y los ríos, comprimidos cada uno por separado (deflate sin
cabecera). Más una tabla de nombres y una lista de lugares para buscar sin internet.
La app lo lee directamente (App/OSM/OSMMapData.swift). Datos © OpenStreetMap (ODbL).

Formato (little-endian):
  cabecera  "CFMAP1\\0\\0", u32 versión, u32 cuadros, u32 nombres, u32 lugares,
            i32 lon0, i32 lat0 (1e-6°, origen de la cuadrícula), i32 paso (1e-6°),
            u32 columnas, u32 filas, u64 fecha de los datos (unix),
            u64 posición de los nombres, u64 de los lugares, u64 del índice, u64 de los datos
  nombres   u32 n, n × u32 desplazamiento, UTF-8 seguido (desplazamientos relativos al texto)
  lugares   n × (i32 lon, i32 lat, u32 nombre, u8 tipo, u8 relleno, u16 municipio)
            tipo: el bit 0x80 marca otro nombre (alt_name…) del lugar anterior. Versión 2: los
            primeros lugares son los departamentos (41) y municipios (40) de OpenStreetMap, y el
            u16 de cada lugar es el índice de su municipio (de su departamento, en un municipio;
            0xFFFF si no hay). En la versión 1 ese campo no existía (relleno a cero).
  índice    n × (u32 clave = fila*columnas+columna, u32 desplazamiento, u32 tamaño, u32 tamaño sin comprimir)
  datos     por cuadro (deflate): u16 calles, u16 áreas, u16 líneas y luego cada una:
            calle: u8 clase|banderas, u8 sentido, u32 nombre, u16 n, puntos
            área:  u8 tipo, u16 anillos, por anillo u16 n, puntos
            línea: u8 tipo, u16 n, puntos
            puntos: el primero relativo al origen del cuadro y los demás como diferencia con el
            anterior, i16 x (lon) e i16 y (lat) en 1e-6°.
"""
import math
import struct
import sys
import time
import zlib
from datetime import datetime, timezone

import numpy as np
import osmium

STEP = 10000          # 0,01° en 1e-6°
MAX_SEG = 250.0       # metros: los tramos más largos se parten para que caigan en todos sus cuadros
NONE = 0xFFFFFFFF

CLASSES = {
    'motorway': 7, 'trunk': 6, 'primary': 5, 'secondary': 4, 'tertiary': 3,
    'motorway_link': 5, 'trunk_link': 5, 'primary_link': 4, 'secondary_link': 3, 'tertiary_link': 3,
    'unclassified': 2, 'residential': 2, 'living_street': 2, 'road': 2,
    'service': 1, 'track': 1,
}
LINKS = {'motorway_link', 'trunk_link', 'primary_link', 'secondary_link', 'tertiary_link'}
PARK = {('leisure', 'park'), ('leisure', 'garden'), ('leisure', 'recreation_ground'), ('landuse', 'grass'),
        ('landuse', 'forest'), ('landuse', 'recreation_ground'), ('natural', 'wood'), ('leisure', 'golf_course')}
WATER = {('natural', 'water'), ('water', 'lake'), ('water', 'reservoir'), ('landuse', 'reservoir'),
         ('water', 'river'), ('natural', 'bay')}
RIVERS = {'river': 1, 'canal': 1, 'stream': 2}
PLACES = {'city': 1, 'town': 2, 'village': 3, 'suburb': 4, 'neighbourhood': 5, 'quarter': 5, 'hamlet': 6, 'locality': 6}
AMENITIES = {'fuel': 10, 'hospital': 11, 'clinic': 11, 'doctors': 11, 'dentist': 11, 'police': 12,
             'university': 13, 'college': 13, 'school': 14, 'kindergarten': 14, 'marketplace': 15, 'bank': 16,
             'restaurant': 17, 'fast_food': 17, 'cafe': 17, 'bar': 17, 'pub': 17, 'ice_cream': 17,
             'pharmacy': 18, 'parking': 19, 'place_of_worship': 20}
SHOPS = {'mall': 21, 'supermarket': 22, 'motorcycle': 23, 'car_repair': 24, 'hardware': 25}
TOURISM = {'hotel': 26, 'motel': 26, 'guest_house': 26, 'hostel': 26,
           'attraction': 27, 'museum': 27, 'viewpoint': 27}
EXTRA = {('amenity', 'bus_station'): 28, ('leisure', 'stadium'): 29, ('amenity', 'townhall'): 31,
         ('aeroway', 'aerodrome'): 32}
# Otros nombres con los que también se busca un lugar («Xela», «La Aurora»…).
ALT_NAMES = ('alt_name', 'short_name', 'loc_name', 'official_name', 'name:es')
# Límites administrativos que dan el «dónde» de cada lugar: departamentos y municipios.
ADMIN_LEVELS = {'4': 41, '6': 40}
ALIAS = 0x80
# 0.8.1: terracería (bit 0x40 de las banderas de la calle) y velocidad máxima (los 4 bits altos
# del byte de sentido, en decenas de km/h). Las versiones anteriores de la app los ignoran.
UNPAVED = {'unpaved', 'gravel', 'fine_gravel', 'dirt', 'ground', 'earth', 'mud', 'sand', 'compacted',
           'grass', 'pebblestone', 'rock', 'woodchips', 'grass_paver'}


def parse_maxspeed(v):
    """«60», «60 km/h», «40 mph» → km/h (0 si no se entiende)."""
    if not v:
        return 0
    v = v.strip().lower().split(';')[0]
    mph = 'mph' in v
    digits = ''.join(ch for ch in v if ch.isdigit() or ch == '.')
    try:
        n = float(digits)
    except ValueError:
        return 0
    if mph:
        n *= 1.609
    return int(n) if 5 <= n <= 150 else 0
# 0.7.2: todos los demás lugares con nombre también se buscan (negocios, oficinas, bodegas,
# edificios, colegios dibujados como edificio…). 33 = negocio o lugar; 34 = residencial.
BUSINESS = 33
RESIDENTIAL = 34
GENERIC_KEYS = ('amenity', 'shop', 'tourism', 'office', 'craft', 'healthcare', 'leisure', 'club',
                'building', 'man_made', 'emergency', 'historic', 'sport')
GENERIC_LANDUSE = {'commercial': BUSINESS, 'industrial': BUSINESS, 'retail': BUSINESS,
                   'residential': RESIDENTIAL, 'religious': BUSINESS, 'education': BUSINESS}
GENERIC_NATURAL = {'peak', 'volcano', 'beach', 'cave_entrance', 'spring'}


def place_kind(t):
    """Tipo de lugar buscable de un objeto (0 si no se busca)."""
    kind = (PLACES.get(t.get('place', '')) or AMENITIES.get(t.get('amenity', '')) or
            SHOPS.get(t.get('shop', '')) or TOURISM.get(t.get('tourism', '')))
    if kind:
        return kind
    for (k, v), extra in EXTRA.items():
        if t.get(k) == v:
            return extra
    if not t.get('name') or t.get('highway') or t.get('boundary') or t.get('route') or t.get('type') == 'route':
        return 0
    if t.get('landuse') in GENERIC_LANDUSE:
        return GENERIC_LANDUSE[t.get('landuse')]
    if t.get('natural') in GENERIC_NATURAL:
        return 27
    for key in GENERIC_KEYS:
        if t.get(key) and t.get(key) != 'no':
            return BUSINESS
    return 0


def q(v):
    return int(round(v * 1e6))


class Reader(osmium.SimpleHandler):
    def __init__(self, bbox):
        super().__init__()
        self.bbox = bbox
        self.roads = []      # (clase, sentido, nombre, [(lon, lat)…])
        self.areas = []      # (tipo, [[(lon, lat)…]…])
        self.lines = []      # (tipo, [(lon, lat)…])
        self.places = []     # (lon, lat, nombre, tipo)
        self.names = {}
        self.admin = []      # (tipo 41/40, nombre, [anillos exteriores])
        self.admin_levels = {}
        self.unpaved = 0
        self.with_maxspeed = 0

    def name_id(self, text):
        if not text:
            return NONE
        text = text.strip()
        if not text:
            return NONE
        i = self.names.get(text)
        if i is None:
            i = len(self.names)
            self.names[text] = i
        return i

    def inside(self, lon, lat):
        if not self.bbox:
            return True
        x0, y0, x1, y1 = self.bbox
        return x0 <= lon <= x1 and y0 <= lat <= y1

    def node(self, n):
        t = n.tags
        kind = place_kind(t)
        name = t.get('name')
        if not kind or not name or not n.location.valid():
            return
        lon, lat = n.location.lon, n.location.lat
        if self.inside(lon, lat):
            self.places.append((q(lon), q(lat), self.name_id(name), kind))
            for alt in self.alt_names(t, name):
                self.places.append((q(lon), q(lat), self.name_id(alt), kind | ALIAS))

    @staticmethod
    def alt_names(t, name):
        out = []
        for key in ALT_NAMES:
            for alt in (t.get(key) or '').split(';'):
                alt = alt.strip()
                if alt and alt != name and alt not in out:
                    out.append(alt)
        return out

    def way(self, w):
        t = w.tags
        hw = t.get('highway')
        try:
            pts = [(n.lon, n.lat) for n in w.nodes]
        except osmium.InvalidLocationError:
            return
        if len(pts) < 2 or (self.bbox and not any(self.inside(*p) for p in pts)):
            return
        if hw in CLASSES:
            if t.get('access') in ('private', 'no') and hw in ('service', 'track'):
                return
            if t.get('motor_vehicle') == 'no' or t.get('motorcycle') == 'no':
                return
            cls = CLASSES[hw]
            flags = cls
            if t.get('junction') in ('roundabout', 'circular'):
                flags |= 0x10
            if hw in LINKS:
                flags |= 0x20
            if hw == 'track' or t.get('surface', '') in UNPAVED or t.get('tracktype') in ('grade3', 'grade4', 'grade5'):
                flags |= 0x40
                self.unpaved += 1
            ow = t.get('oneway', '')
            direction = 0
            if ow in ('yes', 'true', '1') or (ow == '' and (t.get('junction') == 'roundabout' or hw == 'motorway')):
                direction = 1
            elif ow == '-1':
                direction = 2
            if t.get('bridge', 'no') not in ('no', ''):
                direction |= 4
            if t.get('tunnel', 'no') not in ('no', ''):
                direction |= 8
            ms = parse_maxspeed(t.get('maxspeed'))
            if ms:
                direction |= min(15, int(ms / 10 + 0.5)) << 4
                self.with_maxspeed += 1
            name = t.get('name') or t.get('ref') or ''
            self.roads.append((flags, direction, self.name_id(name), pts))
            # Las calles con nombre también se buscan (en su punto medio).
            if name and cls >= 2:
                mid = pts[len(pts) // 2]
                self.places.append((q(mid[0]), q(mid[1]), self.name_id(name), 30))
        elif t.get('waterway') in RIVERS:
            self.lines.append((RIVERS[t.get('waterway')], pts))

    def area(self, a):
        t = a.tags
        if t.get('boundary') == 'administrative':
            level = t.get('admin_level', '')
            self.admin_levels[level] = self.admin_levels.get(level, 0) + 1
            name = t.get('name')
            if level in ADMIN_LEVELS and name:
                try:
                    rings = [[(n.lon, n.lat) for n in outer] for outer in a.outer_rings()]
                    rings = [ring for ring in rings if len(ring) >= 4]
                    if rings:
                        self.admin.append((ADMIN_LEVELS[level], name, rings))
                except osmium.InvalidLocationError:
                    pass
            return
        # Lugares dibujados como edificio o terreno (centros comerciales, hospitales…): se
        # buscan en el centro de su contorno.
        poi = place_kind(t)
        name = t.get('name')
        if poi and name and poi not in PLACES.values():
            try:
                for outer in a.outer_rings():
                    ring = [(n.lon, n.lat) for n in outer]
                    if len(ring) >= 3:
                        lon = sum(p[0] for p in ring) / len(ring)
                        lat = sum(p[1] for p in ring) / len(ring)
                        if self.inside(lon, lat):
                            self.places.append((q(lon), q(lat), self.name_id(name), poi))
                            for alt in self.alt_names(t, name):
                                self.places.append((q(lon), q(lat), self.name_id(alt), poi | ALIAS))
                    break
            except osmium.InvalidLocationError:
                pass
        kind = 0
        for k, v in t:
            if (k, v) in WATER:
                kind = 2
                break
            if (k, v) in PARK:
                kind = 1
        if not kind:
            return
        try:
            for outer in a.outer_rings():
                ring = [(n.lon, n.lat) for n in outer]
                holes = [[(n.lon, n.lat) for n in inner] for inner in a.inner_rings(outer)]
                if len(ring) >= 4 and (not self.bbox or any(self.inside(*p) for p in ring)):
                    self.areas.append((kind, [ring] + [h for h in holes if len(h) >= 4]))
        except osmium.InvalidLocationError:
            pass


def meters(a, b):
    lat = math.radians((a[1] + b[1]) / 2)
    return math.hypot((b[0] - a[0]) * 111320 * math.cos(lat), (b[1] - a[1]) * 110574)


def densify(pts):
    out = [pts[0]]
    for a, b in zip(pts, pts[1:]):
        d = meters(a, b)
        n = int(d // MAX_SEG)
        for i in range(1, n + 1):
            t = i / (n + 1)
            out.append((a[0] + (b[0] - a[0]) * t, a[1] + (b[1] - a[1]) * t))
        out.append(b)
    return out


def tile_of(qx, qy):
    return (qy // STEP, qx // STEP)


def split_by_tile(qpts):
    """Trozos de la polilínea por cuadro: cada tramo va en el cuadro de cada uno de sus extremos."""
    pieces = {}
    for i in range(len(qpts) - 1):
        a, b = qpts[i], qpts[i + 1]
        for key in {tile_of(*a), tile_of(*b)}:
            lst = pieces.setdefault(key, [])
            if lst and lst[-1][-1] == i:
                lst[-1].append(i + 1)
            else:
                lst.append([i, i + 1])
    return pieces


def pack_points(out, pts, ox, oy):
    px, py = ox, oy
    for x, y in pts:
        dx, dy = x - px, y - py
        out += struct.pack('<hh', max(-32768, min(32767, dx)), max(-32768, min(32767, dy)))
        px, py = px + max(-32768, min(32767, dx)), py + max(-32768, min(32767, dy))


def clip_ring(ring, box):
    """Recorte de Sutherland–Hodgman de un anillo (puntos en 1e-6°) a una caja."""
    x0, y0, x1, y1 = box
    def clip(points, inside, cross):
        out = []
        for i in range(len(points)):
            cur, prev = points[i], points[i - 1]
            if inside(cur):
                if not inside(prev):
                    out.append(cross(prev, cur))
                out.append(cur)
            elif inside(prev):
                out.append(cross(prev, cur))
        return out
    def ix(x):
        return lambda p, q_: (x, p[1] + (q_[1] - p[1]) * (x - p[0]) / (q_[0] - p[0]))
    def iy(y):
        return lambda p, q_: (p[0] + (q_[0] - p[0]) * (y - p[1]) / (q_[1] - p[1]), y)
    pts = [tuple(map(float, p)) for p in ring]
    for inside, cross in ((lambda p: p[0] >= x0, ix(x0)), (lambda p: p[0] <= x1, ix(x1)),
                          (lambda p: p[1] >= y0, iy(y0)), (lambda p: p[1] <= y1, iy(y1))):
        if not pts:
            break
        pts = clip(pts, inside, cross)
    return [(int(round(x)), int(round(y))) for x, y in pts]


def simplify(pts, tol):
    """Douglas–Peucker (puntos enteros); conserva el primero y el último."""
    if len(pts) < 3:
        return pts
    keep = [False] * len(pts)
    keep[0] = keep[-1] = True
    stack = [(0, len(pts) - 1)]
    while stack:
        i, j = stack.pop()
        ax, ay = pts[i]
        bx, by = pts[j]
        dx, dy = bx - ax, by - ay
        L = math.hypot(dx, dy) or 1.0
        best, bi = -1.0, -1
        for k in range(i + 1, j):
            px, py = pts[k]
            d = abs(dy * (px - ax) - dx * (py - ay)) / L
            if d > best:
                best, bi = d, k
        if best > tol and bi > 0:
            keep[bi] = True
            stack.append((i, bi))
            stack.append((bi, j))
    return [p for p, k in zip(pts, keep) if k]


def simplify_ring(pts, tol):
    """Douglas–Peucker para un anillo cerrado (el primer punto se repite al final): se parte en
    dos por el punto más lejano al primero, para que el método no se quede sin referencia."""
    if len(pts) < 5:
        return pts
    x0, y0 = pts[0]
    k = max(range(len(pts)), key=lambda i: (pts[i][0] - x0) ** 2 + (pts[i][1] - y0) ** 2)
    if k == 0 or k == len(pts) - 1:
        return pts
    a = simplify(pts[:k + 1], tol)
    b = simplify(pts[k:], tol)
    return a[:-1] + b


def ring_area(arr):
    x, y = arr[:, 0], arr[:, 1]
    return abs(np.dot(x, np.roll(y, 1)) - np.dot(y, np.roll(x, 1))) / 2


def inside_ring(arr, pts):
    """Qué puntos (M×2) caen dentro del anillo (N×2), por el método del rayo."""
    x, y = pts[:, 0], pts[:, 1]
    res = np.zeros(len(pts), dtype=bool)
    xs, ys = arr[:, 0], arr[:, 1]
    xj, yj = np.roll(xs, 1), np.roll(ys, 1)
    for xi, yi, xk, yk in zip(xs, ys, xj, yj):
        if yi == yk:
            continue
        cross = (yi > y) != (yk > y)
        if not cross.any():
            continue
        res ^= cross & (x < (xk - xi) * (y - yi) / (yk - yi) + xi)
    return res


def assign_admin(r):
    """Pone primero los departamentos y municipios y apunta cada lugar a su municipio."""
    polys = []   # (tipo, nombre, [anillos np], área, caja)
    for kind, name, rings in r.admin:
        arrs = []
        for ring in rings:
            qr = simplify_ring([(q(x), q(y)) for x, y in ring], 300)   # unos 33 m
            if len(qr) >= 4:
                arrs.append(np.array(qr, dtype=np.float64))
        if not arrs:
            continue
        area = sum(ring_area(a) for a in arrs)
        allpts = np.concatenate(arrs)
        box = (allpts[:, 0].min(), allpts[:, 1].min(), allpts[:, 0].max(), allpts[:, 1].max())
        polys.append((kind, name, arrs, area, box))
    depts = [p for p in polys if p[0] == 41]
    munis = [p for p in polys if p[0] == 40]
    ordered = depts + munis

    def locate(pts, group, offset):
        best = np.full(len(pts), -1, dtype=np.int64)
        best_area = np.full(len(pts), np.inf)
        for i, (kind, name, arrs, area, box) in enumerate(group):
            m = (pts[:, 0] >= box[0]) & (pts[:, 0] <= box[2]) & (pts[:, 1] >= box[1]) & (pts[:, 1] <= box[3])
            idx = np.nonzero(m)[0]
            if len(idx) == 0:
                continue
            sub = pts[idx]
            hit = np.zeros(len(idx), dtype=bool)
            for a in arrs:
                hit |= inside_ring(a, sub)
            win = idx[hit & (area < best_area[idx])]
            best[win] = offset + i
            best_area[win] = area
        return best

    reps = []
    for kind, name, arrs, area, box in ordered:
        big = max(arrs, key=ring_area)
        reps.append((int(big[:, 0].mean()), int(big[:, 1].mean())))
    admin_places = []
    rep_pts = np.array(reps, dtype=np.float64) if reps else np.zeros((0, 2))
    muni_dept = locate(rep_pts[len(depts):], depts, 0) if len(munis) else np.zeros(0, dtype=np.int64)
    for i, (kind, name, arrs, area, box) in enumerate(ordered):
        parent = 0xFFFF
        if kind == 40 and muni_dept[i - len(depts)] >= 0:
            parent = int(muni_dept[i - len(depts)])
        admin_places.append((reps[i][0], reps[i][1], r.name_id(name), kind, parent))

    pts = np.array([(x, y) for x, y, n, k in r.places], dtype=np.float64) if r.places else np.zeros((0, 2))
    muni = locate(pts, munis, len(depts)) if munis else np.full(len(pts), -1)
    dept = locate(pts, depts, 0) if depts else np.full(len(pts), -1)
    out = list(admin_places)
    for (x, y, n, k), mi, di in zip(r.places, muni, dept):
        owner = int(mi) if mi >= 0 else (int(di) if di >= 0 else 0xFFFF)
        out.append((x, y, n, k, owner))
    print(f'límites: {len(depts)} departamentos, {len(munis)} municipios; niveles en el archivo: '
          f'{dict(sorted(r.admin_levels.items()))}; lugares sin municipio: {int((muni < 0).sum())} de {len(pts)}',
          file=sys.stderr)
    return out


def data_date(src):
    """Fecha de los datos de OpenStreetMap (de la cabecera del archivo, si la trae)."""
    try:
        h = osmium.io.Reader(src, osmium.osm.osm_entity_bits.NOTHING).header()
        ts = h.get('osmosis_replication_timestamp')
        if ts:
            return int(datetime.strptime(ts, '%Y-%m-%dT%H:%M:%SZ').replace(tzinfo=timezone.utc).timestamp())
    except Exception:
        pass
    return None


def build(src, dst, bbox=None, date=None):
    t0 = time.time()
    r = Reader(bbox)
    r.apply_file(src, locations=True, idx='flex_mem')
    print(f'leído: {len(r.roads)} calles, {len(r.areas)} áreas, {len(r.lines)} ríos, {len(r.places)} lugares, '
          f'{len(r.names)} nombres ({time.time() - t0:.0f} s)', file=sys.stderr)
    # Antes de escribir la tabla de nombres: los municipios añaden los suyos.
    places = assign_admin(r)

    tiles = {}   # (fila, col) -> {'roads': [], 'areas': [], 'lines': []}
    def tile(key):
        return tiles.setdefault(key, {'roads': [], 'areas': [], 'lines': []})

    for flags, direction, name, pts in r.roads:
        qpts = [(q(x), q(y)) for x, y in densify(pts)]
        for key, chains in split_by_tile(qpts).items():
            for c in chains:
                tile(key)['roads'].append((flags, direction, name, [qpts[i] for i in c]))
    for kind, pts in r.lines:
        qpts = [(q(x), q(y)) for x, y in densify(pts)]
        qpts = simplify(qpts, 3)
        for key, chains in split_by_tile(qpts).items():
            for c in chains:
                tile(key)['lines'].append((kind, [qpts[i] for i in c]))
    margin = 40   # 4 cm… en 1e-6° son unos 4 m: los bordes de los cuadros vecinos se solapan
    for kind, rings in r.areas:
        qrings = [simplify([(q(x), q(y)) for x, y in ring], 4) for ring in rings]
        xs = [p[0] for p in qrings[0]]
        ys = [p[1] for p in qrings[0]]
        for row in range(min(ys) // STEP, max(ys) // STEP + 1):
            for col in range(min(xs) // STEP, max(xs) // STEP + 1):
                box = (col * STEP - margin, row * STEP - margin, (col + 1) * STEP + margin, (row + 1) * STEP + margin)
                clipped = [clip_ring(ring, box) for ring in qrings]
                clipped = [c for c in clipped if len(c) >= 3]
                if clipped and len(clipped[0]) >= 3:
                    tile((row, col))['areas'].append((kind, clipped))

    keys = sorted(tiles)
    rows = [k[0] for k in keys]
    cols = [k[1] for k in keys]
    row0, col0 = min(rows), min(cols)
    ncols = max(cols) - col0 + 1
    nrows = max(rows) - row0 + 1

    blobs = []
    raw_total = 0
    for key in keys:
        t = tiles[key]
        oy, ox = key[0] * STEP, key[1] * STEP
        out = bytearray(struct.pack('<HHH', len(t['roads']), len(t['areas']), len(t['lines'])))
        for flags, direction, name, pts in t['roads']:
            out += struct.pack('<BBIH', flags, direction, name, len(pts))
            pack_points(out, pts, ox, oy)
        for kind, rings in t['areas']:
            out += struct.pack('<BH', kind, len(rings))
            for ring in rings:
                out += struct.pack('<H', len(ring))
                pack_points(out, ring, ox, oy)
        for kind, pts in t['lines']:
            out += struct.pack('<BH', kind, len(pts))
            pack_points(out, pts, ox, oy)
        c = zlib.compressobj(9, zlib.DEFLATED, -15)
        comp = c.compress(bytes(out)) + c.flush()
        blobs.append(((key[0] - row0) * ncols + (key[1] - col0), comp, len(out)))
        raw_total += len(out)

    names = sorted(r.names.items(), key=lambda kv: kv[1])
    name_bytes = bytearray()
    offsets = []
    for text, _ in names:
        offsets.append(len(name_bytes))
        name_bytes += text.encode('utf-8')
    print(f'calles con velocidad máxima: {r.with_maxspeed}; de terracería: {r.unpaved}')
    name_sec = struct.pack('<I', len(names)) + b''.join(struct.pack('<I', o) for o in offsets) + bytes(name_bytes)
    place_sec = b''.join(struct.pack('<iiIBxH', x, y, n, k, owner) for x, y, n, k, owner in places)

    header_len = 8 + 4 * 4 + 4 * 3 + 4 * 2 + 8 + 8 * 4
    pos_names = header_len
    pos_places = pos_names + len(name_sec)
    pos_index = pos_places + len(place_sec)
    pos_data = pos_index + 16 * len(blobs)
    index = bytearray()
    data = bytearray()
    for key, comp, rawlen in blobs:
        index += struct.pack('<IIII', key, len(data), len(comp), rawlen)
        data += comp
    stamp = date or data_date(src) or int(time.time())
    header = (b'CFMAP1\0\0' + struct.pack('<IIII', 2, len(blobs), len(names), len(places)) +
              struct.pack('<iii', col0 * STEP, row0 * STEP, STEP) + struct.pack('<II', ncols, nrows) +
              struct.pack('<Q', stamp) + struct.pack('<QQQQ', pos_names, pos_places, pos_index, pos_data))
    assert len(header) == header_len
    with open(dst, 'wb') as f:
        f.write(header)
        f.write(name_sec)
        f.write(place_sec)
        f.write(index)
        f.write(data)
    total = header_len + len(name_sec) + len(place_sec) + len(index) + len(data)
    print(f'escrito {dst}: {total / 1e6:.1f} MB ({len(blobs)} cuadros, datos {len(data) / 1e6:.1f} MB '
          f'comprimidos de {raw_total / 1e6:.1f} MB; nombres {len(name_sec) / 1e6:.1f} MB; '
          f'lugares {len(place_sec) / 1e6:.1f} MB) en {time.time() - t0:.0f} s', file=sys.stderr)


if __name__ == '__main__':
    args = sys.argv[1:]
    bbox = None
    if '--bbox' in args:
        i = args.index('--bbox')
        bbox = tuple(float(v) for v in args[i + 1].split(','))
        del args[i:i + 2]
    date = None
    if '--date' in args:
        i = args.index('--date')
        date = int(datetime.strptime(args[i + 1], '%Y-%m-%dT%H:%M:%SZ').replace(tzinfo=timezone.utc).timestamp())
        del args[i:i + 2]
    build(args[0], args[1], bbox, date)
