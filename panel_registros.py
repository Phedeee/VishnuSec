"""
ventanas/panel_registros.py - Pestañas de consulta de bitácoras: "Auditoría" e "Inconsistencias".

Es un panel genérico: recibe el SQL, muestra el resultado en una tabla y ofrece
  - búsqueda por texto,
  - un filtro desplegable por una columna (por ejemplo, el motivo),
  - exportación a CSV (solo de las filas que se están viendo).
"""
from PyQt6.QtWidgets import (QComboBox, QHBoxLayout, QLabel, QLineEdit, QMessageBox,
                             QPushButton, QVBoxLayout, QWidget)

from db import BaseDeDatos, ErrorBD
from ventanas.dialogos import exportar_con_dialogo
from ventanas.widgets import TablaResultados, formatear


class PanelRegistros(QWidget):
    def __init__(self, bd: BaseDeDatos, *, descripcion: str, sql: str, etiqueta_filtro: str,
                 columna_filtro: str, nombre_csv: str, parent=None):
        super().__init__(parent)
        self.bd = bd
        self.sql = sql
        self.columna_filtro = columna_filtro
        self.nombre_csv = nombre_csv
        self._columnas, self._filas = [], []

        lbl_desc = QLabel(descripcion)
        lbl_desc.setObjectName("subtitulo")
        lbl_desc.setWordWrap(True)

        self.txt_buscar = QLineEdit()
        self.txt_buscar.setPlaceholderText("Buscar en cualquier columna...")
        self.txt_buscar.setClearButtonEnabled(True)
        self.txt_buscar.textChanged.connect(self._aplicar_filtros)
        self.cmb_filtro = QComboBox()
        self.cmb_filtro.setMinimumWidth(170)
        self.cmb_filtro.currentIndexChanged.connect(self._aplicar_filtros)
        self.lbl_etiqueta = QLabel(etiqueta_filtro)

        btn_actualizar = QPushButton("Actualizar")
        btn_actualizar.clicked.connect(self.recargar)
        self.btn_exportar = QPushButton("Exportar a CSV...")
        self.btn_exportar.clicked.connect(self.exportar)

        barra = QHBoxLayout()
        barra.addWidget(self.txt_buscar, 1)
        barra.addWidget(self.lbl_etiqueta)
        barra.addWidget(self.cmb_filtro)
        barra.addWidget(btn_actualizar)
        barra.addWidget(self.btn_exportar)

        self.tabla = TablaResultados()
        self.lbl_estado = QLabel("")
        self.lbl_estado.setObjectName("subtitulo")

        layout = QVBoxLayout(self)
        layout.setContentsMargins(12, 12, 12, 12)
        layout.addWidget(lbl_desc)
        layout.addLayout(barra)
        layout.addWidget(self.tabla, 1)
        layout.addWidget(self.lbl_estado)

        self.recargar()

    # ------------------------------------------------------------------
    def recargar(self):
        """Vuelve a leer los datos de la base (se llama también tras inactivar un empleado)."""
        try:
            self._columnas, self._filas = self.bd.consultar(self.sql)
        except ErrorBD as e:
            self.lbl_estado.setText("No se pudieron cargar los datos.")
            QMessageBox.critical(self, "Error al consultar", str(e))
            return

        self.tabla.mostrar(self._columnas, self._filas)

        # Rellenar el filtro desplegable con los valores distintos de la columna elegida
        seleccion_previa = self.cmb_filtro.currentText()
        indice = self._columnas.index(self.columna_filtro)
        valores = sorted({str(f[indice]) for f in self._filas if f[indice] is not None})
        self.cmb_filtro.blockSignals(True)
        self.cmb_filtro.clear()
        self.cmb_filtro.addItem("Todos")
        self.cmb_filtro.addItems(valores)
        pos = self.cmb_filtro.findText(seleccion_previa)
        self.cmb_filtro.setCurrentIndex(pos if pos >= 0 else 0)
        self.cmb_filtro.blockSignals(False)
        self._aplicar_filtros()

    def _criterios(self):
        texto = self.txt_buscar.text()
        valor = "" if self.cmb_filtro.currentIndex() <= 0 else self.cmb_filtro.currentText()
        return texto, valor

    def _aplicar_filtros(self):
        if not self._columnas:
            return
        texto, valor = self._criterios()
        col = self._columnas.index(self.columna_filtro)
        visibles = self.tabla.filtrar(texto, [(col, valor)])
        self.lbl_estado.setText(f"Mostrando {visibles} de {len(self._filas)} registros  |  "
                                "clic en un encabezado para ordenar")
        self.btn_exportar.setEnabled(visibles > 0)

    def _filas_visibles(self):
        """Mismas filas que se ven en la tabla, con sus valores originales (para el CSV)."""
        texto, valor = self._criterios()
        buscado = texto.strip().lower()
        col = self._columnas.index(self.columna_filtro)
        resultado = []
        for fila in self._filas:
            if valor and formatear(fila[col]) != valor:
                continue
            if buscado and not any(buscado in formatear(v).lower() for v in fila):
                continue
            resultado.append(fila)
        return resultado

    def exportar(self):
        exportar_con_dialogo(self, self.nombre_csv, self._columnas, self._filas_visibles())
