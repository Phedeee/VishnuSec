"""
diagnostico.py - Informe para detectar por qué una instalación no funciona.

Se ejecuta con:   SOC_App.exe --diagnostico
Muestra las versiones de las bibliotecas, la configuración que se está usando y, si se define
la variable de entorno SOC_CLAVE, prueba la conexión a la base de datos.
"""
import os
import platform
import sys

import config
from recursos import carpeta_datos_usuario, esta_empaquetada


def generar_informe() -> str:
    lineas = [f"{config.APP_NOMBRE}  -  versión {config.APP_VERSION}", "-" * 60]
    lineas.append(f"Modo: {'ejecutable (.exe)' if esta_empaquetada() else 'Python (código fuente)'}")
    lineas.append(f"Python: {platform.python_version()}  |  Sistema: {platform.platform()}")

    try:
        from PyQt6.QtCore import PYQT_VERSION_STR, QT_VERSION_STR
        lineas.append(f"PyQt6: {PYQT_VERSION_STR}  |  Qt: {QT_VERSION_STR}")
    except Exception as e:                                   # noqa: BLE001
        lineas.append(f"PyQt6: ERROR al cargar ({e})")

    try:
        import psycopg
        lineas.append(f"psycopg: {psycopg.__version__}  |  implementación: {psycopg.pq.__impl__}  |  "
                      f"libpq: {psycopg.pq.version()}")
    except Exception as e:                                   # noqa: BLE001
        lineas.append(f"psycopg: ERROR al cargar ({e})")

    lineas.append("-" * 60)
    existe = "existe" if os.path.exists(config.RUTA_CONFIG_INI) else "NO existe (se usan valores por defecto)"
    lineas.append(f"Archivo de configuración: {config.RUTA_CONFIG_INI}  ->  {existe}")
    if config.INI_ERROR:
        lineas.append(f"  AVISO: el archivo config.ini tiene errores y se ignoró ({config.INI_ERROR}). "
                      "Se usan los valores por defecto.")
    lineas.append(f"Servidor: {config.HOST_POR_DEFECTO}:{config.PUERTO_POR_DEFECTO}  |  "
                  f"base: {config.BASE_POR_DEFECTO}  |  usuario: {config.USUARIO_POR_DEFECTO}")
    lineas.append(f"Tiempo máximo por consulta: {config.TIEMPO_MAX_CONSULTA_MS // 1000} s  |  "
                  f"límite de filas (consulta libre): {config.LIMITE_FILAS_CONSULTA_LIBRE}")
    lineas.append(f"Registro de errores: {os.path.join(carpeta_datos_usuario(), 'soc_app.log')}")

    clave = os.environ.get("SOC_CLAVE")
    lineas.append("-" * 60)
    if not clave:
        lineas.append("Prueba de conexión: omitida (defina la variable de entorno SOC_CLAVE con la "
                      "contraseña para probarla).")
    else:
        from db import BaseDeDatos, ErrorBD
        bd = BaseDeDatos()
        try:
            bd.conectar(config.HOST_POR_DEFECTO, config.PUERTO_POR_DEFECTO, config.BASE_POR_DEFECTO,
                        config.USUARIO_POR_DEFECTO, clave)
            lineas.append(f"Prueba de conexión: CORRECTA  (PostgreSQL {bd.info['version']}, "
                          f"usuario {bd.info['usuario']}, base {bd.info['base']})")
            lineas.append(f"Tablas visibles: {len(bd.resumen_tablas())}")
        except ErrorBD as e:
            lineas.append(f"Prueba de conexión: FALLÓ -> {e}")
        finally:
            bd.cerrar()
    return "\n".join(lineas)
