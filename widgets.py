"""
ventanas/widgets.py - Componentes visuales reutilizables.

  TablaResultados : tabla que muestra el resultado de cualquier consulta,
                    con formato en español y ordenamiento por columnas.
  ResaltadorSQL   : colorea las palabras clave del SQL (azul), textos (rojo)
                    y comentarios (verde) para que se lea mejor.
"""
import re
from datetime import date, datetime
from decimal import Decimal

from PyQt6.QtCore import Qt
from PyQt6.QtGui import QColor, QFont, QSyntaxHighlighter, QTextCharFormat
from PyQt6.QtWidgets import QAbstractItemView, QHeaderView, QTableWidget, QTableWidgetItem

ANCHO_MAXIMO_COLUMNA = 380      # píxeles: evita columnas gigantes con textos largos


# ----------------------------------------------------------------------
# Formato de valores
# ----------------------------------------------------------------------
def formatear(valor) -> str:
    """Convierte un valor de la base de datos al texto que se ve en pantalla."""
    if valor is None:
        return "—"
    if isinstance(valor, bool):
        return "Sí" if valor else "No"
    if isinstance(valor, Decimal):
        return format(valor, "f").replace(".", ",")          # 9.8 -> 9,8
    if isinstance(valor, float):
        return f"{valor:.2f}".replace(".", ",")
    if isinstance(valor, datetime):
        return valor.strftime("%Y-%m-%d %H:%M")
    if isinstance(valor, date):
        return valor.strftime("%Y-%m-%d")
    return str(valor)


class ItemOrdenable(QTableWidgetItem):
    """Celda que se ordena por su valor REAL (números como números, fechas como fechas)
    y no como texto (de lo contrario 10 quedaría antes que 9)."""

    def __lt__(self, otro):
        a = self.data(Qt.ItemDataRole.UserRole)
        b = otro.data(Qt.ItemDataRole.UserRole)
        try:
            return a < b
        except TypeError:                       # tipos mezclados (p. ej. NULL y números)
            return str(a) < str(b)


class TablaResultados(QTableWidget):
    def __init__(self, parent=None):
        super().__init__(0, 0, parent)
        self.setAlternatingRowColors(True)
        self.setEditTriggers(QAbstractItemView.EditTrigger.NoEditTriggers)   # solo lectura
        self.setSelectionBehavior(QAbstractItemView.SelectionBehavior.SelectRows)
        self.verticalHeader().setVisible(False)
        self.horizontalHeader().setSortIndicatorShown(True)
        self.horizontalHeader().setHighlightSections(False)
        self.setWordWrap(False)

    def filtrar(self, texto: str = "", igualdad=None) -> int:
        """
        Oculta las filas que no cumplen los filtros y devuelve cuántas quedan visibles.
          texto    : las filas deben contener este texto en alguna celda (sin distinguir mayúsculas)
          igualdad : lista de (indice_de_columna, valor): la celda debe ser exactamente ese valor
                     (si el valor está vacío, ese filtro se ignora)
        """
        buscado = texto.strip().lower()
        visibles = 0
        for r in range(self.rowCount()):
            ok = all(not valor or self.item(r, col).text() == valor for col, valor in (igualdad or []))
            if ok and buscado:
                ok = any(buscado in self.item(r, c).text().lower() for c in range(self.columnCount()))
            self.setRowHidden(r, not ok)
            visibles += ok
        return visibles

    def valor_fila(self, fila: int, columna: int):
        """Valor real (no el texto formateado) de una celda."""
        item = self.item(fila, columna)
        return item.data(Qt.ItemDataRole.UserRole) if item else None

    def limpiar(self):
        self.setSortingEnabled(False)
        self.clear()
        self.setRowCount(0)
        self.setColumnCount(0)

    def mostrar(self, columnas, filas):
        """Llena la tabla con el resultado de una consulta."""
        self.setSortingEnabled(False)            # desactivar mientras se llena (más rápido)
        self.clear()
        self.setColumnCount(len(columnas))
        self.setHorizontalHeaderLabels([str(c) for c in columnas])
        self.setRowCount(len(filas))

        for r, fila in enumerate(filas):
            for c, valor in enumerate(fila):
                item = ItemOrdenable(formatear(valor))
                es_numero = isinstance(valor, (int, float, Decimal)) and not isinstance(valor, bool)
                if es_numero:
                    item.setTextAlignment(Qt.AlignmentFlag.AlignRight | Qt.AlignmentFlag.AlignVCenter)
                    item.setData(Qt.ItemDataRole.UserRole, float(valor))
                else:
                    item.setData(Qt.ItemDataRole.UserRole, "" if valor is None else valor)
                if isinstance(valor, str) and len(valor) > 40:
                    item.setToolTip(valor)       # texto completo al pasar el mouse
                self.setItem(r, c, item)

        self.resizeColumnsToContents()
        for c in range(len(columnas)):           # limitar el ancho de columnas muy largas
            if self.columnWidth(c) > ANCHO_MAXIMO_COLUMNA:
                self.setColumnWidth(c, ANCHO_MAXIMO_COLUMNA)
        self.horizontalHeader().setStretchLastSection(True)
        self.setSortingEnabled(True)             # ahora se puede ordenar con clic en el encabezado


# ----------------------------------------------------------------------
# Resaltado de sintaxis SQL
# ----------------------------------------------------------------------
class ResaltadorSQL(QSyntaxHighlighter):
    PALABRAS = (
        "SELECT FROM WHERE GROUP BY HAVING ORDER LIMIT OFFSET JOIN INNER LEFT RIGHT FULL OUTER "
        "ON AS AND OR NOT IN IS NULL BETWEEN LIKE ILIKE CASE WHEN THEN ELSE END DISTINCT UNION ALL "
        "WITH OVER PARTITION FILTER ASC DESC EXISTS INSERT UPDATE DELETE CREATE TABLE INTO VALUES "
        "TRUE FALSE"
    ).split()
    FUNCIONES = ("COUNT SUM AVG MIN MAX ROUND COALESCE NULLIF EXTRACT DATE_TRUNC STRING_AGG BOOL_OR "
                 "CURRENT_DATE NOW CAST").split()

    def __init__(self, documento):
        super().__init__(documento)
        def fmt(color, negrita=False, cursiva=False):
            f = QTextCharFormat()
            f.setForeground(QColor(color))
            if negrita:
                f.setFontWeight(QFont.Weight.Bold)
            f.setFontItalic(cursiva)
            return f

        flags = re.IGNORECASE
        self.reglas = [
            (re.compile(r"\b(" + "|".join(self.PALABRAS) + r")\b", flags), fmt("#1F4E79", negrita=True)),
            (re.compile(r"\b(" + "|".join(self.FUNCIONES) + r")\b", flags), fmt("#7B2D8E")),
            (re.compile(r"\b\d+(\.\d+)?\b"), fmt("#B45F06")),
            (re.compile(r"'[^']*'"), fmt("#B3261E")),
            (re.compile(r"--[^\n]*"), fmt("#4C8A5B", cursiva=True)),    # comentarios (van al final: ganan)
        ]

    def highlightBlock(self, texto):
        for patron, formato in self.reglas:
            for m in patron.finditer(texto):
                self.setFormat(m.start(), m.end() - m.start(), formato)
