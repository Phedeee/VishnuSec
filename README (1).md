# Aplicación SOC - Gestión de Activos e Incidentes (versión 1.0)

Aplicación de escritorio en Python (PyQt6) que se conecta a la base de datos
PostgreSQL del proyecto.

## Requisitos
- Windows 11 con **Python 3.10 o superior** (marcar "Add Python to PATH" al instalarlo)
- PostgreSQL con la base `soc_activos` cargada (scripts 01 a 06, en ese orden)

## Instalación (una sola vez)
Abra el Símbolo del sistema (`cmd`) y ejecute, dentro de la carpeta `app_soc`:

```
python -m venv .venv
.venv\Scripts\activate.bat
pip install -r requirements.txt
```

## Ejecución
```
.venv\Scripts\activate.bat
python main.py
```

Datos de conexión que aparecen precargados:

| Campo | Valor |
|---|---|
| Servidor | localhost |
| Puerto | 5432 |
| Base de datos | soc_activos |
| Usuario | app_lectura |
| Contraseña | la definida en `05_usuario_solo_lectura.sql` |

Para la pestaña *Gestión de empleados* se pide, la primera vez que se usa, la contraseña del usuario
`app_gestion` (definida en `06_usuario_gestion.sql`).

## Estructura del proyecto
```
app_soc/
├── main.py              Punto de entrada: login -> ventana principal
├── config.py            Lee la configuración (config.ini, variables de entorno, valores por defecto)
├── config.ini           Configuración editable: servidor, base de datos, límites
├── recursos.py          Rutas de archivos (funciona con Python y dentro del .exe)
├── diagnostico.py       Informe de diagnóstico (python main.py --diagnostico)
├── soc_app.spec         Receta de PyInstaller para generar el ejecutable
├── build_exe.bat        Genera el ejecutable en Windows con un doble clic
├── icono.png / icono.ico  Icono de la aplicación
├── db.py                Acceso a PostgreSQL (única capa que usa SQL)
├── consultas.py         Catálogo de las 10 consultas de negocio (mismo SQL del script 03)
├── validacion.py        Revisión del SQL escrito por el usuario (solo lectura, una sentencia)
├── exportar.py          Exportación de resultados a CSV
├── estilos.py           Aspecto visual (colores, botones, tablas)
├── requirements.txt     Dependencias
└── ventanas/
    ├── login.py             Ventana de conexión
    ├── principal.py         Ventana principal (pestañas)
    ├── panel_consultas.py   Pestaña "Consultas de negocio"
    ├── panel_libre.py       Pestaña "Consulta libre"
    ├── panel_gestion.py     Pestaña "Gestión de empleados" (inactivar y reasignar activos)
    ├── panel_registros.py   Pestañas "Auditoría" e "Inconsistencias"
    ├── dialogos.py          Diálogo compartido para exportar a CSV
    ├── hilos.py             Ejecuta las consultas en segundo plano (la ventana no se congela)
    └── widgets.py           Tabla de resultados y resaltado de SQL
```

## Uso de la pestaña "Consultas de negocio"
1. Elija una consulta en la lista de la izquierda: se muestra la pregunta que responde,
   las tablas, las técnicas de SQL y el código.
2. Pulse **Ejecutar consulta** (o haga doble clic sobre la consulta).
3. Haga clic en el encabezado de una columna para ordenar el resultado.
4. **Exportar a CSV...** guarda el resultado. El archivo usa `;` como separador, coma decimal
   y UTF-8, por lo que se abre con doble clic en Excel (configuración regional en español).
5. **Ocultar SQL** da más espacio a la tabla de resultados.

Cada consulta se cancela automáticamente si tarda más de 30 segundos.

## Uso de la pestaña "Consulta libre"
- Escriba una consulta de lectura (SELECT, WITH, EXPLAIN, SHOW) y pulse **Ctrl+Enter** o **F5**.
- Si selecciona una parte del texto con el mouse, solo se ejecuta esa parte.
- Solo se ejecuta **una sentencia a la vez**.
- A la izquierda está la estructura de la base de datos (tablas, columnas, tipos y claves
  PK/FK). Con doble clic se inserta el nombre en el editor.
- **Ejemplos de consultas...** carga consultas listas para probar; **Historial** recupera las
  últimas consultas de la sesión.
- Mientras una consulta corre, el botón cambia a **Detener consulta**.
- Se muestran como máximo 1.000 filas; si hay más, la app lo avisa (agregue filtros o LIMIT).

### Seguridad de la consulta libre (tres capas)
1. La app rechaza con un mensaje claro todo lo que no sea una consulta de lectura.
2. Cada consulta corre dentro de una transacción **READ ONLY** (PostgreSQL no permite salir de ella).
3. El usuario `app_lectura` solo tiene permiso SELECT en la base de datos.

## Problemas frecuentes
- **"No se pudo conectar al servidor"**: el servicio de PostgreSQL no está iniciado
  (Windows: `Servicios` > `postgresql-x64-18` > Iniciar) o el puerto es distinto de 5432.
- **"Usuario o contraseña incorrectos"**: revise la contraseña del usuario `app_lectura`.
  Se puede cambiar en pgAdmin con: `ALTER ROLE app_lectura PASSWORD 'nueva_clave';`
- **"La base de datos indicada no existe"**: el nombre debe coincidir con el creado en pgAdmin.
- **No deja activar el entorno (PowerShell)**: use `cmd` en vez de PowerShell, o ejecute
  `Set-ExecutionPolicy -Scope Process Bypass` y vuelva a intentar.
- **`pip` no se reconoce**: Python no se agregó al PATH; reinstálelo marcando esa casilla.

## Uso de la pestaña "Gestión de empleados"
1. Busque o filtre la lista (por texto, estado o departamento) y seleccione un empleado.
2. Si está **activo**, la parte inferior muestra sus activos y a quién pasaría cada uno
   (vista previa). Si está **inactivo**, muestra el historial de activos que tenía.
3. Elija el motivo (Renuncia o Despido) y pulse **Inactivar empleado...**
4. La primera vez se pide la contraseña del usuario `app_gestion`; luego se confirma la acción.
5. El procedimiento `sp_inactivar_empleado` inactiva al empleado, reasigna sus activos y registra
   todo en **Auditoría**. Si no hay a quién reasignar, queda constancia en **Inconsistencias**.
6. Las pestañas Auditoría, Inconsistencias y Resumen se actualizan solas.

### Seguridad de la gestión
- Las demás pestañas siguen usando el usuario de solo lectura (`app_lectura`).
- `app_gestion` **no puede modificar tablas**: solo puede leer y ejecutar el procedimiento
  `sp_inactivar_empleado` (declarado SECURITY DEFINER, ver `06_usuario_gestion.sql`).
- Si el procedimiento falla, se deshace todo (el empleado no queda inactivado a medias).

## Generar el ejecutable (.exe) en Windows
El ejecutable debe generarse **en Windows** (PyInstaller construye para el sistema donde corre).

1. Abra la carpeta `app_soc` y haga doble clic en **`build_exe.bat`** (o ejecute `.\build_exe.bat`
   desde PowerShell). La primera vez descarga las dependencias y tarda unos minutos.
2. Al terminar, el programa queda en **`dist\SOC_App\SOC_App.exe`**. También se crea `dist\SOC_App.zip`.
3. Para usarlo en otro computador copie **toda la carpeta** `SOC_App` (o descomprima el `.zip`); el
   `.exe` solo no funciona porque necesita los archivos de la carpeta `_internal`.
4. Para cambiar el servidor o la base de datos edite `SOC_App\config.ini` con el Bloc de notas
   (no hace falta volver a generar el ejecutable).

Tamaño aproximado: entre 150 y 250 MB (incluye Python, Qt y el controlador de PostgreSQL).

### Si algo falla con el ejecutable
- **Diagnóstico:** desde PowerShell, dentro de la carpeta `SOC_App`, ejecute `.\SOC_App.exe --diagnostico`.
  Muestra las versiones, el `config.ini` que se está usando y los pasos de la conexión.
  Para probar también la conexión: `$env:SOC_CLAVE="su_contraseña"; .\SOC_App.exe --diagnostico`.
- **Registro de errores:** los errores inesperados se guardan en
  `%LOCALAPPDATA%\SOC_App\soc_app.log` (péguelo en la consulta si necesita ayuda).
- **Windows muestra "Windows protegió su PC" (SmartScreen):** ocurre con cualquier programa sin firma
  digital. Pulse *Más información* > *Ejecutar de todas formas*.
- **El antivirus lo bloquea o lo borra:** agregue la carpeta `SOC_App` a las excepciones. Es un
  falso positivo frecuente en ejecutables creados con PyInstaller.
- **Error por una DLL (por ejemplo `VCRUNTIME140.dll` o `MSVCP140.dll`):** instale el paquete
  "Microsoft Visual C++ Redistributable 2015-2022" (x64) desde el sitio de Microsoft.
- **Otro computador no logra conectarse:** el servidor PostgreSQL debe aceptar conexiones remotas
  (`listen_addresses` en `postgresql.conf`, una línea para esa red en `pg_hba.conf`, el puerto
  5432 abierto en el firewall) y `host` en `config.ini` debe ser la IP del servidor, no `localhost`.
