"""
config.py - Valores de configuración de la aplicación.

Los valores que aparecen PRECARGADOS en la ventana de conexión se leen, en este orden de
prioridad:
    1) variables de entorno (SOC_HOST, SOC_PUERTO, SOC_BASE, SOC_USUARIO, SOC_USUARIO_GESTION)
    2) el archivo config.ini que está junto al ejecutable (o junto a main.py)
    3) los valores por defecto escritos aquí

Así se puede cambiar el servidor o la base de datos editando config.ini con el Bloc de notas,
sin tener que volver a generar el ejecutable.

La contraseña nunca se guarda: la escribe el usuario cada vez que inicia sesión.
"""
import configparser
import os

from recursos import carpeta_aplicacion

APP_NOMBRE = "SOC - Gestión de Activos e Incidentes"
APP_VERSION = "1.0"

RUTA_CONFIG_INI = os.path.join(carpeta_aplicacion(), "config.ini")

_ini = configparser.ConfigParser(interpolation=None)
INI_ERROR = ""                             # si el config.ini está dañado, aquí queda el motivo
try:
    _ini.read(RUTA_CONFIG_INI, encoding="utf-8")
except (configparser.Error, OSError, UnicodeDecodeError) as _e:   # un config.ini dañado no debe impedir abrir la app
    _ini = configparser.ConfigParser(interpolation=None)
    INI_ERROR = str(_e).splitlines()[0]


def _leer(seccion: str, clave: str, variable_entorno: str, defecto: str) -> str:
    """Devuelve el valor según la prioridad: entorno > config.ini > defecto."""
    if os.environ.get(variable_entorno):
        return os.environ[variable_entorno]
    valor = _ini.get(seccion, clave, fallback="").strip()
    return valor if valor else defecto


def _entero(texto: str, defecto: int) -> int:
    try:
        return int(texto)
    except ValueError:
        return defecto


# Valores por defecto de la ventana de conexión
HOST_POR_DEFECTO = _leer("conexion", "host", "SOC_HOST", "localhost")
PUERTO_POR_DEFECTO = _entero(_leer("conexion", "puerto", "SOC_PUERTO", "5432"), 5432)
BASE_POR_DEFECTO = _leer("conexion", "base", "SOC_BASE", "soc_activos")
USUARIO_POR_DEFECTO = _leer("conexion", "usuario", "SOC_USUARIO", "app_lectura")
USUARIO_GESTION_POR_DEFECTO = _leer("conexion", "usuario_gestion", "SOC_USUARIO_GESTION", "app_gestion")

# Segundos máximos de espera al conectar (evita que la ventana se quede congelada)
TIEMPO_ESPERA_CONEXION = 5

# Tiempo máximo (en milisegundos) que puede tardar UNA consulta antes de que PostgreSQL la
# cancele. Protege contra consultas que nunca terminan.
TIEMPO_MAX_CONSULTA_MS = 1000 * _entero(
    _leer("opciones", "tiempo_maximo_consulta_segundos", "SOC_TIMEOUT_S", "30"), 30)

# Máximo de filas que muestra la consulta libre (evita llenar la pantalla/memoria con
# resultados enormes, por ejemplo un producto cartesiano sin condición)
LIMITE_FILAS_CONSULTA_LIBRE = _entero(
    _leer("opciones", "limite_filas_consulta_libre", "SOC_LIMITE_FILAS", "1000"), 1000)
