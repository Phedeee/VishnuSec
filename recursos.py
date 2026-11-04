"""
recursos.py - Rutas de archivos que funcionan tanto ejecutando con Python como
dentro del ejecutable generado con PyInstaller.

Cuando la app corre como .exe, los archivos incluidos (como el icono) se extraen a una
carpeta temporal (sys._MEIPASS) y el archivo config.ini vive junto al .exe.
"""
import os
import sys


def esta_empaquetada() -> bool:
    """True si la aplicación corre como ejecutable (PyInstaller)."""
    return bool(getattr(sys, "frozen", False))


def ruta_recurso(nombre: str) -> str:
    """Ruta de un archivo incluido dentro de la aplicación (por ejemplo, el icono)."""
    base = getattr(sys, "_MEIPASS", os.path.dirname(os.path.abspath(__file__)))
    return os.path.join(base, nombre)


def carpeta_aplicacion() -> str:
    """Carpeta donde está el .exe (o main.py): ahí se busca el archivo config.ini."""
    if esta_empaquetada():
        return os.path.dirname(sys.executable)
    return os.path.dirname(os.path.abspath(__file__))


def carpeta_datos_usuario() -> str:
    """Carpeta donde la app guarda su registro de errores (se crea si no existe)."""
    if sys.platform == "win32":
        base = os.environ.get("LOCALAPPDATA") or os.path.expanduser("~")
    else:
        base = os.environ.get("XDG_DATA_HOME") or os.path.expanduser("~/.local/share")
    carpeta = os.path.join(base, "SOC_App")
    os.makedirs(carpeta, exist_ok=True)
    return carpeta
