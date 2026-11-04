"""
validacion.py - Revisión del SQL que escribe el usuario en la "Consulta libre".

Esta revisión NO es la seguridad real (esa la dan el usuario app_lectura, que solo
tiene SELECT, y la transacción READ ONLY de db.py). Sirve para dar mensajes claros
ANTES de enviar el texto a la base de datos:
  - rechaza el texto vacío,
  - rechaza varias sentencias a la vez (se ejecuta una por una),
  - rechaza sentencias que no sean de lectura (INSERT, DELETE, DROP...).
"""
import re

PERMITIDAS = {"SELECT", "WITH", "EXPLAIN", "SHOW", "TABLE", "VALUES"}


def dividir_sentencias(texto: str) -> list:
    """
    Separa el texto por ';' respetando textos entre comillas simples ('a;b'),
    identificadores entre comillas dobles, comentarios (-- y /* */) y bloques $$ ... $$.
    Devuelve solo las sentencias que tienen código real (ignora las vacías o solo comentarios).
    """
    sentencias, actual, tiene_codigo = [], [], False
    i, n = 0, len(texto)

    def terminar():
        nonlocal actual, tiene_codigo
        if tiene_codigo:
            sentencias.append("".join(actual).strip())
        actual, tiene_codigo = [], False

    while i < n:
        c = texto[i]
        if c in ("'", '"'):                                   # texto o identificador entre comillas
            j = i + 1
            while j < n:
                if texto[j] == c:
                    if j + 1 < n and texto[j + 1] == c:       # comilla doblada = comilla literal
                        j += 2
                        continue
                    break
                j += 1
            actual.append(texto[i:j + 1]); tiene_codigo = True; i = j + 1
        elif texto.startswith("--", i):                       # comentario de línea
            j = texto.find("\n", i)
            j = n if j == -1 else j
            actual.append(texto[i:j]); i = j
        elif texto.startswith("/*", i):                       # comentario de bloque
            j = texto.find("*/", i + 2)
            j = n if j == -1 else j + 2
            actual.append(texto[i:j]); i = j
        elif c == "$" and re.match(r"\$[A-Za-z_]*\$", texto[i:]):   # bloque $$ ... $$
            etiqueta = re.match(r"\$[A-Za-z_]*\$", texto[i:]).group(0)
            j = texto.find(etiqueta, i + len(etiqueta))
            j = n if j == -1 else j + len(etiqueta)
            actual.append(texto[i:j]); tiene_codigo = True; i = j
        elif c == ";":
            terminar(); i += 1
        else:
            actual.append(c)
            if not c.isspace():
                tiene_codigo = True
            i += 1
    terminar()
    return sentencias


def primera_palabra(sentencia: str) -> str:
    """Primera palabra clave de la sentencia (ignorando comentarios, espacios y paréntesis)."""
    sin_comentarios = re.sub(r"--[^\n]*|/\*.*?\*/", " ", sentencia, flags=re.DOTALL)
    m = re.match(r"[\s(]*([A-Za-z]+)", sin_comentarios)
    return m.group(1).upper() if m else ""


def preparar(texto: str):
    """
    Revisa el texto escrito por el usuario.
    Devuelve (sentencia, None) si es válido, o (None, mensaje_de_error).
    """
    sentencias = dividir_sentencias(texto)
    if not sentencias:
        return None, "Escriba una consulta SELECT para ejecutar."
    if len(sentencias) > 1:
        return None, (f"Hay {len(sentencias)} sentencias en el editor. Se ejecuta una a la vez: "
                      "seleccione con el mouse la que desea ejecutar y pulse «Ejecutar».")
    sentencia = sentencias[0]
    palabra = primera_palabra(sentencia)
    if palabra not in PERMITIDAS:
        return None, ("Solo se permiten consultas de lectura (SELECT, WITH, EXPLAIN, SHOW, TABLE, VALUES). "
                      f"Su sentencia empieza por «{palabra or sentencia[:15]}».")
    return sentencia, None
