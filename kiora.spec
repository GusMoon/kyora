# -*- mode: python ; coding: utf-8 -*-
import os
import sys

block_cipher = None

project_dir = os.path.abspath(os.curdir)

datas = [
    (os.path.join(project_dir, 'core', 'resources'), os.path.join('core', 'resources')),
]

config_file = os.path.join(project_dir, 'core', 'matrix', 'ecosystems', 'global_config.json')
if os.path.exists(config_file):
    datas.append((config_file, os.path.join('core', 'matrix', 'ecosystems')))

cookies_file = os.path.join(project_dir, 'core', 'matrix', 'ecosystems', 'studio', 'youtube_cookies.txt')
if os.path.exists(cookies_file):
    datas.append((cookies_file, os.path.join('core', 'matrix', 'ecosystems', 'studio')))

icon_path = os.path.join(project_dir, 'core', 'resources', 'kiora.ico')

a = Analysis(
    ['main.py'],
    pathex=[project_dir],
    binaries=[],
    datas=datas,
    hiddenimports=[
        'PySide6.QtCore',
        'PySide6.QtGui',
        'PySide6.QtWidgets',
        'sqlite3',
    ],
    hookspath=[],
    hooksconfig={},
    runtime_hooks=[],
    excludes=['unittest', 'pytest'],
    win_no_prefer_redirects=False,
    win_private_assemblies=False,
    cipher=block_cipher,
    noarchive=False,
)

pyz = PYZ(a.pure, a.zipped_data, cipher=block_cipher)

exe = EXE(
    pyz,
    a.scripts,
    [],
    exclude_binaries=True,
    name='Kiora',
    debug=False,
    bootloader_ignore_signals=False,
    strip=False,
    upx=False,
    console=False,
    disable_windowed_traceback=False,
    argv_emulation=False,
    target_arch=None,
    codesign_identity=None,
    entitlements_file=None,
    icon=icon_path if os.path.exists(icon_path) else None,
)

coll = COLLECT(
    exe,
    a.binaries,
    a.zipfiles,
    a.datas,
    strip=False,
    upx=False,
    upx_exclude=[],
    name='Kiora',
)
