"""
ventanas/panel_libre.py - Pestaña "Consulta libre".

Permite escribir cualquier consulta de LECTURA, ejecutarla y exportar el resultado.
Incluye:
  - un explorador de la estructura (tablas y columnas, con sus claves PK/FK),
  - ejemplos de consultas listos para usar,
  - historial de las consultas ejecutadas en la sesión,
  - un botón para detener consultas largas.

Seguridad (tres capas, de la más débil a la más fuerte):
  1. validacion.py rechaza sentencias que no son de lectura, con un mensaje claro.
  2. db.py ejecuta cada consulta dentro de una transacción READ ONLY.
  3. El usuario app_lectura solo tiene permiso SELECT en la base de datos.
"""
from PyQt6.QtCore import Qt
from PyQt6.QtGui import QBrush, QColor, QFont, QFontDatabase, QKeySequence, QShortcut
from PyQt6.QtWidgets import (QComboBox, QHBoxLayout, QLabel, QMessageBox, QPlainTextEdit,
                             QPushButton, QSplitter, QTreeWidget, QTreeWidgetItem, QVBoxLayout,
                             QWidget)

from config import LIMITE_FILAS_CONSULTA_LIBRE
from db import BaseDeDatos, ErrorBD
from validacion import preparar
from ventanas.dialogos import exportar_con_dialogo
from ventanas.hilos import HiloConsulta
from ventanas.widgets import ResaltadorSQL, TablaResultados

MAX_HISTORIAL = 30

EJEMPLOS = [
    ("Tablas y cantidad de columnas",
     "SELECT table_name AS tabla, COUNT(*) AS columnas\n"
     "FROM   information_schema.columns\n"
     "WHERE  table_schema = 'public'\n"
     "GROUP  BY table_name\n"
     "ORDER  BY table_name;"),
    ("Empleados activos por departamento",
     "SELECT departamento, COUNT(*) AS empleados\n"
     "FROM   empleados\n"
     "WHERE  estado = 'Activo'\n"
     "GROUP  BY departamento\n"
     "ORDER  BY empleados DESC;"),
    ("Activos de criticidad Alta",
     "SELECT nombre_host, tipo_dispositivo, direccion_ip\n"
     "FROM   activos_red\n"
     "WHERE  criticidad = 'Alta'\n"
     "ORDER  BY tipo_dispositivo, nombre_host;"),
    ("Incidentes sin resolver y su amenaza",
     "SELECT i.id_incidente, ar.nombre_host, ta.nombre_amenaza, ta.nivel_riesgo,\n"
     "       i.fecha_deteccion, i.estado\n"
     "FROM   incidentes i\n"
     "JOIN   activos_red ar    ON ar.id_activo = i.activo_id\n"
     "JOIN   tipos_amenaza ta  ON ta.id_amenaza = i.tipo_amenaza_id\n"
     "WHERE  i.estado <> 'Resuelto'\n"
     "ORDER  BY i.fecha_deteccion DESC;"),
    ("Vulnerabilidades críticas (CVSS 9 o más)",
     "SELECT cve_code, puntaje_cvss, descripcion_tecnica\n"
     "FROM   vulnerabilidades_conocidas\n"
     "WHERE  puntaje_cvss >= 9.0\n"
     "ORDER  BY puntaje_cvss DESC, cve_code;"),
    ("Últimas reasignaciones de activos (auditoría)",
     "SELECT au.fecha_reasignacion, ar.nombre_host,\n"
     "       ea.nombre AS empleado_anterior, en.nombre AS empleado_nuevo, au.motivo\n"
     "FROM   auditoria au\n"
     "JOIN   activos_red ar ON ar.id_activo   = au.activo_id\n"
     "JOIN   empleados  ea ON ea.id_empleado = au.empleado_anterior_id\n"
     "JOIN   empleados  en ON en.id_empleado = au.empleado_nuevo_id\n"
     "ORDER  BY au.fecha_reasignacion DESC\n"
     "LIMIT  10;"),
    ("Registros rechazados (inconsistencias)",
     "SELECT fecha_registro, tabla_origen, operacion, motivo\n"
     "FROM   inconsistencias\n"
     "ORDER  BY fecha_registro DESC\n"
     "LIMIT  15;"),
    ("Plan de ejecución de una consulta (EXPLAIN)",
     "EXPLAIN ANALYZE\n"
     "SELECT activo_id, tipo_amenaza_id, fecha_deteccion\n"
     "FROM   incidentes\n"
     "WHERE  estado IN ('Abierto', 'En Investigación')\n"
     "ORDER  BY fecha_deteccion DESC\n"
     "LIMIT  20;"),
    ("Índices existentes en la base de datos",
     "SELECT tablename AS tabla, indexname AS indice, indexdef AS definicion\n"
     "FROM   pg_indexes\n"
     "WHERE  schemaname = 'public'\n"
     "ORDER  BY tablename, indexname;"),
]


class PanelConsultaLibre(QWidget):
    def __init__(self, bd: BaseDeDatos, parent=None):
        super().__init__(parent)
        self.bd = bd
        self._hilo = None
        self._columnas, self._filas = [], []
        self._historial = []

        # ================= Izquierda: explorador de estructura ================
        lbl_esq = QLabel("Estructura de la base de datos")
        lbl_esq.setObjectName("subtitulo")
        self.arbol = QTreeWidget()
        self.arbol.setColumnCount(3)
        self.arbol.setHeaderLabels(["Tabla / columna", "Tipo", "Clave"])
        self.arbol.setUniformRowHeights(True)
        self.arbol.setMinimumWidth(430)
        self.arbol.setHorizontalScrollBarPolicy(Qt.ScrollBarPolicy.ScrollBarAsNeeded)
        self.arbol.itemDoubleClicked.connect(self._insertar_nombre)
        lbl_ayuda = QLabel("Doble clic en una tabla o columna para insertarla en el editor.")
        lbl_ayuda.setObjectName("subtitulo")
        lbl_ayuda.setWordWrap(True)
        btn_refrescar = QPushButton("Actualizar estructura")
        btn_refrescar.clicked.connect(self.cargar_esquema)

        izquierda = QWidget()
        lay_izq = QVBoxLayout(izquierda)
        lay_izq.setContentsMargins(0, 0, 0, 0)
        lay_izq.setSpacing(4)
        lay_izq.addWidget(lbl_esq)
        lay_izq.addWidget(self.arbol, 1)
        lay_izq.addWidget(lbl_ayuda)
        lay_izq.addWidget(btn_refrescar)

        # ================= Derecha arriba: editor y botones ===================
        self.editor = QPlainTextEdit()
        self.editor.setPlaceholderText(
            "Escriba aquí su consulta (SELECT, WITH, EXPLAIN...) y pulse Ctrl+Enter o «Ejecutar».\n"
            "Si selecciona una parte del texto, solo se ejecuta esa parte.")
        fuente = QFontDatabase.systemFont(QFontDatabase.SystemFont.FixedFont)
        fuente.setPointSize(11)
        self.editor.setFont(fuente)
        self.editor.setTabStopDistance(32)
        self.resaltador = ResaltadorSQL(self.editor.document())

        self.btn_ejecutar = QPushButton("▶  Ejecutar  (Ctrl+Enter)")
        self.btn_ejecutar.setObjectName("primario")
        self.btn_ejecutar.clicked.connect(self._pulsar_ejecutar)
        self.btn_exportar = QPushButton("Exportar a CSV...")
        self.btn_exportar.setEnabled(False)
        self.btn_exportar.clicked.connect(self.exportar)
        btn_limpiar = QPushButton("Limpiar")
        btn_limpiar.clicked.connect(self._limpiar)

        self.cmb_ejemplos = QComboBox()
        self.cmb_ejemplos.addItem("Ejemplos de consultas...")
        for titulo, _ in EJEMPLOS:
            self.cmb_ejemplos.addItem(titulo)
        self.cmb_ejemplos.activated.connect(self._cargar_ejemplo)

        self.cmb_historial = QComboBox()
        self.cmb_historial.addItem("Historial de la sesión...")
        self.cmb_historial.activated.connect(self._cargar_historial)

        barra = QHBoxLayout()
        barra.addWidget(self.btn_ejecutar)
        barra.addWidget(self.btn_exportar)
        barra.addWidget(btn_limpiar)
        barra.addStretch()
        barra.addWidget(self.cmb_ejemplos)
        barra.addWidget(self.cmb_historial)

        superior = QWidget()
        lay_sup = QVBoxLayout(superior)
        lay_sup.setContentsMargins(0, 0, 0, 0)
        lay_sup.setSpacing(6)
        lay_sup.addWidget(self.editor, 1)
        lay_sup.addLayout(barra)

        # ================= Derecha abajo: resultados ==========================
        self.lbl_estado = QLabel("Escriba una consulta de lectura y pulse «Ejecutar».")
        self.lbl_estado.setObjectName("subtitulo")
        self.tabla = TablaResultados()
        inferior = QWidget()
        lay_inf = QVBoxLayout(inferior)
        lay_inf.setContentsMargins(0, 0, 0, 0)
        lay_inf.setSpacing(4)
        lay_inf.addWidget(self.lbl_estado)
        lay_inf.addWidget(self.tabla, 1)

        vertical = QSplitter(Qt.Orientation.Vertical)
        vertical.addWidget(superior)
        vertical.addWidget(inferior)
        vertical.setSizes([300, 360])
        vertical.setChildrenCollapsible(False)

        horizontal = QSplitter(Qt.Orientation.Horizontal)
        horizontal.addWidget(izquierda)
        horizontal.addWidget(vertical)
        horizontal.setSizes([450, 730])
        horizontal.setChildrenCollapsible(False)

        layout = QHBoxLayout(self)
        layout.setContentsMargins(12, 12, 12, 12)
        layout.addWidget(horizontal)

        # Atajos de teclado: Ctrl+Enter (y Ctrl+Enter del teclado numérico) y F5
        for tecla in ("Ctrl+Return", "Ctrl+Enter", "F5"):
            QShortcut(QKeySequence(tecla), self, activated=self._pulsar_ejecutar)

        self.cargar_esquema()

    # ------------------------------------------------------------------
    # Explorador de estructura
    # ------------------------------------------------------------------
    def cargar_esquema(self):
        try:
            filas = self.bd.esquema()
        except ErrorBD as e:
            QMessageBox.critical(self, "No se pudo leer la estructura", str(e))
            return
        self.arbol.clear()
        negrita = QFont()
        negrita.setBold(True)
        color_pk, color_fk = QBrush(QColor("#B8860B")), QBrush(QColor("#7B2D8E"))
        tablas = {}
        for tabla, columna, tipo, acepta_nulos, es_pk, es_fk in filas:
            tipo = tipo.replace("character varying", "varchar").replace("timestamp without time zone", "timestamp")
            if tabla not in tablas:
                item_t = QTreeWidgetItem([tabla, "", ""])
                item_t.setFont(0, negrita)
                self.arbol.addTopLevelItem(item_t)
                tablas[tabla] = item_t
            clave = "PK" if es_pk else ("FK" if es_fk else "")
            item_c = QTreeWidgetItem([columna, tipo + ("" if acepta_nulos else " NOT NULL"), clave])
            if clave:
                item_c.setForeground(2, color_pk if es_pk else color_fk)
                item_c.setFont(2, negrita)
            tablas[tabla].addChild(item_c)
        self.arbol.setColumnWidth(0, 210)
        self.arbol.setColumnWidth(1, 170)
        self.arbol.setColumnWidth(2, 45)

    def _insertar_nombre(self, item, _columna):
        """Doble clic: escribe el nombre de la tabla o columna en el editor, donde está el cursor."""
        self.editor.insertPlainText(item.text(0))
        self.editor.setFocus()

    # ------------------------------------------------------------------
    # Ejemplos, historial y limpieza
    # ------------------------------------------------------------------
    def _cargar_ejemplo(self, indice):
        if indice > 0:
            self.editor.setPlainText(EJEMPLOS[indice - 1][1])
        self.cmb_ejemplos.setCurrentIndex(0)             # vuelve al texto "Ejemplos..."
        self.editor.setFocus()

    def _cargar_historial(self, indice):
        if indice > 0:
            self.editor.setPlainText(self._historial[indice - 1])
        self.cmb_historial.setCurrentIndex(0)
        self.editor.setFocus()

    def _registrar_historial(self, sentencia: str):
        if sentencia in self._historial:                 # sin repetidos: sube al primer lugar
            self._historial.remove(sentencia)
        self._historial.insert(0, sentencia)
        del self._historial[MAX_HISTORIAL:]
        self.cmb_historial.clear()
        self.cmb_historial.addItem("Historial de la sesión...")
        for s in self._historial:
            una_linea = " ".join(s.split())
            self.cmb_historial.addItem(una_linea if len(una_linea) <= 70 else una_linea[:67] + "...")

    def _limpiar(self):
        self.editor.clear()
        self.tabla.limpiar()
        self._columnas, self._filas = [], []
        self.btn_exportar.setEnabled(False)
        self.lbl_estado.setText("Escriba una consulta de lectura y pulse «Ejecutar».")
        self.editor.setFocus()

    # ------------------------------------------------------------------
    # Ejecución
    # ------------------------------------------------------------------
    def _pulsar_ejecutar(self):
        """El mismo botón sirve para ejecutar y (mientras corre una consulta) para detenerla."""
        if self._hilo is not None:
            self.bd.cancelar()
            self.lbl_estado.setText("Deteniendo la consulta...")
            return
        self.ejecutar()

    def ejecutar(self):
        cursor = self.editor.textCursor()
        texto = cursor.selection().toPlainText() if cursor.hasSelection() else self.editor.toPlainText()
        sentencia, error = preparar(texto)
        if error:
            self.lbl_estado.setText("No se ejecutó la consulta.")
            QMessageBox.warning(self, "Revise la consulta", error)
            return

        self._registrar_historial(sentencia)
        self.btn_ejecutar.setText("■  Detener consulta")
        self.btn_exportar.setEnabled(False)
        self.lbl_estado.setText("Ejecutando consulta..." + (" (solo el texto seleccionado)" if cursor.hasSelection() else ""))
        self.tabla.limpiar()

        # Se piden LIMITE+1 filas para saber si el resultado fue recortado
        self._hilo = HiloConsulta(self.bd, sentencia, limite=LIMITE_FILAS_CONSULTA_LIBRE + 1)
        self._hilo.terminado.connect(self._al_terminar)
        self._hilo.fallo.connect(self._al_fallar)
        self._hilo.finished.connect(self._liberar_hilo)
        self._hilo.start()

    def _al_terminar(self, columnas, filas, segundos):
        recortado = len(filas) > LIMITE_FILAS_CONSULTA_LIBRE
        if recortado:
            filas = filas[:LIMITE_FILAS_CONSULTA_LIBRE]
        self._columnas, self._filas = columnas, filas
        self.tabla.mostrar(columnas, filas)
        self.btn_exportar.setEnabled(len(filas) > 0)
        if not columnas:
            texto = "La consulta se ejecutó y no devuelve filas."
        elif recortado:
            texto = (f"Mostrando solo las primeras {LIMITE_FILAS_CONSULTA_LIBRE:,} filas".replace(",", ".")
                     + f" (hay más) — {segundos * 1000:.0f} ms. Agregue filtros o LIMIT para acotar el resultado.")
        else:
            texto = f"{len(filas)} fila(s) en {segundos * 1000:.0f} ms  |  clic en un encabezado para ordenar"
        self.lbl_estado.setText(texto)

    def _al_fallar(self, mensaje):
        self.lbl_estado.setText("La consulta falló.")
        QMessageBox.critical(self, "Error al ejecutar la consulta", mensaje)

    def _liberar_hilo(self):
        self._hilo.deleteLater()
        self._hilo = None
        self.btn_ejecutar.setText("▶  Ejecutar  (Ctrl+Enter)")

    def detener(self):
        """Al cerrar la ventana: cancela la consulta en curso y espera al hilo."""
        if self._hilo is not None:
            self.bd.cancelar()
            self._hilo.wait(3000)

    # ------------------------------------------------------------------
    def exportar(self):
        exportar_con_dialogo(self, "consulta_libre", self._columnas, self._filas)
