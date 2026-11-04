"""
ventanas/login.py - Ventana de conexión a la base de datos.
"""
from PyQt6.QtCore import Qt
from PyQt6.QtGui import QIntValidator
from PyQt6.QtWidgets import (QApplication, QCheckBox, QDialog, QFormLayout, QHBoxLayout,
                             QLabel, QLineEdit, QPushButton, QVBoxLayout)

from config import (APP_NOMBRE, BASE_POR_DEFECTO, HOST_POR_DEFECTO,
                    PUERTO_POR_DEFECTO, USUARIO_POR_DEFECTO)
from db import BaseDeDatos, ErrorBD


class DialogoLogin(QDialog):
    """
    Pide los datos de conexión. Si la conexión tiene éxito se cierra con
    'accept()' (resultado Aceptado) y la conexión queda abierta dentro de 'bd'.
    """

    def __init__(self, bd: BaseDeDatos, parent=None, *, titulo_ventana="Conexión a la base de datos",
                 encabezado=APP_NOMBRE, subtitulo=None, usuario_defecto=USUARIO_POR_DEFECTO,
                 datos_fijos=None, solo_lectura=True):
        """
        datos_fijos : si se indica {"host":..., "puerto":..., "base":...}, el formulario solo pide
                      usuario y contraseña (se usa para la sesión de gestión).
        solo_lectura: False únicamente para la sesión de gestión.
        """
        super().__init__(parent)
        self.bd = bd
        self.datos_fijos = datos_fijos
        self.solo_lectura = solo_lectura
        self.setWindowTitle(titulo_ventana)
        self.setMinimumWidth(440)

        # --- Encabezado ---------------------------------------------------
        titulo = QLabel(encabezado)
        titulo.setObjectName("titulo")
        titulo.setWordWrap(True)
        subtitulo = QLabel(subtitulo or
                           "Conéctese a la base de datos PostgreSQL del proyecto.\n"
                           "Los datos ya vienen cargados: normalmente solo debe escribir la contraseña.")
        subtitulo.setObjectName("subtitulo")
        subtitulo.setWordWrap(True)
        subtitulo.setObjectName("subtitulo")

        # --- Campos del formulario -----------------------------------------
        self.txt_host = QLineEdit(HOST_POR_DEFECTO)
        self.txt_host.setPlaceholderText("localhost (este computador)")
        self.txt_puerto = QLineEdit(str(PUERTO_POR_DEFECTO))
        self.txt_puerto.setPlaceholderText("5432")
        self.txt_puerto.setValidator(QIntValidator(1, 65535))     # solo acepta números válidos de puerto
        self.txt_base = QLineEdit(BASE_POR_DEFECTO)
        self.txt_base.setPlaceholderText("nombre de la base creada en pgAdmin")
        self.txt_usuario = QLineEdit(usuario_defecto)
        self.txt_usuario.setPlaceholderText("app_lectura")
        self.txt_clave = QLineEdit()
        self.txt_clave.setEchoMode(QLineEdit.EchoMode.Password)   # muestra puntos en vez de letras
        self.txt_clave.setPlaceholderText("contraseña de app_lectura")

        self.chk_mostrar = QCheckBox("Mostrar contraseña")
        self.chk_mostrar.toggled.connect(self._alternar_clave)

        form = QFormLayout()
        form.setVerticalSpacing(10)
        if datos_fijos is None:                      # login normal: se piden todos los datos
            form.addRow("Servidor:", self.txt_host)
            form.addRow("Puerto:", self.txt_puerto)
            form.addRow("Base de datos:", self.txt_base)
        form.addRow("Usuario:", self.txt_usuario)
        form.addRow("Contraseña:", self.txt_clave)
        form.addRow("", self.chk_mostrar)

        # --- Mensaje de estado y botones -----------------------------------
        self.lbl_mensaje = QLabel("")
        self.lbl_mensaje.setWordWrap(True)

        self.btn_conectar = QPushButton("Conectar")
        self.btn_conectar.setObjectName("primario")
        self.btn_conectar.setDefault(True)               # Enter = Conectar
        self.btn_conectar.clicked.connect(self._conectar)
        btn_cancelar = QPushButton("Cancelar")
        btn_cancelar.clicked.connect(self.reject)

        botones = QHBoxLayout()
        botones.addStretch()
        botones.addWidget(btn_cancelar)
        botones.addWidget(self.btn_conectar)

        # --- Disposición general -------------------------------------------
        layout = QVBoxLayout(self)
        layout.setContentsMargins(24, 20, 24, 20)
        layout.setSpacing(12)
        layout.addWidget(titulo)
        layout.addWidget(subtitulo)
        layout.addSpacing(6)
        layout.addLayout(form)
        layout.addWidget(self.lbl_mensaje)
        layout.addLayout(botones)

        # El cursor empieza en la contraseña (lo único que normalmente falta)
        self.txt_clave.setFocus()

    # ------------------------------------------------------------------
    def _alternar_clave(self, visible: bool):
        modo = QLineEdit.EchoMode.Normal if visible else QLineEdit.EchoMode.Password
        self.txt_clave.setEchoMode(modo)

    def _mostrar_mensaje(self, texto: str, tipo: str = "error"):
        self.lbl_mensaje.setObjectName(tipo)              # 'error' u 'ok' (define el color)
        self.lbl_mensaje.style().unpolish(self.lbl_mensaje)
        self.lbl_mensaje.style().polish(self.lbl_mensaje)  # aplica el nuevo estilo
        self.lbl_mensaje.setText(texto)

    def _conectar(self):
        usuario = self.txt_usuario.text().strip()
        clave = self.txt_clave.text()
        if self.datos_fijos is not None:             # sesión de gestión: mismo servidor y base
            host, base, puerto = (self.datos_fijos["host"], self.datos_fijos["base"],
                                  self.datos_fijos["puerto"])
        else:
            host = self.txt_host.text().strip()
            base = self.txt_base.text().strip()
            try:
                puerto = int(self.txt_puerto.text() or PUERTO_POR_DEFECTO)   # vacío = puerto por defecto
            except ValueError:
                self._mostrar_mensaje("El puerto debe ser un número entre 1 y 65535.")
                self.txt_puerto.setFocus()
                return

        # Validación básica antes de intentar conectar
        if not host or not base or not usuario:
            self._mostrar_mensaje("Complete el servidor, la base de datos y el usuario.")
            return
        if not clave:
            self._mostrar_mensaje("Escriba la contraseña.")
            self.txt_clave.setFocus()
            return

        # Mientras conecta: cursor de espera y botón desactivado (evita doble clic)
        self.btn_conectar.setEnabled(False)
        self._mostrar_mensaje("Conectando...", "subtitulo")
        QApplication.setOverrideCursor(Qt.CursorShape.WaitCursor)
        QApplication.processEvents()
        try:
            self.bd.conectar(host, puerto, base, usuario, clave, solo_lectura=self.solo_lectura)
        except ErrorBD as e:
            self._mostrar_mensaje(str(e))
            self.txt_clave.selectAll()
            self.txt_clave.setFocus()
        else:
            self.txt_clave.clear()          # no dejar la contraseña en memoria de la interfaz
            self.accept()                   # cierra el diálogo con resultado "Aceptado"
        finally:
            QApplication.restoreOverrideCursor()
            self.btn_conectar.setEnabled(True)
