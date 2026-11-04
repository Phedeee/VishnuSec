"""
exportar.py - Exportación de resultados a archivos CSV.

Formato elegido para que el archivo se abra correctamente con doble clic en
Excel de Windows configurado en español (Colombia):
  - Separador de columnas: punto y coma (;)   -> es el separador de lista de Excel en español
  - Decimales con coma (9,8)                   -> así los reconoce Excel como números
  - Codificación UTF-8 con BOM ('utf-8-sig')   -> Excel muestra bien tildes y ñ
"""
import csv
from datetime import date, datetime
from decimal import Decimal


def _a_texto(valor) -> str:
    """Convierte un valor de la base de datos al texto que se escribe en el CSV."""
    if valor is None:
        return ""
    if isinstance(valor, bool):
        return "Sí" if valor else "No"
    if isinstance(valor, (Decimal, float)):
        return format(valor, "f").replace(".", ",") if isinstance(valor, Decimal) \
            else repr(valor).replace(".", ",")
    if isinstance(valor, datetime):
        return valor.strftime("%Y-%m-%d %H:%M:%S")
    if isinstance(valor, date):
        return valor.strftime("%Y-%m-%d")
    return str(valor)


def guardar_csv(ruta: str, columnas, filas) -> int:
    """Escribe el CSV y devuelve la cantidad de filas guardadas."""
    with open(ruta, "w", newline="", encoding="utf-8-sig") as archivo:
        escritor = csv.writer(archivo, delimiter=";", quoting=csv.QUOTE_MINIMAL)
        escritor.writerow(columnas)
        for fila in filas:
            escritor.writerow([_a_texto(v) for v in fila])
    return len(filas)
