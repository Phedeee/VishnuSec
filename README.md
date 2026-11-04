# Proyecto SOC: Gestión de activos de red, incidentes y vulnerabilidades

Base de datos PostgreSQL para el centro de operaciones de seguridad (SOC) de una organización, con
scripts SQL, programación avanzada (PL/pgSQL) y una aplicación de escritorio en Python.

**Curso:** Bases de Datos I  ·  **Autor(es):** _(completar)_  ·  **Fecha:** _(completar)_

---

## 1. Contenido de la carpeta

```
proyecto_soc/
├── README.md                              Este archivo
├── 1_base_de_datos/
│   ├── 01_ddl_estructura.sql              Tablas y restricciones (CREATE TABLE, PK, FK, UNIQUE, CHECK)
│   ├── 02_dml_datos.sql                   Datos de ejemplo (30 a 40 registros por tabla)
│   ├── 03_consultas_negocio.sql           10 consultas de negocio
│   ├── 04_topicos_avanzados.sql           Procedimiento, triggers e índice (PL/pgSQL)
│   ├── 05_usuario_solo_lectura.sql        Usuario app_lectura (solo SELECT)
│   └── 06_usuario_gestion.sql             Usuario app_gestion (solo ejecuta el procedimiento)
├── 2_diagrama/
│   └── diagrama_fisico_modelo_relacional.png   Diagrama físico (tablas, campos, tipos, PK y FK)
└── 3_aplicacion/
    └── app_soc/                           Aplicación de escritorio (código fuente, Python + PyQt6)
```

La guía de sustentación (preguntas probables y guion de demostración) es un documento aparte.

## 2. Requisitos

- **PostgreSQL 16 o superior** con pgAdmin 4 (los scripts usan funciones de PostgreSQL 11 en adelante).
- **Python 3.10 o superior** (solo para ejecutar o empaquetar la aplicación).
- Windows 11 (la aplicación y el ejecutable se verificaron en este sistema).

## 3. Instalación paso a paso

### 3.1 Base de datos

1. En pgAdmin: clic derecho en *Databases* > *Create* > *Database* y cree la base **`soc_activos`**.
2. Abra el *Query Tool* de `soc_activos` y ejecute los scripts de `1_base_de_datos` **en este orden**
   (abrir archivo y pulsar F5):

   | Orden | Script | Qué hace |
   |---|---|---|
   | 1 | `01_ddl_estructura.sql` | Crea las 11 tablas y todas las restricciones |
   | 2 | `02_dml_datos.sql` | Carga 398 registros de ejemplo |
   | 3 | `03_consultas_negocio.sql` | _Opcional:_ ejecuta las 10 consultas de negocio |
   | 4 | `04_topicos_avanzados.sql` | Crea el procedimiento, los triggers y el índice, y ejecuta pruebas |
   | 5 | `05_usuario_solo_lectura.sql` | Crea el usuario `app_lectura` |
   | 6 | `06_usuario_gestion.sql` | Crea el usuario `app_gestion` |

3. **Cambie las contraseñas** que aparecen dentro de los scripts 05 y 06 antes de ejecutarlos
   (`CambieEstaClave_123` y `CambieEstaClaveGestion_123` son solo valores de ejemplo).

Notas:
- Todos los scripts se pueden ejecutar varias veces. El 01 borra y recrea las tablas; el 02 recarga los datos.
- Si ejecuta el 04 de nuevo, ejecute también el 06 (el 04 vuelve a crear el procedimiento sin el atributo
  de seguridad que le agrega el 06).
- El 03 y el 04 contienen varias consultas; pgAdmin muestra el resultado de la última. Para ver otra,
  selecciónela y ejecútela sola.

### 3.2 Aplicación de escritorio

```
cd 3_aplicacion\app_soc
python -m venv .venv
.venv\Scripts\activate.bat
pip install -r requirements.txt
python main.py
```

En la ventana de conexión escriba la contraseña de `app_lectura`; los demás datos ya vienen cargados
(`localhost`, puerto `5432`, base `soc_activos`). Se pueden cambiar en `config.ini`.

### 3.3 Ejecutable (.exe) opcional

Desde `3_aplicacion\app_soc` haga doble clic en `build_exe.bat`. El programa queda en
`dist\SOC_App\SOC_App.exe` (copie la carpeta `SOC_App` completa para llevarlo a otro equipo).
Más detalles y solución de problemas en `3_aplicacion\app_soc\README.md`.

## 4. Modelo de datos

El diagrama está en `2_diagrama/diagrama_fisico_modelo_relacional.png`.

| Tabla | Tipo | Registros | Descripción |
|---|---|---|---|
| `activos_red` | Maestra | 40 | Inventario de dispositivos (servidores, routers, equipos de usuario...) |
| `empleados` | Maestra | 40 | Personal; se inactiva en lugar de borrarse (estado, motivo y fecha de retiro) |
| `tipos_amenaza` | Maestra | 35 | Catálogo de amenazas con su nivel de riesgo |
| `analistas_soc` | Maestra | 32 | Analistas del SOC, con certificación y turno |
| `vulnerabilidades_conocidas` | Maestra | 35 | Catálogo de CVE reales con puntaje CVSS |
| `asignaciones_activos` | Relación N:M | 40 | Historial de responsables de cada activo |
| `incidentes` | Transaccional | 40 | Eventos de seguridad detectados |
| `mitigaciones` | Transaccional | 34 | Acciones que resuelven un incidente |
| `activo_vulnerabilidad` | Relación N:M | 40 | Vulnerabilidades de cada activo y su estado de parcheo |
| `auditoria` | Control | 30 | A qué empleado se reasignó un activo cuando otro se retiró |
| `inconsistencias` | Control | 32 | Registros rechazados y el motivo por el que no se dejaron incluir |

**Integridad:** PK en todas las tablas; FK con `ON UPDATE CASCADE` y `ON DELETE RESTRICT`; UNIQUE en IP,
correo, CVE, nombre de amenaza y en el par activo–vulnerabilidad; CHECK para listas de valores, rango
del CVSS (0 a 10), formato de correo y de CVE, y coherencia entre estado y fechas; y un índice único
parcial que impide dos asignaciones vigentes del mismo activo.

## 5. Consultas de negocio (script 03)

1. Incidentes por tipo de amenaza y tiempo de respuesta
2. Activos críticos con incidentes sin resolver
3. Exposición a vulnerabilidades por activo
4. Carga de trabajo del SOC por turno y certificación
5. Incidentes por departamento del responsable actual
6. Empleados activos sin equipo asignado
7. Reasignaciones por retiro de empleados (auditoría)
8. Top 10 activos de mayor riesgo combinado
9. Evolución trimestral de incidentes
10. Vulnerabilidades graves más extendidas

Usan INNER y LEFT JOIN, filtros avanzados, COUNT/SUM/AVG, GROUP BY con HAVING, subconsultas, CTE y
funciones de ventana. Cada una indica en comentarios la pregunta de negocio y las técnicas aplicadas.

## 6. Programación avanzada (script 04)

- **Procedimiento `sp_inactivar_empleado(id, motivo)`:** inactiva a un empleado, finaliza sus asignaciones
  y reasigna cada activo a otro empleado activo del mismo departamento (el de menos activos). Registra
  todo en `auditoria`; si no hay a quién reasignar, lo registra en `inconsistencias`. Es transaccional:
  si algo falla, se deshace todo.
- **Trigger `trg_validar_asignacion`:** valida que el empleado esté activo, que el activo no tenga ya un
  responsable vigente y que nadie supere 5 activos. Si falla, cancela el INSERT y guarda el motivo en
  `inconsistencias`.
- **Trigger `trg_mitigacion_valida_y_cierra`:** rechaza mitigaciones anteriores a la detección del
  incidente y marca el incidente como Resuelto cuando la mitigación es válida.
- **Índice `idx_incidentes_sin_resolver`:** B-Tree parcial que acelera la consulta de los últimos
  incidentes sin resolver. El script incluye una prueba con 500.000 filas y `EXPLAIN ANALYZE`
  antes y después.

## 7. Usuarios y seguridad

| Usuario | Permisos | Se usa en |
|---|---|---|
| `postgres` | Superusuario | Solo para instalar (ejecutar los scripts) |
| `app_lectura` | Solo SELECT; sesión de solo lectura | Todas las pestañas, excepto la inactivación |
| `app_gestion` | SELECT y ejecutar `sp_inactivar_empleado`; no puede modificar tablas | Solo para inactivar empleados |

La consulta libre de la aplicación tiene tres capas de protección: validación previa del texto,
transacción `READ ONLY` y permisos del usuario. Las contraseñas no se guardan en el código ni en
`config.ini`.

## 8. La aplicación de escritorio

Seis pestañas: **Resumen** de la base de datos, **Consultas de negocio** (las 10, con SQL visible y
exportación a CSV), **Consulta libre** (con explorador de estructura, ejemplos e historial),
**Gestión de empleados** (inactivar con vista previa de reasignación), **Auditoría** e **Inconsistencias**.

## 9. Restaurar los datos de ejemplo

Inactivar empleados desde la aplicación modifica los datos de verdad. Para volver al estado original
ejecute de nuevo `02_dml_datos.sql` (no toca los usuarios ni el procedimiento).

## 10. Pruebas realizadas

- Los 6 scripts se ejecutaron en orden sobre una base vacía, con PostgreSQL 16, tanto sentencia por
  sentencia (`psql`) como en un solo bloque (como lo hace pgAdmin).
- Las 10 consultas devuelven resultados; el procedimiento, los triggers y el índice se probaron con
  casos válidos e inválidos.
- Se verificaron los permisos: `app_lectura` y `app_gestion` no pueden modificar tablas directamente, y
  la consulta libre rechaza escrituras, incluso con intentos de evadir la protección.
- La aplicación y el ejecutable se verificaron en Windows 11.

## 11. Datos y alcance

Los empleados, equipos e incidentes son **ficticios**. Los códigos CVE son reales, pero sus puntajes CVSS
son aproximados. El proyecto es académico: no está pensado para operar con datos reales sin una revisión
adicional (por ejemplo, conexiones cifradas con SSL y copias de seguridad programadas).
