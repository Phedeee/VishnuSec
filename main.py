"""
main.py - Punto de entrada de la aplicación.

Para ejecutarla:            python main.py
Informe de diagnóstico:     python main.py --diagnostico

Flujo:
  1. Se muestra la ventana de conexión.
  2. Si la conexión es exitosa, se abre la ventana principal.
  3. Si el usuario elige "Cerrar sesión", se vuelve a la ventana de conexión.
"""
import logging
import os
import sys
import traceback

from PyQt6.QtGui import QIcon
from PyQt6.QtWidgets import QApplication, QDialog, QMessageBox

from config import APP_NOMBRE
from db import BaseDeDatos
from estilos import configurar_aspecto
from recursos import carpeta_datos_usuario, ruta_recurso
from ventanas.login import DialogoLogin
from ventanas.principal import VentanaPrincipal

RUTA_LOG = os.path.join(carpeta_datos_usuario(), "soc_app.log")


def configurar_registro():
    """Los errores inesperados se guardan en un archivo (útil porque el .exe no tiene consola)."""
    logging.basicConfig(filename=RUTA_LOG, level=logging.INFO, encoding="utf-8",
                        format="%(asctime)s  %(levelname)s  %(message)s")


def manejar_excepcion(tipo, valor, tb):
    """Se llama ante cualquier error no controlado: lo registra y avisa al usuario con claridad."""
    detalle = "".join(traceback.format_exception(tipo, valor, tb))
    logging.error("Error no controlado:\n%s", detalle)
    if QApplication.instance() is not None:
        QMessageBox.critical(
            None, "Error inesperado",
            f"Ocurrió un error inesperado:\n\n{valor}\n\n"
            f"El detalle técnico se guardó en:\n{RUTA_LOG}")


def mostrar_diagnostico(con_ventana: bool):
    from diagnostico import generar_informe
    informe = generar_informe()
    print(informe)
    if con_ventana:
        QMessageBox.information(None, "Diagnóstico", informe)


def main():
    configurar_registro()
    sys.excepthook = manejar_excepcion

    if sys.platform == "win32":          # para que el icono aparezca en la barra de tareas de Windows
        import ctypes
        ctypes.windll.shell32.SetCurrentProcessExplicitAppUserModelID("soc.gestion.activos.app")

    app = QApplication(sys.argv)
    app.setApplicationName(APP_NOMBRE)
    app.setWindowIcon(QIcon(ruta_recurso("icono.png")))
    configurar_aspecto(app)              # colores claros fijos: se ve igual en modo claro u oscuro

    if "--diagnostico" in sys.argv:
        mostrar_diagnostico(con_ventana="--sin-ventana" not in sys.argv)
        return

    bd = BaseDeDatos()
    while True:
        login = DialogoLogin(bd)
        if login.exec() != QDialog.DialogCode.Accepted:
            break                        # el usuario canceló: salir de la aplicación

        ventana = VentanaPrincipal(bd)
        ventana.show()
        app.exec()                       # se queda aquí hasta que se cierre la ventana principal

        bd.cerrar()                      # siempre cerrar la conexión al terminar la sesión
        if not ventana.cerro_sesion:
            break                        # cerró con la X o con Salir: terminar
        # si cerró sesión, el bucle vuelve a mostrar la ventana de conexión

    bd.cerrar()


if __name__ == "__main__":
    main()
    sys.exit(0)
