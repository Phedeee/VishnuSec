"""
ventanas/panel_gestion.py - Pestaña "Gestión de empleados" (ETAPA 5).

Permite inactivar a un empleado (renuncia o despido). Al hacerlo, el procedimiento
almacenado sp_inactivar_empleado reasigna AUTOMÁTICAMENTE sus activos a otro
empleado del mismo departamento y deja constancia en las tablas auditoria e
inconsistencias.

SEGURIDAD
- La lista de empleados se lee con la sesión normal (solo lectura).
- Para inactivar se necesita una SEGUNDA sesión: el usuario 'app_gestion', que no puede
  modificar tablas directamente; solo puede ejecutar el procedimiento. Se le pide su
  contraseña la primera vez que se usa la función.
"""
from PyQt6.QtCore import Qt, pyqtSignal
from PyQt6.QtWidgets import (QAbstractItemView, QComboBox, QGroupBox, QHBoxLayout, QLabel,
                             QLineEdit, QMessageBox, QPushButton, QSplitter, QVBoxLayout, QWidget)

from config import USUARIO_GESTION_POR_DEFECTO
from db import BaseDeDatos, ErrorBD
from ventanas.hilos import HiloTarea
from ventanas.login import DialogoLogin
from ventanas.widgets import TablaResultados

MAX_ACTIVOS_POR_EMPLEADO = 5      # mismo límite que aplica el trigger trg_validar_asignacion

SQL_EMPLEADOS = """
    SELECT e.id_empleado AS id, e.nombre, e.correo, e.departamento, e.estado,
           e.motivo_retiro, e.fecha_retiro,
           COUNT(a.id_asignacion) AS activos_vigentes
    FROM   empleados e
    LEFT JOIN asignaciones_activos a
           ON a.empleado_id = e.id_empleado AND a.estado = 'Vigente'
    GROUP  BY e.id_empleado
    ORDER  BY e.id_empleado
"""
SQL_ASIGNADOS = """
    SELECT aa.id_asignacion, ar.nombre_host, ar.tipo_dispositivo, ar.criticidad, aa.fecha_asignacion
    FROM   asignaciones_activos aa
    JOIN   activos_red ar ON ar.id_activo = aa.activo_id
    WHERE  aa.empleado_id = %s AND aa.estado = 'Vigente'
    ORDER  BY aa.id_asignacion
"""
SQL_CANDIDATOS = """
    SELECT e.id_empleado, e.nombre, COUNT(a.id_asignacion)
    FROM   empleados e
    LEFT JOIN asignaciones_activos a
           ON a.empleado_id = e.id_empleado AND a.estado = 'Vigente'
    WHERE  e.departamento = %s AND e.estado = 'Activo' AND e.id_empleado <> %s
    GROUP  BY e.id_empleado
"""
SQL_HISTORIAL = """
    SELECT au.fecha_reasignacion AS fecha, ar.nombre_host AS activo,
           ar.tipo_dispositivo AS tipo, en.nombre AS paso_a, au.motivo
    FROM   auditoria au
    JOIN   activos_red ar ON ar.id_activo   = au.activo_id
    JOIN   empleados   en ON en.id_empleado = au.empleado_nuevo_id
    WHERE  au.empleado_anterior_id = %s
    ORDER  BY au.fecha_reasignacion DESC, au.id_auditoria DESC
"""


class PanelGestion(QWidget):
    datos_modificados = pyqtSignal()       # se emite tras inactivar: otras pestañas se actualizan

    def __init__(self, bd: BaseDeDatos, parent=None):
        super().__init__(parent)
        self.bd = bd                            # sesión de solo lectura
        self.bd_gestion = BaseDeDatos()         # sesión de gestión (se abre cuando se necesita)
        self._hilo = None
        self._n_activos = 0                     # activos del empleado seleccionado (vista previa)

        # ================= Arriba: lista de empleados =========================
        self.txt_buscar = QLineEdit()
        self.txt_buscar.setPlaceholderText("Buscar por nombre, correo, departamento...")
        self.txt_buscar.setClearButtonEnabled(True)
        self.txt_buscar.textChanged.connect(self._filtrar)
        self.cmb_estado = QComboBox()
        self.cmb_estado.addItems(["Todos", "Activo", "Inactivo"])
        self.cmb_estado.currentIndexChanged.connect(self._filtrar)
        self.cmb_depto = QComboBox()
        self.cmb_depto.setMinimumWidth(150)
        self.cmb_depto.currentIndexChanged.connect(self._filtrar)
        btn_actualizar = QPushButton("Actualizar")
        btn_actualizar.clicked.connect(self.cargar_empleados)

        filtros = QHBoxLayout()
        filtros.addWidget(self.txt_buscar, 1)
        filtros.addWidget(QLabel("Estado:"))
        filtros.addWidget(self.cmb_estado)
        filtros.addWidget(QLabel("Departamento:"))
        filtros.addWidget(self.cmb_depto)
        filtros.addWidget(btn_actualizar)

        self.tabla = TablaResultados()
        self.tabla.setSelectionMode(QAbstractItemView.SelectionMode.SingleSelection)
        self.tabla.itemSelectionChanged.connect(self._mostrar_detalle)
        self.lbl_cuenta = QLabel("")
        self.lbl_cuenta.setObjectName("subtitulo")

        superior = QWidget()
        lay_sup = QVBoxLayout(superior)
        lay_sup.setContentsMargins(0, 0, 0, 0)
        lay_sup.setSpacing(6)
        lay_sup.addLayout(filtros)
        lay_sup.addWidget(self.tabla, 1)
        lay_sup.addWidget(self.lbl_cuenta)

        # ================= Abajo izquierda: detalle / vista previa ============
        self.lbl_detalle = QLabel("Seleccione un empleado de la lista.")
        self.lbl_detalle.setObjectName("titulo")
        self.lbl_detalle.setStyleSheet("font-size: 13pt;")
        self.lbl_detalle.setWordWrap(True)
        self.tabla_detalle = TablaResultados()
        self.lbl_nota = QLabel("")
        self.lbl_nota.setObjectName("subtitulo")
        self.lbl_nota.setWordWrap(True)

        detalle = QWidget()
        lay_det = QVBoxLayout(detalle)
        lay_det.setContentsMargins(0, 0, 0, 0)
        lay_det.setSpacing(4)
        lay_det.addWidget(self.lbl_detalle)
        lay_det.addWidget(self.tabla_detalle, 1)
        lay_det.addWidget(self.lbl_nota)

        # ================= Abajo derecha: acción y sesión de gestión ==========
        caja = QGroupBox("Inactivar empleado")
        lay_caja = QVBoxLayout(caja)
        self.lbl_seleccion = QLabel("Ningún empleado seleccionado.")
        self.lbl_seleccion.setWordWrap(True)
        self.cmb_motivo = QComboBox()
        self.cmb_motivo.addItems(["Renuncia", "Despido"])
        self.btn_inactivar = QPushButton("Inactivar empleado...")
        self.btn_inactivar.setObjectName("peligro")
        self.btn_inactivar.setEnabled(False)
        self.btn_inactivar.clicked.connect(self._inactivar)
        self.lbl_sesion = QLabel("")
        self.lbl_sesion.setObjectName("subtitulo")
        self.lbl_sesion.setWordWrap(True)
        self.btn_cerrar_gestion = QPushButton("Cerrar sesión de gestión")
        self.btn_cerrar_gestion.clicked.connect(self.cerrar_sesion_gestion)
        lay_caja.addWidget(self.lbl_seleccion)
        lay_caja.addWidget(QLabel("Motivo del retiro:"))
        lay_caja.addWidget(self.cmb_motivo)
        lay_caja.addWidget(self.btn_inactivar)
        lay_caja.addSpacing(10)
        lay_caja.addWidget(self.lbl_sesion)
        lay_caja.addWidget(self.btn_cerrar_gestion)
        lay_caja.addStretch()
        caja.setMinimumWidth(300)

        inferior = QSplitter(Qt.Orientation.Horizontal)
        inferior.addWidget(detalle)
        inferior.addWidget(caja)
        inferior.setSizes([760, 320])
        inferior.setChildrenCollapsible(False)

        vertical = QSplitter(Qt.Orientation.Vertical)
        vertical.addWidget(superior)
        vertical.addWidget(inferior)
        vertical.setSizes([330, 300])
        vertical.setChildrenCollapsible(False)

        layout = QVBoxLayout(self)
        layout.setContentsMargins(12, 12, 12, 12)
        layout.addWidget(vertical)

        self._actualizar_estado_sesion()
        self.cargar_empleados()

    # ------------------------------------------------------------------
    # Lista de empleados
    # ------------------------------------------------------------------
    def cargar_empleados(self):
        seleccionado = self._empleado_seleccionado()
        try:
            columnas, filas = self.bd.consultar(SQL_EMPLEADOS)
        except ErrorBD as e:
            QMessageBox.critical(self, "Error al consultar", str(e))
            return
        self.tabla.mostrar(columnas, filas)
        self._total = len(filas)

        deptos = sorted({f[3] for f in filas})
        previo = self.cmb_depto.currentText()
        self.cmb_depto.blockSignals(True)
        self.cmb_depto.clear()
        self.cmb_depto.addItem("Todos")
        self.cmb_depto.addItems(deptos)
        pos = self.cmb_depto.findText(previo)
        self.cmb_depto.setCurrentIndex(pos if pos >= 0 else 0)
        self.cmb_depto.blockSignals(False)
        self._filtrar()

        # Volver a seleccionar al mismo empleado (si sigue visible)
        if seleccionado:
            for r in range(self.tabla.rowCount()):
                if int(self.tabla.valor_fila(r, 0)) == seleccionado["id"] and not self.tabla.isRowHidden(r):
                    self.tabla.selectRow(r)
                    break
        self._mostrar_detalle()

    def _filtrar(self):
        if self.tabla.columnCount() == 0:
            return
        estado = "" if self.cmb_estado.currentIndex() == 0 else self.cmb_estado.currentText()
        depto = "" if self.cmb_depto.currentIndex() <= 0 else self.cmb_depto.currentText()
        visibles = self.tabla.filtrar(self.txt_buscar.text(), [(3, depto), (4, estado)])
        self.lbl_cuenta.setText(f"Mostrando {visibles} de {self._total} empleados  |  "
                                "seleccione uno para ver sus activos")

    def _empleado_seleccionado(self):
        """Datos del empleado seleccionado o None."""
        fila = self.tabla.currentRow()
        if fila < 0 or self.tabla.isRowHidden(fila) or not self.tabla.selectedItems():
            return None
        return {"id": int(self.tabla.valor_fila(fila, 0)),
                "nombre": self.tabla.item(fila, 1).text(),
                "departamento": self.tabla.item(fila, 3).text(),
                "estado": self.tabla.item(fila, 4).text()}

    # ------------------------------------------------------------------
    # Detalle y vista previa
    # ------------------------------------------------------------------
    def _mostrar_detalle(self):
        emp = self._empleado_seleccionado()
        self._n_activos = 0
        if emp is None:
            self.lbl_detalle.setText("Seleccione un empleado de la lista.")
            self.lbl_seleccion.setText("Ningún empleado seleccionado.")
            self.tabla_detalle.limpiar()
            self.lbl_nota.setText("")
            self.btn_inactivar.setEnabled(False)
            return
        try:
            if emp["estado"] == "Activo":
                self._detalle_activo(emp)
            else:
                self._detalle_inactivo(emp)
        except ErrorBD as e:
            QMessageBox.critical(self, "Error al consultar", str(e))
        activo = emp["estado"] == "Activo"
        self.btn_inactivar.setEnabled(activo and self._hilo is None)
        self.lbl_seleccion.setText(
            f"<b>{emp['nombre']}</b><br>{emp['departamento']}" if activo
            else f"<b>{emp['nombre']}</b> ya está inactivo.<br>No es posible inactivarlo de nuevo.")

    def _detalle_activo(self, emp):
        _, asignados = self.bd.consultar(SQL_ASIGNADOS, (emp["id"],))
        _, candidatos = self.bd.consultar(SQL_CANDIDATOS, (emp["departamento"], emp["id"]))
        self._n_activos = len(asignados)

        # --- Simulación: misma regla del procedimiento (el de menos activos; en empate, el id menor)
        cargas = {c[0]: [c[1], c[2]] for c in candidatos}      # id -> [nombre, activos vigentes]
        filas = []
        for _, host, tipo, crit, desde in asignados:
            if not cargas:
                destino = "— sin reemplazo en el departamento"
            else:
                elegido = min(cargas, key=lambda i: (cargas[i][1], i))
                if cargas[elegido][1] >= MAX_ACTIVOS_POR_EMPLEADO:
                    destino = f"— rechazado: {cargas[elegido][0]} ya tiene {MAX_ACTIVOS_POR_EMPLEADO} activos"
                else:
                    destino = cargas[elegido][0]
                    cargas[elegido][1] += 1
            filas.append((host, tipo, crit, desde, destino))

        n = len(asignados)
        self.lbl_detalle.setText(f"{emp['nombre']}  —  {emp['departamento']}  —  "
                                 f"{n} activo(s) vigente(s)")
        self.tabla_detalle.mostrar(["activo", "tipo", "criticidad", "asignado_desde", "pasaría_a (vista previa)"], filas)
        if n == 0:
            self.lbl_nota.setText("Este empleado no tiene activos asignados: al inactivarlo solo cambia su estado.")
        elif not candidatos:
            self.lbl_nota.setText("⚠ No hay otros empleados activos en este departamento: los activos quedarán "
                                  "sin responsable y se registrará en Inconsistencias.")
        else:
            self.lbl_nota.setText("Vista previa: cada activo pasa al empleado activo del mismo departamento "
                                  "con menos activos. El resultado real queda registrado en la pestaña Auditoría.")

    def _detalle_inactivo(self, emp):
        columnas, filas = self.bd.consultar(SQL_HISTORIAL, (emp["id"],))
        self.lbl_detalle.setText(f"{emp['nombre']}  —  {emp['departamento']}  —  INACTIVO")
        self.tabla_detalle.mostrar(columnas, filas)
        self.lbl_nota.setText(f"Historial: {len(filas)} activo(s) que tenía y fueron reasignados a otro empleado."
                              if filas else "No tenía activos asignados al momento de su retiro.")

    # ------------------------------------------------------------------
    # Sesión de gestión
    # ------------------------------------------------------------------
    def _actualizar_estado_sesion(self):
        activa = self.bd_gestion.conectada
        self.btn_cerrar_gestion.setVisible(activa)
        if activa:
            self.lbl_sesion.setText(f"Sesión de gestión ACTIVA (usuario {self.bd_gestion.info['usuario']}).")
        else:
            self.lbl_sesion.setText("Sesión de gestión no iniciada. Se solicitará la contraseña del usuario "
                                    f"{USUARIO_GESTION_POR_DEFECTO} al inactivar un empleado.")

    def _asegurar_sesion_gestion(self) -> bool:
        """Abre la sesión de gestión si hace falta. Devuelve False si el usuario cancela."""
        if self.bd_gestion.conectada:
            return True
        i = self.bd.info
        dialogo = DialogoLogin(
            self.bd_gestion, self, titulo_ventana="Sesión de gestión", encabezado="Sesión de gestión",
            subtitulo="Para inactivar empleados se necesita el usuario de gestión, que solo puede "
                      "ejecutar el procedimiento de inactivación (no puede modificar tablas directamente).",
            usuario_defecto=USUARIO_GESTION_POR_DEFECTO,
            datos_fijos={"host": i["host"], "puerto": i["puerto"], "base": i["base"]},
            solo_lectura=False)
        aceptado = dialogo.exec() == DialogoLogin.DialogCode.Accepted
        self._actualizar_estado_sesion()
        return aceptado

    def cerrar_sesion_gestion(self):
        self.bd_gestion.cerrar()
        self._actualizar_estado_sesion()

    # ------------------------------------------------------------------
    # Inactivar
    # ------------------------------------------------------------------
    def _inactivar(self):
        emp = self._empleado_seleccionado()
        if emp is None or emp["estado"] != "Activo" or self._hilo is not None:
            return
        if not self._asegurar_sesion_gestion():
            return
        motivo = self.cmb_motivo.currentText()
        cuerpo = (f"¿Inactivar a {emp['nombre']} ({emp['departamento']}) por {motivo.lower()}?\n\n"
                  + (f"Se reasignarán {self._n_activos} activo(s) a otros empleados del departamento.\n\n"
                     if self._n_activos else "No tiene activos asignados.\n\n")
                  + "El cambio se guarda de forma definitiva en la base de datos.")
        respuesta = QMessageBox.question(self, "Confirmar inactivación", cuerpo,
                                         QMessageBox.StandardButton.Yes | QMessageBox.StandardButton.No,
                                         QMessageBox.StandardButton.No)
        if respuesta != QMessageBox.StandardButton.Yes:
            return

        self.btn_inactivar.setEnabled(False)
        self.btn_inactivar.setText("Procesando...")
        self._empleado_en_proceso = emp
        self._hilo = HiloTarea(lambda: self.bd_gestion.inactivar_empleado(emp["id"], motivo))
        self._hilo.terminado.connect(self._al_inactivar)
        self._hilo.fallo.connect(self._al_fallar)
        self._hilo.finished.connect(self._liberar_hilo)
        self._hilo.start()

    def _al_inactivar(self, avisos):
        emp = self._empleado_en_proceso
        try:
            _, filas = self.bd.consultar(SQL_HISTORIAL, (emp["id"],))
        except ErrorBD:
            filas = []
        nuevas = [f"   •  {host}  →  {paso_a}" for _, host, _, paso_a, _ in filas[:15]]
        texto = "El empleado fue inactivado correctamente.\n\n" + "\n".join(a for a in avisos if a)
        if nuevas:
            texto += "\n\nReasignaciones registradas en Auditoría:\n" + "\n".join(nuevas)
        QMessageBox.information(self, "Inactivación completada", texto)
        self.cargar_empleados()
        self.datos_modificados.emit()

    def _al_fallar(self, mensaje):
        QMessageBox.critical(self, "No se pudo inactivar al empleado",
                             mensaje + "\n\nNo se realizó ningún cambio en la base de datos.")
        self.cargar_empleados()

    def _liberar_hilo(self):
        self._hilo.deleteLater()
        self._hilo = None
        self.btn_inactivar.setText("Inactivar empleado...")
        self._actualizar_estado_sesion()
        self._mostrar_detalle()

    def detener(self):
        """Al cerrar la ventana: espera a que termine una inactivación en curso y cierra la sesión de gestión."""
        if self._hilo is not None:
            self._hilo.wait(35000)
        self.bd_gestion.cerrar()
