#!/usr/bin/env python3
# Genera "Latinoamericano (Windows).keylayout": la distribucion Latinoamericana de Windows (KBDLA) para macOS.
# AltGr (Alt derecho) = Opcion. Ejemplos: AltGr+Q = @, AltGr+'= \, AltGr++ = ~, AltGr+{ = ^, AltGr+} = `.
# ´ y ¨ son teclas muertas (´ + a = á, ¨ + u = ü). ^ y ` salen directo (mas comodo para programar).
# Uso: python3 generar-latam.py  -> escribe el .keylayout junto a este script
import os

# codigo de tecla de macOS: (normal, shift, altgr)
K = {
    50: ('|', '°', '¬'),            # debajo de Esc
    18: ('1', '!', '|'), 19: ('2', '"', '@'), 20: ('3', '#', '·'), 21: ('4', '$', '~'),
    23: ('5', '%', '€'), 22: ('6', '&', '¬'), 26: ('7', '/', '{'), 28: ('8', '(', '['),
    25: ('9', ')', ']'), 29: ('0', '=', '}'),
    27: ("'", '?', '\\'),           # junto al 0
    24: ('¿', '¡', ''),
    12: ('q', 'Q', '@'), 13: ('w', 'W', ''), 14: ('e', 'E', '€'), 15: ('r', 'R', ''), 17: ('t', 'T', ''),
    16: ('y', 'Y', ''), 32: ('u', 'U', ''), 34: ('i', 'I', ''), 31: ('o', 'O', ''), 35: ('p', 'P', ''),
    33: ('DEAD_ACUTE', 'DEAD_DIAER', ''),   # ´ ¨
    30: ('+', '*', '~'),
    0: ('a', 'A', ''), 1: ('s', 'S', ''), 2: ('d', 'D', ''), 3: ('f', 'F', ''), 5: ('g', 'G', ''),
    4: ('h', 'H', ''), 38: ('j', 'J', ''), 40: ('k', 'K', ''), 37: ('l', 'L', ''),
    41: ('ñ', 'Ñ', ''),
    39: ('{', '[', '^'),
    42: ('}', ']', '`'),
    10: ('<', '>', ''),             # junto a la Z (ISO)
    6: ('z', 'Z', ''), 7: ('x', 'X', ''), 8: ('c', 'C', ''), 9: ('v', 'V', ''), 11: ('b', 'B', ''),
    45: ('n', 'N', ''), 46: ('m', 'M', ''),
    43: (',', ';', ''), 47: ('.', ':', ''), 44: ('-', '_', ''),
    49: (' ', ' ', ' '),
}
# Teclas que no escriben letras (iguales en todas las capas)
FIJAS = {36: '\r', 48: '\t', 51: '\x08', 53: '\x1b', 76: '\x03', 117: '\x7f', 115: '\x01', 119: '\x04',
         116: '\x0b', 121: '\x0c', 123: '\x1c', 124: '\x1d', 125: '\x1f', 126: '\x1e', 114: '\x05', 71: '\x1b'}
for c in (122, 120, 99, 118, 96, 97, 98, 100, 101, 109, 103, 111, 105, 107, 113, 106, 64, 79, 80, 90):
    FIJAS[c] = '\x10'
PAD = {65: '.', 67: '*', 69: '+', 75: '/', 78: '-', 81: '=', 82: '0', 83: '1', 84: '2', 85: '3', 86: '4',
       87: '5', 88: '6', 89: '7', 91: '8', 92: '9'}
# Distribucion de EE.UU. para Comando (asi Comando+Z/C/V y demas atajos funcionan igual)
US = {50: '`', 18: '1', 19: '2', 20: '3', 21: '4', 23: '5', 22: '6', 26: '7', 28: '8', 25: '9', 29: '0',
      27: '-', 24: '=', 33: '[', 30: ']', 41: ';', 39: "'", 42: '\\', 10: '<', 43: ',', 47: '.', 44: '/'}

ACUTE = dict(zip('aeiouyAEIOUY ', 'áéíóúýÁÉÍÓÚÝ´'))
DIAER = dict(zip('aeiouyAEIOUY ', 'äëïöüÿÄËÏÖÜŸ¨'))

def x(s):
    return ''.join(c if (c.isalnum() and ord(c) < 128) else f'&#x{ord(c):04X};' for c in s)

acciones = {}
def tecla(code, s):
    if s == 'DEAD_ACUTE':
        return f'<key code="{code}" action="acute"/>'
    if s == 'DEAD_DIAER':
        return f'<key code="{code}" action="diaer"/>'
    if s in ACUTE:
        acciones[s] = True
        return f'<key code="{code}" action="a{ord(s):04X}"/>'
    return f'<key code="{code}" output="{x(s)}"/>'

def mapa(idx, capa):
    l = [f'    <keyMap index="{idx}">']
    for code in sorted(set(K) | set(FIJAS) | set(PAD)):
        if code in FIJAS:
            l.append(f'      <key code="{code}" output="{x(FIJAS[code])}"/>'); continue
        if code in PAD:
            l.append(f'      <key code="{code}" output="{x(PAD[code])}"/>'); continue
        n, s, a = K[code]
        if capa == 'normal': v = n
        elif capa == 'shift': v = s
        elif capa == 'caps': v = n.upper() if len(n) == 1 and n.isalpha() else n
        elif capa == 'altgr': v = a
        elif capa == 'altgr-shift': v = a
        elif capa == 'comando': v = US.get(code, n if len(n) == 1 else '')
        elif capa == 'control':
            b = US.get(code, n)
            v = chr(ord(b.upper()) - 64) if len(b) == 1 and b.isalpha() and ord(b) < 128 else b if len(b) == 1 else ''
        if v == '':
            l.append(f'      <key code="{code}" output=""/>')
        else:
            l.append('      ' + tecla(code, v))
    l.append('    </keyMap>')
    return '\n'.join(l)

capas = ['normal', 'shift', 'caps', 'altgr', 'altgr-shift', 'comando', 'control']
mapas = '\n'.join(mapa(i, c) for i, c in enumerate(capas))

acc = ['    <action id="acute"><when state="none" next="acute"/><when state="acute" output="&#x00B4;"/><when state="diaer" output="&#x00A8;"/></action>',
       '    <action id="diaer"><when state="none" next="diaer"/><when state="diaer" output="&#x00A8;"/><when state="acute" output="&#x00B4;"/></action>']
for ch in sorted(acciones):
    acc.append(f'    <action id="a{ord(ch):04X}"><when state="none" output="{x(ch)}"/>'
               f'<when state="acute" output="{x(ACUTE[ch])}"/><when state="diaer" output="{x(DIAER[ch])}"/></action>')

xml = f'''<?xml version="1.1" encoding="UTF-8"?>
<!DOCTYPE keyboard SYSTEM "file://localhost/System/Library/DTDs/KeyboardLayout.dtd">
<keyboard group="0" id="16382" name="Latinoamericano (Windows)" maxout="1">
  <layouts>
    <layout first="0" last="255" modifiers="mods" mapSet="mapa"/>
  </layouts>
  <modifierMap id="mods" defaultIndex="0">
    <keyMapSelect mapIndex="0"><modifier keys=""/></keyMapSelect>
    <keyMapSelect mapIndex="1"><modifier keys="anyShift caps?"/></keyMapSelect>
    <keyMapSelect mapIndex="2"><modifier keys="caps"/></keyMapSelect>
    <keyMapSelect mapIndex="3"><modifier keys="anyOption caps?"/></keyMapSelect>
    <keyMapSelect mapIndex="4"><modifier keys="anyOption anyShift caps?"/></keyMapSelect>
    <keyMapSelect mapIndex="5"><modifier keys="command anyShift? anyOption? caps?"/></keyMapSelect>
    <keyMapSelect mapIndex="6"><modifier keys="anyControl anyShift? anyOption? caps? command?"/></keyMapSelect>
  </modifierMap>
  <keyMapSet id="mapa">
{mapas}
  </keyMapSet>
  <actions>
{chr(10).join(acc)}
  </actions>
  <terminators>
    <when state="acute" output="&#x00B4;"/>
    <when state="diaer" output="&#x00A8;"/>
  </terminators>
</keyboard>
'''
dst = os.path.join(os.path.dirname(os.path.abspath(__file__)), 'Latinoamericano (Windows).keylayout')
open(dst, 'w', encoding='utf-8').write(xml)
print('escrito:', dst)
