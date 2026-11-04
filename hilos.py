"""
ventanas/hilos.py - Ejecución de consultas en segundo plano.

Si una consulta tarda, ejecutarla en el hilo principal CONGELA la ventana (no se
puede mover ni cerrar). Por eso cada consulta se ejecuta en un hilo aparte (QThread)
y avisa al terminar mediante "señales" (signals) de Qt.
"""
import time

from PyQt6.QtCore import QThread, pyqtSignal

from db import BaseDeDatos, ErrorBD


class HiloConsulta(QThread):
    terminado = pyqtSignal(list, list, float)   # columnas, filas, segundos que tardó
    fallo = pyqtSignal(str)                     # mensaje de error

    def __init__(self, bd: BaseDeDatos, consulta, parametros=None, limite=None, parent=None):
        super().__init__(parent)
        self.bd = bd
        self.consulta = consulta
        self.parametros = parametros
        self.limite = limite

    def run(self):
        """Se ejecuta en el hilo secundario (no tocar widgets desde aquí)."""
        inicio = time.perf_counter()
        try:
            columnas, filas = self.bd.consultar(self.consulta, self.parametros, self.limite)
        except ErrorBD as e:
            self.fallo.emit(str(e))
            return
        except Exception as e:                  # cualquier otro error inesperado
            self.fallo.emit(f"Error inesperado: {e}")
            return
        self.terminado.emit(columnas, filas, time.perf_counter() - inicio)


class HiloTarea(QThread):
    """Ejecuta en segundo plano cualquier función (por ejemplo, inactivar un empleado)."""
    terminado = pyqtSignal(object)      # lo que devuelve la función
    fallo = pyqtSignal(str)

    def __init__(self, funcion, parent=None):
        super().__init__(parent)
        self.funcion = funcion

    def run(self):
        try:
            self.terminado.emit(self.funcion())
        except ErrorBD as e:
            self.fallo.emit(str(e))
        except Exception as e:
            self.fallo.emit(f"Error inesperado: {e}")
