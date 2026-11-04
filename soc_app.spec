# -*- mode: python ; coding: utf-8 -*-
# =====================================================================
#  soc_app.spec - Receta de PyInstaller para generar el ejecutable.
#  Se usa con:   pyinstaller soc_app.spec --noconfirm --clean
#  (el script build_exe.bat ya lo hace todo automáticamente)
# =====================================================================
from PyInstaller.utils.hooks import collect_all

# psycopg_binary contiene la biblioteca nativa de PostgreSQL (libpq): se incluye completa
datos_pg, binarios_pg, ocultos_pg = collect_all('psycopg_binary')

a = Analysis(
    ['main.py'],
    pathex=['.'],
    binaries=binarios_pg,
    datas=datos_pg + [('icono.png', '.'), ('icono.ico', '.')],   # archivos que viajan dentro de la app
    hiddenimports=ocultos_pg + ['psycopg', 'psycopg_binary'],
    excludes=['tkinter', 'unittest', 'pydoc_data', 'PIL', 'numpy'],        # módulos que la app no necesita
    noarchive=False,
)
pyz = PYZ(a.pure)

exe = EXE(
    pyz,
    a.scripts,
    [],
    exclude_binaries=True,       # modo "carpeta" (onedir): arranca más rápido y da menos falsos positivos de antivirus
    name='SOC_App',
    console=False,               # sin ventana negra de consola (los errores van a soc_app.log)
    icon='icono.ico',
    upx=False,                   # sin compresión UPX: evita falsos positivos de antivirus
)
coll = COLLECT(
    exe,
    a.binaries,
    a.datas,
    upx=False,
    name='SOC_App',              # la carpeta final será dist\SOC_App\
)
