"""
ventanas/dialogos.py - Diálogos compartidos por varias pestañas.
"""
import re
import unicodedata

from PyQt6.QtCore import QStandardPaths
from PyQt6.QtWidgets import QFileDialog, QMessageBox

from exportar import guardar_csv


def _nombre_archivo(texto: str) -> str:
    """'Exposición a vulnerabilidades' -> 'exposicion_a_vulnerabilidades'."""
    sin_tildes = "".join(c for c in unicodedata.normalize("NFD", texto) if unicodedata.category(c) != "Mn")
    return re.sub(r"[^a-z0-9]+", "_", sin_tildes.lower()).strip("_")


def exportar_con_dialogo(parent, nombre_sugerido: str, columnas, filas) -> None:
    """Pregunta dónde guardar y escribe el CSV. Muestra mensajes claros si algo falla."""
    if not filas:
        return
    carpeta = QStandardPaths.writableLocation(QStandardPaths.StandardLocation.DocumentsLocation)
    ruta, _ = QFileDialog.getSaveFileName(
        parent, "Guardar resultado como CSV",
        f"{carpeta}/{_nombre_archivo(nombre_sugerido)}.csv", "Archivos CSV (*.csv)")
    if not ruta:
        return                                      # el usuario canceló
    if not ruta.lower().endswith(".csv"):
        ruta += ".csv"
    try:
        n = guardar_csv(ruta, columnas, filas)
    except OSError as e:                            # p. ej. el archivo está abierto en Excel
        QMessageBox.critical(parent, "No se pudo guardar",
                             f"{e}\n\nSi el archivo está abierto en Excel, ciérrelo e intente de nuevo.")
        return
    QMessageBox.information(parent, "Exportación completa", f"Se guardaron {n} filas en:\n{ruta}")
