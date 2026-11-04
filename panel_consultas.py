"""
ventanas/panel_consultas.py - Pestaña "Consultas de negocio".

Muestra la lista de las 10 consultas, su descripción y su SQL, ejecuta la
elegida y presenta el resultado en una tabla que se puede exportar a CSV.
"""
from PyQt6.QtCore import Qt
from PyQt6.QtGui import QFontDatabase
from PyQt6.QtWidgets import (QHBoxLayout, QLabel, QListWidget, QListWidgetItem,
                             QMessageBox, QPlainTextEdit, QPushButton, QSplitter, QVBoxLayout,
                             QWidget)

from consultas import CONSULTAS
from db import BaseDeDatos
from ventanas.dialogos import exportar_con_dialogo
from ventanas.hilos import HiloConsulta
from ventanas.widgets import ResaltadorSQL, TablaResultados


class PanelConsultas(QWidget):
    def __init__(self, bd: BaseDeDatos, parent=None):
        super().__init__(parent)
        self.bd = bd
        self._hilo = None                 # hilo de la consulta en curso (None = ninguna)
        self._columnas, self._filas = [], []   # último resultado (para exportar)

        # ================= Panel izquierdo: lista de consultas ================
        self.lista = QListWidget()
        for c in CONSULTAS:
            item = QListWidgetItem(f"{c['id']}.  {c['titulo']}")
            item.setData(Qt.ItemDataRole.UserRole, c["id"])
            self.lista.addItem(item)
        self.lista.setMinimumWidth(340)
        self.lista.setWordWrap(True)                                   # títulos largos en varias líneas
        self.lista.setHorizontalScrollBarPolicy(Qt.ScrollBarPolicy.ScrollBarAlwaysOff)
        self.lista.currentRowChanged.connect(self._seleccionar)
        self.lista.itemDoubleClicked.connect(lambda _: self.ejecutar())

        # ================= Panel derecho superior: descripción y SQL ==========
        self.lbl_titulo = QLabel()
        self.lbl_titulo.setObjectName("titulo")
        self.lbl_titulo.setWordWrap(True)
        self.lbl_pregunta = QLabel()
        self.lbl_pregunta.setWordWrap(True)
        self.lbl_meta = QLabel()
        self.lbl_meta.setObjectName("subtitulo")
        self.lbl_meta.setWordWrap(True)
        self.lbl_meta.setTextFormat(Qt.TextFormat.RichText)

        self.txt_sql = QPlainTextEdit()
        self.txt_sql.setReadOnly(True)
        self.txt_sql.setLineWrapMode(QPlainTextEdit.LineWrapMode.NoWrap)
        fuente = QFontDatabase.systemFont(QFontDatabase.SystemFont.FixedFont)   # fuente monoespaciada
        fuente.setPointSize(10)
        self.txt_sql.setFont(fuente)
        self.resaltador = ResaltadorSQL(self.txt_sql.document())

        self.btn_ver_sql = QPushButton("Ocultar SQL")
        self.btn_ver_sql.setCheckable(True)
        self.btn_ver_sql.setChecked(True)
        self.btn_ver_sql.toggled.connect(self._alternar_sql)

        self.btn_ejecutar = QPushButton("▶  Ejecutar consulta")
        self.btn_ejecutar.setObjectName("primario")
        self.btn_ejecutar.clicked.connect(self.ejecutar)
        self.btn_exportar = QPushButton("Exportar a CSV...")
        self.btn_exportar.clicked.connect(self.exportar)
        self.btn_exportar.setEnabled(False)

        barra = QHBoxLayout()
        barra.addWidget(self.btn_ejecutar)
        barra.addWidget(self.btn_exportar)
        barra.addWidget(self.btn_ver_sql)
        barra.addStretch()

        superior = QWidget()
        lay_sup = QVBoxLayout(superior)
        lay_sup.setContentsMargins(0, 0, 0, 0)
        lay_sup.setSpacing(6)
        lay_sup.addWidget(self.lbl_titulo)
        lay_sup.addWidget(self.lbl_pregunta)
        lay_sup.addWidget(self.lbl_meta)
        lay_sup.addWidget(self.txt_sql, 1)
        lay_sup.addLayout(barra)

        # ================= Panel derecho inferior: resultados =================
        self.lbl_estado = QLabel("Elija una consulta y pulse «Ejecutar».")
        self.lbl_estado.setObjectName("subtitulo")
        self.tabla = TablaResultados()

        inferior = QWidget()
        lay_inf = QVBoxLayout(inferior)
        lay_inf.setContentsMargins(0, 0, 0, 0)
        lay_inf.setSpacing(4)
        lay_inf.addWidget(self.lbl_estado)
        lay_inf.addWidget(self.tabla, 1)

        # ================= Divisores ajustables con el mouse ==================
        self.divisor_vertical = QSplitter(Qt.Orientation.Vertical)
        self.divisor_vertical.addWidget(superior)
        self.divisor_vertical.addWidget(inferior)
        self.divisor_vertical.setSizes([330, 300])
        self.divisor_vertical.setChildrenCollapsible(False)

        divisor = QSplitter(Qt.Orientation.Horizontal)
        divisor.addWidget(self.lista)
        divisor.addWidget(self.divisor_vertical)
        divisor.setSizes([350, 800])
        divisor.setChildrenCollapsible(False)

        layout = QHBoxLayout(self)
        layout.setContentsMargins(12, 12, 12, 12)
        layout.addWidget(divisor)

        self.lista.setCurrentRow(0)       # selecciona la primera consulta al abrir

    # ------------------------------------------------------------------
    def _consulta_actual(self):
        fila = self.lista.currentRow()
        return CONSULTAS[fila] if fila >= 0 else None

    def _seleccionar(self, _fila):
        """Al elegir otra consulta: mostrar su descripción y limpiar el resultado anterior."""
        c = self._consulta_actual()
        if c is None:
            return
        self.lbl_titulo.setText(f"Consulta {c['id']}: {c['titulo']}")
        self.lbl_pregunta.setText(f"<b>Pregunta de negocio:</b> {c['pregunta']}")
        self.lbl_meta.setText(f"<b>Tablas:</b> {c['tablas']}<br><b>Técnicas:</b> {c['tecnicas']}")
        self.txt_sql.setPlainText(c["sql"])
        if self._hilo is None:             # no borrar el estado si hay una consulta ejecutándose
            self.tabla.limpiar()
            self._columnas, self._filas = [], []
            self.btn_exportar.setEnabled(False)
            self.lbl_estado.setText("Pulse «Ejecutar consulta» para ver el resultado.")

    def _alternar_sql(self, visible: bool):
        self.txt_sql.setVisible(visible)
        self.btn_ver_sql.setText("Ocultar SQL" if visible else "Ver SQL")

    # ------------------------------------------------------------------
    # Ejecución
    # ------------------------------------------------------------------
    def ejecutar(self):
        c = self._consulta_actual()
        if c is None or self._hilo is not None:
            return
        self.btn_ejecutar.setEnabled(False)
        self.btn_exportar.setEnabled(False)
        self.lista.setEnabled(False)
        self.lbl_estado.setText("Ejecutando consulta...")
        self.tabla.limpiar()

        self._hilo = HiloConsulta(self.bd, c["sql"])
        self._hilo.terminado.connect(self._al_terminar)
        self._hilo.fallo.connect(self._al_fallar)
        self._hilo.finished.connect(self._liberar_hilo)
        self._hilo.start()                # empieza en segundo plano: la ventana sigue libre

    def _al_terminar(self, columnas, filas, segundos):
        self._columnas, self._filas = columnas, filas
        self.tabla.mostrar(columnas, filas)
        self.btn_exportar.setEnabled(len(filas) > 0)
        texto = f"{len(filas)} fila(s) en {segundos * 1000:.0f} ms"
        if not filas:
            texto = "La consulta no devolvió resultados."
        self.lbl_estado.setText(texto + "  |  clic en un encabezado para ordenar")

    def _al_fallar(self, mensaje):
        self.lbl_estado.setText("La consulta falló.")
        QMessageBox.critical(self, "Error al ejecutar la consulta", mensaje)

    def _liberar_hilo(self):
        self._hilo.deleteLater()
        self._hilo = None
        self.btn_ejecutar.setEnabled(True)
        self.lista.setEnabled(True)

    def detener(self):
        """Se llama al cerrar la ventana: cancela la consulta en curso y espera al hilo."""
        if self._hilo is not None:
            self.bd.cancelar()
            self._hilo.wait(3000)

    # ------------------------------------------------------------------
    # Exportación
    # ------------------------------------------------------------------
    def exportar(self):
        c = self._consulta_actual()
        if c is not None:
            exportar_con_dialogo(self, f"consulta_{c['id']:02d}_{c['titulo']}", self._columnas, self._filas)
