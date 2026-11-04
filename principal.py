"""
ventanas/principal.py - Ventana principal de la aplicación.

En esta etapa muestra el resumen de las tablas y el panel de las 10 consultas de
negocio y la consulta libre. En las siguientes etapas se agregarán más pestañas
(gestión de empleados, auditoría e inconsistencias).
"""
from PyQt6.QtCore import Qt
from PyQt6.QtGui import QAction, QKeySequence
from PyQt6.QtWidgets import (QAbstractItemView, QHBoxLayout, QHeaderView, QLabel,
                             QMainWindow, QMessageBox, QPushButton, QTableWidget,
                             QTableWidgetItem, QTabWidget, QVBoxLayout, QWidget)

from config import APP_NOMBRE, APP_VERSION
from db import BaseDeDatos, ErrorBD
from ventanas.panel_consultas import PanelConsultas
from ventanas.panel_gestion import PanelGestion
from ventanas.panel_libre import PanelConsultaLibre
from ventanas.panel_registros import PanelRegistros


SQL_AUDITORIA = """
    SELECT au.id_auditoria AS id, au.fecha_reasignacion AS fecha,
           ar.nombre_host AS activo, ar.tipo_dispositivo AS tipo,
           ea.nombre AS empleado_anterior, ea.departamento AS departamento,
           en.nombre AS empleado_nuevo, au.motivo
    FROM   auditoria au
    JOIN   activos_red ar ON ar.id_activo   = au.activo_id
    JOIN   empleados   ea ON ea.id_empleado = au.empleado_anterior_id
    JOIN   empleados   en ON en.id_empleado = au.empleado_nuevo_id
    ORDER  BY au.fecha_reasignacion DESC, au.id_auditoria DESC
"""
SQL_INCONSISTENCIAS = """
    SELECT id_inconsistencia AS id, fecha_registro AS fecha, tabla_origen AS tabla,
           operacion, motivo, datos_rechazados AS datos
    FROM   inconsistencias
    ORDER  BY fecha_registro DESC, id_inconsistencia DESC
"""


class VentanaPrincipal(QMainWindow):
    def __init__(self, bd: BaseDeDatos):
        super().__init__()
        self.bd = bd
        self.cerro_sesion = False        # True si el usuario eligió "Cerrar sesión"
        self.setWindowTitle(APP_NOMBRE)
        self.resize(1180, 760)

        self._crear_menu()

        # Pestañas
        self.pestanas = QTabWidget()
        self.panel_consultas = PanelConsultas(self.bd)
        self.pestanas.addTab(self._crear_pestana_resumen(), "Resumen de la base de datos")
        self.panel_libre = PanelConsultaLibre(self.bd)
        self.pestanas.addTab(self.panel_consultas, "Consultas de negocio")
        self.pestanas.addTab(self.panel_libre, "Consulta libre")

        # Etapa 5: gestión de empleados y bitácoras
        self.panel_auditoria = PanelRegistros(
            self.bd,
            descripcion="Reasignaciones de activos cuando un empleado renuncia o es despedido: "
                        "a qué empleado pasó cada activo.",
            sql=SQL_AUDITORIA, etiqueta_filtro="Motivo:", columna_filtro="motivo",
            nombre_csv="auditoria_reasignaciones")
        self.panel_inconsistencias = PanelRegistros(
            self.bd,
            descripcion="Registros que el sistema no dejó incluir por incumplir una regla de negocio, "
                        "con el motivo del rechazo.",
            sql=SQL_INCONSISTENCIAS, etiqueta_filtro="Tabla:", columna_filtro="tabla",
            nombre_csv="inconsistencias")
        self.panel_gestion = PanelGestion(self.bd)
        self.panel_gestion.datos_modificados.connect(self._refrescar_tras_cambios)
        self.pestanas.addTab(self.panel_gestion, "Gestión de empleados")
        self.pestanas.addTab(self.panel_auditoria, "Auditoría")
        self.pestanas.addTab(self.panel_inconsistencias, "Inconsistencias")
        self.setCentralWidget(self.pestanas)

        self.statusBar().showMessage(self._texto_sesion())
        self.cargar_resumen()

    # ------------------------------------------------------------------
    # Construcción de la interfaz
    # ------------------------------------------------------------------
    def _crear_menu(self):
        menu_archivo = self.menuBar().addMenu("&Archivo")

        accion_sesion = QAction("&Cerrar sesión", self)
        accion_sesion.setShortcut(QKeySequence("Ctrl+L"))
        accion_sesion.triggered.connect(self._cerrar_sesion)
        menu_archivo.addAction(accion_sesion)

        accion_salir = QAction("&Salir", self)
        accion_salir.setShortcut(QKeySequence("Ctrl+Q"))
        accion_salir.triggered.connect(self.close)
        menu_archivo.addAction(accion_salir)

        menu_ayuda = self.menuBar().addMenu("A&yuda")
        accion_acerca = QAction("&Acerca de", self)
        accion_acerca.triggered.connect(self._acerca_de)
        menu_ayuda.addAction(accion_acerca)

    def _crear_pestana_resumen(self) -> QWidget:
        pagina = QWidget()
        layout = QVBoxLayout(pagina)
        layout.setContentsMargins(16, 16, 16, 16)

        self.lbl_sesion = QLabel(self._texto_sesion())
        self.lbl_sesion.setObjectName("subtitulo")

        self.tabla = QTableWidget(0, 2)
        self.tabla.setHorizontalHeaderLabels(["Tabla", "Registros"])
        self.tabla.setAlternatingRowColors(True)
        self.tabla.setEditTriggers(QAbstractItemView.EditTrigger.NoEditTriggers)  # solo lectura
        self.tabla.setSelectionBehavior(QAbstractItemView.SelectionBehavior.SelectRows)
        self.tabla.verticalHeader().setVisible(False)
        self.tabla.horizontalHeader().setSectionResizeMode(0, QHeaderView.ResizeMode.Stretch)
        self.tabla.horizontalHeader().setSectionResizeMode(1, QHeaderView.ResizeMode.ResizeToContents)

        self.lbl_total = QLabel("")
        btn_actualizar = QPushButton("Actualizar")
        btn_actualizar.clicked.connect(self.cargar_resumen)

        pie = QHBoxLayout()
        pie.addWidget(self.lbl_total)
        pie.addStretch()
        pie.addWidget(btn_actualizar)

        layout.addWidget(self.lbl_sesion)
        layout.addWidget(self.tabla)
        layout.addLayout(pie)
        return pagina

    # ------------------------------------------------------------------
    # Datos
    # ------------------------------------------------------------------
    def _texto_sesion(self) -> str:
        i = self.bd.info
        return (f"Conectado a «{i['base']}» en {i['host']}:{i['puerto']}  |  "
                f"usuario: {i['usuario']}  |  PostgreSQL {i['version']}  |  modo solo lectura")

    def cargar_resumen(self):
        try:
            filas = self.bd.resumen_tablas()
        except ErrorBD as e:
            QMessageBox.critical(self, "Error al consultar", str(e))
            return
        self.tabla.setRowCount(len(filas))
        for r, (nombre, cantidad) in enumerate(filas):
            self.tabla.setItem(r, 0, QTableWidgetItem(nombre))
            item = QTableWidgetItem(f"{cantidad:,}".replace(",", "."))   # 1.234 estilo español
            item.setTextAlignment(Qt.AlignmentFlag.AlignRight | Qt.AlignmentFlag.AlignVCenter)
            self.tabla.setItem(r, 1, item)
        total = sum(c for _, c in filas)
        self.lbl_total.setText(f"{len(filas)} tablas  |  {total} registros en total")

    def _refrescar_tras_cambios(self):
        """Tras inactivar un empleado: actualizar las pestañas que muestran esos datos."""
        self.panel_auditoria.recargar()
        self.panel_inconsistencias.recargar()
        self.cargar_resumen()

    # ------------------------------------------------------------------
    # Cierre de la ventana
    # ------------------------------------------------------------------
    def closeEvent(self, evento):
        self.panel_consultas.detener()      # cancela las consultas en curso, si las hay
        self.panel_libre.detener()
        self.panel_gestion.detener()
        super().closeEvent(evento)

    # ------------------------------------------------------------------
    # Acciones del menú
    # ------------------------------------------------------------------
    def _cerrar_sesion(self):
        self.cerro_sesion = True
        self.close()

    def _acerca_de(self):
        QMessageBox.about(self, "Acerca de",
                          f"<b>{APP_NOMBRE}</b><br>Versión {APP_VERSION}<br><br>"
                          "Aplicación de escritorio para consultar la base de datos del SOC.")
