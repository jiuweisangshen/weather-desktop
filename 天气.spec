# -*- mode: python ; coding: utf-8 -*-
# 在仓库根目录执行：python -m PyInstaller 天气.spec --distpath dist --workpath build\pyi --noconfirm

a = Analysis(
    ['src/weather_app/main.py'],
    pathex=['src'],
    binaries=[],
    datas=[('src/weather_app/ui', 'weather_app/ui'),
           ('src/weather_app/i18n', 'weather_app/i18n'),
           ('assets', 'assets')],
    hiddenimports=[],
    hookspath=[],
    hooksconfig={},
    runtime_hooks=[],
    excludes=[],
    noarchive=False,
    optimize=0,
)
pyz = PYZ(a.pure)

exe = EXE(
    pyz,
    a.scripts,
    [],
    exclude_binaries=True,
    name='天气',
    debug=False,
    bootloader_ignore_signals=False,
    strip=False,
    upx=True,
    console=False,
    disable_windowed_traceback=False,
    argv_emulation=False,
    target_arch=None,
    codesign_identity=None,
    entitlements_file=None,
    icon=['assets/appicon/app_icon.ico'],
)
coll = COLLECT(
    exe,
    a.binaries,
    a.datas,
    strip=False,
    upx=True,
    upx_exclude=[],
    name='天气',
)
