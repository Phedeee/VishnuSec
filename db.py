"""
db.py - Capa de acceso a PostgreSQL.

Toda la comunicación con la base de datos pasa por la clase BaseDeDatos.
Las ventanas (interfaz gráfica) NUNCA hablan directamente con PostgreSQL:
le piden los datos a esta clase. Ventajas:
  - Si cambia la forma de conectarse, solo se modifica este archivo.
  - Los errores técnicos se convierten en mensajes claros en español.
  - La conexión se abre en modo SOLO LECTURA (doble seguridad: además del
    usuario app_lectura, la propia sesión rechaza cualquier escritura).
"""
import psycopg                                  # controlador de PostgreSQL (versión 3)
from psycopg import sql                         # utilidades para construir SQL de forma segura
from psycopg.conninfo import make_conninfo

from config import TIEMPO_ESPERA_CONEXION, TIEMPO_MAX_CONSULTA_MS


class ErrorBD(Exception):
    """Error de base de datos con un mensaje ya listo para mostrar al usuario."""


class BaseDeDatos:
    def __init__(self):
        self._conn = None          # objeto de conexión de psycopg (None = desconectado)
        self.info = {}             # datos de la sesión (usuario, base, servidor...)
        self._solo_lectura = True  # False únicamente en la sesión de gestión (ver conectar)

    # ------------------------------------------------------------------
    # Estado de la conexión
    # ------------------------------------------------------------------
    @property
    def conectada(self) -> bool:
        return self._conn is not None and not self._conn.closed

    # ------------------------------------------------------------------
    # Conectar / cerrar
    # ------------------------------------------------------------------
    def conectar(self, host: str, puerto: int, base: str, usuario: str, clave: str,
                 solo_lectura: bool = True) -> None:
        """
        Abre la conexión. Lanza ErrorBD con un mensaje claro si algo falla.

        solo_lectura=True  (por defecto): la sesión rechaza cualquier escritura.
        solo_lectura=False: SOLO para la sesión de gestión (usuario app_gestion). Aun así,
        las consultas siguen corriendo en transacciones READ ONLY; lo único que escribe es
        el método inactivar_empleado(), que llama al procedimiento almacenado.
        """
        self.cerrar()
        self._solo_lectura = solo_lectura
        modo = "-c default_transaction_read_only=on " if solo_lectura else ""
        try:
            conninfo = make_conninfo(
                host=host, port=puerto, dbname=base, user=usuario, password=clave,
                connect_timeout=TIEMPO_ESPERA_CONEXION,
                client_encoding="UTF8",                          # tildes y ñ correctas
                # Sesión de solo lectura: PostgreSQL rechazará INSERT/UPDATE/DELETE/DDL.
                # statement_timeout cancela cualquier consulta que tarde demasiado.
                options=f"{modo}-c statement_timeout={TIEMPO_MAX_CONSULTA_MS}",
            )
            # autocommit=True: cada consulta se ejecuta sola, sin dejar transacciones abiertas
            self._conn = psycopg.connect(conninfo, autocommit=True)
        except UnicodeDecodeError as e:
            # Problema típico en Windows en español: el servidor devuelve el error con
            # una codificación que Python no puede leer. Casi siempre es contraseña o usuario mal.
            raise ErrorBD(
                "No se pudo conectar. Verifique el usuario y la contraseña, "
                "y que el servidor PostgreSQL esté en ejecución."
            ) from e
        except psycopg.Error as e:
            raise ErrorBD(self._traducir_error_conexion(e)) from e

        # Guardar datos de la sesión para mostrarlos en la interfaz
        _, filas = self.consultar(
            "SELECT current_user, current_database(), "
            "regexp_replace(version(), '^PostgreSQL ([0-9.]+).*', '\\1')"
        )
        usuario_bd, base_bd, version = filas[0]
        self.info = {"usuario": usuario_bd, "base": base_bd, "version": version,
                     "host": host, "puerto": puerto, "solo_lectura": solo_lectura}

    def cerrar(self) -> None:
        if self._conn is not None and not self._conn.closed:
            self._conn.close()
        self._conn = None
        self.info = {}

    # ------------------------------------------------------------------
    # Consultas
    # ------------------------------------------------------------------
    def consultar(self, consulta, parametros=None, limite=None):
        """
        Ejecuta una consulta y devuelve (columnas, filas).

        consulta   : texto SQL o un objeto sql.SQL(...)
        parametros : valores para los marcadores %s  (NUNCA pegar valores en el texto SQL:
                     usar parámetros evita la inyección SQL)
        limite     : máximo de filas a devolver (None = todas)
        """
        if not self.conectada:
            raise ErrorBD("No hay una conexión activa con la base de datos.")
        try:
            with self._conn.cursor() as cur:
                # Cada consulta se ejecuta dentro de una transacción READ ONLY. Es la barrera
                # más fuerte: aunque el texto intente cambiar los ajustes de la sesión
                # (por ejemplo con set_config), PostgreSQL NO permite pasar a lectura/escritura
                # dentro de una transacción de solo lectura que ya empezó.
                cur.execute("BEGIN READ ONLY")
                try:
                    cur.execute(consulta, parametros)
                    if cur.description is None:            # la sentencia no devuelve filas
                        return [], []
                    columnas = [c.name for c in cur.description]
                    filas = cur.fetchmany(limite) if limite else cur.fetchall()
                    return columnas, filas
                finally:
                    try:
                        cur.execute("ROLLBACK")             # siempre cerrar la transacción
                    except psycopg.Error:
                        pass
        except psycopg.errors.QueryCanceled as e:
            raise ErrorBD(
                f"La consulta fue cancelada: superó el tiempo máximo permitido "
                f"({TIEMPO_MAX_CONSULTA_MS // 1000} segundos) o se detuvo manualmente."
            ) from e
        except (psycopg.errors.ReadOnlySqlTransaction, psycopg.errors.ActiveSqlTransaction) as e:
            raise ErrorBD("Operación no permitida: la aplicación trabaja en modo SOLO LECTURA "
                          "y no puede modificar datos ni cambiar la configuración de la sesión.") from e
        except psycopg.errors.InsufficientPrivilege as e:
            raise ErrorBD("El usuario de la conexión no tiene permiso para esa operación. "
                          f"Detalle: {(e.diag.message_primary or str(e)).strip()}") from e
        except psycopg.Error as e:
            # diag.message_primary es el mensaje "limpio" del servidor
            mensaje = e.diag.message_primary or str(e)
            raise ErrorBD(mensaje.strip()) from e

    def inactivar_empleado(self, id_empleado: int, motivo: str) -> list:
        """
        Inactiva a un empleado llamando al procedimiento sp_inactivar_empleado.
        Es la ÚNICA operación de escritura de toda la aplicación, y solo funciona
        con la sesión de gestión (usuario app_gestion).

        Devuelve la lista de mensajes (NOTICE) que emite el procedimiento, por
        ejemplo el resumen "Activos reasignados: 2...". Si el procedimiento lanza un
        error, la transacción se deshace por completo y se lanza ErrorBD.
        """
        if not self.conectada:
            raise ErrorBD("No hay una conexión activa con la base de datos.")
        if self._solo_lectura:
            raise ErrorBD("Esta sesión es de solo lectura: para inactivar empleados inicie la sesión de gestión.")
        if motivo not in ("Renuncia", "Despido"):
            raise ErrorBD("Motivo inválido: debe ser Renuncia o Despido.")

        avisos = []
        manejador = lambda diag: avisos.append(diag.message_primary or "")   # recoge los RAISE NOTICE
        self._conn.add_notice_handler(manejador)
        try:
            # transaction(): hace BEGIN, y COMMIT si todo sale bien o ROLLBACK si hay error
            with self._conn.transaction():
                # Parámetros (%s): nunca se pegan los valores dentro del texto SQL
                self._conn.execute("CALL sp_inactivar_empleado(%s::int, %s::varchar)", (int(id_empleado), motivo))
        except psycopg.errors.QueryCanceled as e:
            raise ErrorBD("La operación fue cancelada por superar el tiempo máximo permitido.") from e
        except psycopg.errors.InsufficientPrivilege as e:
            raise ErrorBD("El usuario de gestión no tiene permiso para ejecutar el procedimiento. "
                          "Ejecute el script 06_usuario_gestion.sql.") from e
        except psycopg.Error as e:
            raise ErrorBD((e.diag.message_primary or str(e)).strip()) from e
        finally:
            self._conn.remove_notice_handler(manejador)
        return avisos

    def cancelar(self) -> None:
        """Pide a PostgreSQL que detenga la consulta en curso (si la hay)."""
        if self.conectada:
            try:
                self._conn.cancel()
            except psycopg.Error:
                pass

    def esquema(self):
        """
        Devuelve la estructura de las tablas: lista de
        (tabla, columna, tipo, acepta_nulos, es_pk, es_fk).
        Se usa pg_catalog porque information_schema oculta las claves (PK/FK)
        a los usuarios que solo tienen permiso SELECT.
        """
        _, filas = self.consultar("""
            SELECT c.relname, a.attname, format_type(a.atttypid, a.atttypmod),
                   NOT a.attnotnull,
                   EXISTS (SELECT 1 FROM pg_constraint k
                           WHERE k.conrelid = c.oid AND k.contype = 'p' AND a.attnum = ANY (k.conkey)),
                   EXISTS (SELECT 1 FROM pg_constraint k
                           WHERE k.conrelid = c.oid AND k.contype = 'f' AND a.attnum = ANY (k.conkey))
            FROM   pg_class c
            JOIN   pg_namespace n ON n.oid = c.relnamespace
            JOIN   pg_attribute a ON a.attrelid = c.oid
            WHERE  n.nspname = 'public' AND c.relkind = 'r'
              AND  a.attnum > 0 AND NOT a.attisdropped
            ORDER  BY c.relname, a.attnum
        """)
        return filas

    def resumen_tablas(self):
        """Lista las tablas del esquema 'public' con su cantidad de registros."""
        _, tablas = self.consultar(
            "SELECT table_name FROM information_schema.tables "
            "WHERE table_schema = 'public' AND table_type = 'BASE TABLE' "
            "ORDER BY table_name"
        )
        resultado = []
        for (nombre,) in tablas:
            # Los NOMBRES de tabla no se pueden pasar como parámetro (%s);
            # sql.Identifier los escapa de forma segura.
            _, filas = self.consultar(
                sql.SQL("SELECT COUNT(*) FROM {}").format(sql.Identifier(nombre))
            )
            resultado.append((nombre, filas[0][0]))
        return resultado

    # ------------------------------------------------------------------
    # Traducción de errores de conexión
    # ------------------------------------------------------------------
    @staticmethod
    def _traducir_error_conexion(e: Exception) -> str:
        texto = str(e).lower()
        if "autenticaci" in texto or "authentication" in texto or "password" in texto:
            return "Usuario o contraseña incorrectos."
        if ("database" in texto and "does not exist" in texto) or "no existe la base" in texto:
            return "La base de datos indicada no existe. Revise el nombre."
        if any(p in texto for p in ("refused", "rechaz", "timeout", "timed out",
                                    "could not translate", "resolve", "no route", "unreachable")):
            return ("No se pudo conectar al servidor. Verifique la dirección y el puerto, "
                    "y que el servicio PostgreSQL esté iniciado.")
        return "No se pudo conectar: " + str(e).strip()
