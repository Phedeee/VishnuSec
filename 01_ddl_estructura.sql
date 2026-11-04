/* =====================================================================
   SCRIPT 1 - ESTRUCTURA (DDL)
   Proyecto : Gestión de activos de red, incidentes y vulnerabilidades (SOC)
   Motor    : PostgreSQL 12 o superior
   Contenido: CREATE TABLE de las 11 tablas + todas las restricciones de
              integridad (PK, FK, UNIQUE, NOT NULL, CHECK) + índices únicos.

   CÓMO EJECUTARLO:
     psql -U postgres -d su_base_de_datos -f 01_ddl_estructura.sql

   ORDEN DE LOS SCRIPTS:
     01_ddl_estructura.sql   -> crea las tablas   (este archivo)
     02_dml_datos.sql        -> carga los datos
     03_consultas_negocio.sql-> 10 consultas de negocio
     04_topicos_avanzados.sql-> procedimiento, trigger e índice
   ===================================================================== */

SET client_encoding = 'UTF8';

/* ---------------------------------------------------------------------
   0. LIMPIEZA (permite volver a ejecutar el script desde cero)
      DROP ... CASCADE elimina la tabla y las FK que dependen de ella.
      Se borran primero las tablas hijas y al final las maestras.
   --------------------------------------------------------------------- */
DROP TABLE IF EXISTS inconsistencias              CASCADE;
DROP TABLE IF EXISTS auditoria                    CASCADE;
DROP TABLE IF EXISTS activo_vulnerabilidad        CASCADE;
DROP TABLE IF EXISTS mitigaciones                 CASCADE;
DROP TABLE IF EXISTS incidentes                   CASCADE;
DROP TABLE IF EXISTS asignaciones_activos         CASCADE;
DROP TABLE IF EXISTS vulnerabilidades_conocidas   CASCADE;
DROP TABLE IF EXISTS analistas_soc                CASCADE;
DROP TABLE IF EXISTS tipos_amenaza                CASCADE;
DROP TABLE IF EXISTS empleados                    CASCADE;
DROP TABLE IF EXISTS activos_red                  CASCADE;

/* =====================================================================
   1. TABLAS MAESTRAS (no dependen de otras tablas)
   ===================================================================== */

/* ---------- 1.1 activos_red: inventario de dispositivos de red ------- */
CREATE TABLE activos_red (
    id_activo         SERIAL        PRIMARY KEY,            -- identificador autonumérico
    direccion_ip      VARCHAR(45)   NOT NULL,               -- 45 caracteres alcanzan para IPv6
    nombre_host       VARCHAR(100)  NOT NULL,
    tipo_dispositivo  VARCHAR(50)   NOT NULL,               -- Servidor, Router, Workstation...
    criticidad        VARCHAR(20)   NOT NULL,

    -- Dos activos no pueden compartir la misma IP
    CONSTRAINT uq_activos_ip        UNIQUE (direccion_ip),
    -- Solo caracteres válidos en una IPv4/IPv6 (dígitos, hex, ':' y '.')
    CONSTRAINT ck_activos_ip_formato CHECK (direccion_ip ~ '^[0-9A-Fa-f:.]+$'),
    -- La criticidad solo admite estos tres valores
    CONSTRAINT ck_activos_criticidad CHECK (criticidad IN ('Alta', 'Media', 'Baja'))
);

/* ---------- 1.2 empleados: personal de la organización --------------- */
CREATE TABLE empleados (
    id_empleado    SERIAL        PRIMARY KEY,
    nombre         VARCHAR(100)  NOT NULL,
    correo         VARCHAR(150)  NOT NULL,
    departamento   VARCHAR(50)   NOT NULL,
    -- Campos agregados por la sugerencia del profesor (inactivación de empleados):
    estado         VARCHAR(20)   NOT NULL DEFAULT 'Activo',
    motivo_retiro  VARCHAR(30),                              -- NULL mientras esté activo
    fecha_retiro   TIMESTAMP,                                -- NULL mientras esté activo

    CONSTRAINT uq_empleados_correo UNIQUE (correo),
    -- Formato básico de correo: algo@dominio.ext
    CONSTRAINT ck_empleados_correo CHECK (correo ~* '^[^@[:space:]]+@[^@[:space:]]+\.[^@[:space:]]+$'),
    CONSTRAINT ck_empleados_estado CHECK (estado IN ('Activo', 'Inactivo')),
    CONSTRAINT ck_empleados_motivo CHECK (motivo_retiro IS NULL OR motivo_retiro IN ('Renuncia', 'Despido')),
    -- Coherencia entre estado y datos de retiro:
    --   Activo   -> motivo y fecha de retiro deben estar vacíos
    --   Inactivo -> motivo y fecha de retiro son obligatorios
    CONSTRAINT ck_empleados_retiro CHECK (
        (estado = 'Activo'   AND motivo_retiro IS NULL     AND fecha_retiro IS NULL)
     OR (estado = 'Inactivo' AND motivo_retiro IS NOT NULL AND fecha_retiro IS NOT NULL)
    )
);

/* ---------- 1.3 tipos_amenaza: catálogo de amenazas ------------------ */
CREATE TABLE tipos_amenaza (
    id_amenaza      SERIAL        PRIMARY KEY,
    nombre_amenaza  VARCHAR(100)  NOT NULL,
    nivel_riesgo    VARCHAR(20)   NOT NULL,
    descripcion     TEXT,                                    -- opcional

    CONSTRAINT uq_amenaza_nombre UNIQUE (nombre_amenaza),
    CONSTRAINT ck_amenaza_nivel  CHECK (nivel_riesgo IN ('Crítico', 'Alto', 'Moderado'))
);

/* ---------- 1.4 analistas_soc: equipo del centro de operaciones ------ */
CREATE TABLE analistas_soc (
    id_analista          SERIAL        PRIMARY KEY,
    nombre               VARCHAR(100)  NOT NULL,
    nivel_certificacion  VARCHAR(50)   NOT NULL,
    turno                VARCHAR(20)   NOT NULL,

    CONSTRAINT ck_analista_cert  CHECK (nivel_certificacion IN ('Junior', 'Senior', 'CISSP')),
    CONSTRAINT ck_analista_turno CHECK (turno IN ('Mañana', 'Tarde', 'Noche'))
);

/* ---------- 1.5 vulnerabilidades_conocidas: catálogo de CVEs --------- */
CREATE TABLE vulnerabilidades_conocidas (
    id_vulnerabilidad   SERIAL         PRIMARY KEY,
    cve_code            VARCHAR(20)    NOT NULL,
    descripcion_tecnica TEXT           NOT NULL,
    puntaje_cvss        DECIMAL(3,1)   NOT NULL,             -- ej: 9.8

    CONSTRAINT uq_vuln_cve   UNIQUE (cve_code),
    -- Formato oficial: CVE-AAAA-NNNN (4 o más dígitos al final)
    CONSTRAINT ck_vuln_cve   CHECK (cve_code ~ '^CVE-[0-9]{4}-[0-9]{4,}$'),
    -- La escala CVSS va de 0.0 a 10.0
    CONSTRAINT ck_vuln_cvss  CHECK (puntaje_cvss BETWEEN 0.0 AND 10.0)
);

/* =====================================================================
   2. TABLAS DE RELACIÓN Y TRANSACCIONALES
   ===================================================================== */

/* ---------- 2.1 asignaciones_activos: N:M activos <-> empleados ------ */
CREATE TABLE asignaciones_activos (
    id_asignacion     SERIAL       PRIMARY KEY,
    activo_id         INT          NOT NULL,
    empleado_id       INT          NOT NULL,
    fecha_asignacion  DATE         NOT NULL,
    fecha_fin         DATE,                                  -- NULL mientras siga vigente
    estado            VARCHAR(20)  NOT NULL DEFAULT 'Vigente',

    CONSTRAINT fk_asig_activo   FOREIGN KEY (activo_id)   REFERENCES activos_red(id_activo)
                                ON UPDATE CASCADE ON DELETE RESTRICT,
    CONSTRAINT fk_asig_empleado FOREIGN KEY (empleado_id) REFERENCES empleados(id_empleado)
                                ON UPDATE CASCADE ON DELETE RESTRICT,
    CONSTRAINT ck_asig_estado   CHECK (estado IN ('Vigente', 'Finalizada')),
    -- La fecha de fin no puede ser anterior al inicio
    CONSTRAINT ck_asig_fechas   CHECK (fecha_fin IS NULL OR fecha_fin >= fecha_asignacion),
    -- Vigente -> sin fecha_fin ; Finalizada -> con fecha_fin
    CONSTRAINT ck_asig_coherencia CHECK (
        (estado = 'Vigente'    AND fecha_fin IS NULL)
     OR (estado = 'Finalizada' AND fecha_fin IS NOT NULL)
    )
);
-- Regla de negocio: un activo solo puede tener UNA asignación vigente a la vez.
-- Un UNIQUE normal no sirve (impediría el historial), por eso se usa un
-- índice único PARCIAL: solo vigila las filas con estado = 'Vigente'.
CREATE UNIQUE INDEX uq_asig_activo_vigente
    ON asignaciones_activos (activo_id)
    WHERE estado = 'Vigente';

/* ---------- 2.2 incidentes: eventos de seguridad detectados ---------- */
CREATE TABLE incidentes (
    id_incidente     SERIAL       PRIMARY KEY,
    activo_id        INT          NOT NULL,
    tipo_amenaza_id  INT          NOT NULL,
    fecha_deteccion  TIMESTAMP    NOT NULL,
    estado           VARCHAR(30)  NOT NULL DEFAULT 'Abierto',

    CONSTRAINT fk_inc_activo   FOREIGN KEY (activo_id)       REFERENCES activos_red(id_activo)
                               ON UPDATE CASCADE ON DELETE RESTRICT,
    CONSTRAINT fk_inc_amenaza  FOREIGN KEY (tipo_amenaza_id) REFERENCES tipos_amenaza(id_amenaza)
                               ON UPDATE CASCADE ON DELETE RESTRICT,
    CONSTRAINT ck_inc_estado   CHECK (estado IN ('Abierto', 'En Investigación', 'Resuelto'))
);

/* ---------- 2.3 mitigaciones: acciones que resuelven un incidente ---- */
CREATE TABLE mitigaciones (
    id_mitigacion    SERIAL     PRIMARY KEY,
    incidente_id     INT        NOT NULL,
    analista_soc_id  INT        NOT NULL,
    acciones_tomadas TEXT       NOT NULL,
    fecha_resolucion TIMESTAMP  NOT NULL,

    CONSTRAINT fk_mit_incidente FOREIGN KEY (incidente_id)    REFERENCES incidentes(id_incidente)
                                ON UPDATE CASCADE ON DELETE RESTRICT,
    CONSTRAINT fk_mit_analista  FOREIGN KEY (analista_soc_id) REFERENCES analistas_soc(id_analista)
                                ON UPDATE CASCADE ON DELETE RESTRICT,
    -- No se admiten acciones vacías o solo espacios
    CONSTRAINT ck_mit_acciones  CHECK (LENGTH(TRIM(acciones_tomadas)) > 0)
);

/* ---------- 2.4 activo_vulnerabilidad: N:M activos <-> CVEs ---------- */
CREATE TABLE activo_vulnerabilidad (
    id_activovuln     SERIAL       PRIMARY KEY,
    activo_id         INT          NOT NULL,
    vulnerabilidad_id INT          NOT NULL,
    estado_parcheo    VARCHAR(30)  NOT NULL DEFAULT 'Pendiente',

    CONSTRAINT fk_av_activo FOREIGN KEY (activo_id)         REFERENCES activos_red(id_activo)
                            ON UPDATE CASCADE ON DELETE RESTRICT,
    CONSTRAINT fk_av_vuln   FOREIGN KEY (vulnerabilidad_id) REFERENCES vulnerabilidades_conocidas(id_vulnerabilidad)
                            ON UPDATE CASCADE ON DELETE RESTRICT,
    CONSTRAINT ck_av_estado CHECK (estado_parcheo IN ('Parcheado', 'Pendiente', 'Mitigado')),
    -- La misma vulnerabilidad no se registra dos veces sobre el mismo activo
    CONSTRAINT uq_av_par    UNIQUE (activo_id, vulnerabilidad_id)
);

/* =====================================================================
   3. TABLAS DE CONTROL (sugerencias del profesor)
   ===================================================================== */

/* ---------- 3.1 auditoria: reasignaciones por retiro de empleados ---- */
-- Cada fila responde: "¿A qué empleado se le asignó el activo X cuando el
-- empleado Y fue despedido o renunció?"
CREATE TABLE auditoria (
    id_auditoria          SERIAL       PRIMARY KEY,
    activo_id             INT          NOT NULL,
    empleado_anterior_id  INT          NOT NULL,             -- quien se retiró
    empleado_nuevo_id     INT          NOT NULL,             -- quien recibe el activo
    motivo                VARCHAR(30)  NOT NULL,
    fecha_reasignacion    TIMESTAMP    NOT NULL DEFAULT NOW(),

    CONSTRAINT fk_aud_activo   FOREIGN KEY (activo_id)            REFERENCES activos_red(id_activo)
                               ON UPDATE CASCADE ON DELETE RESTRICT,
    CONSTRAINT fk_aud_anterior FOREIGN KEY (empleado_anterior_id) REFERENCES empleados(id_empleado)
                               ON UPDATE CASCADE ON DELETE RESTRICT,
    CONSTRAINT fk_aud_nuevo    FOREIGN KEY (empleado_nuevo_id)    REFERENCES empleados(id_empleado)
                               ON UPDATE CASCADE ON DELETE RESTRICT,
    CONSTRAINT ck_aud_motivo   CHECK (motivo IN ('Renuncia', 'Despido')),
    -- El activo debe pasar a un empleado DIFERENTE del que se retira
    CONSTRAINT ck_aud_distintos CHECK (empleado_anterior_id <> empleado_nuevo_id)
);

/* ---------- 3.2 inconsistencias: bitácora de registros rechazados ---- */
-- Sin FK a propósito: es una bitácora genérica que puede referirse a
-- cualquier tabla (incluso a registros que nunca llegaron a existir).
CREATE TABLE inconsistencias (
    id_inconsistencia  SERIAL       PRIMARY KEY,
    tabla_origen       VARCHAR(50)  NOT NULL,                -- tabla donde se intentó la operación
    operacion          VARCHAR(10)  NOT NULL,
    registro_id        INT,                                  -- NULL si el registro no llegó a crearse
    datos_rechazados   TEXT,                                 -- copia legible de los datos enviados
    motivo             TEXT         NOT NULL,                -- por qué no se dejó incluir
    fecha_registro     TIMESTAMP    NOT NULL DEFAULT NOW(),

    CONSTRAINT ck_inco_operacion CHECK (operacion IN ('INSERT', 'UPDATE', 'DELETE')),
    CONSTRAINT ck_inco_motivo    CHECK (LENGTH(TRIM(motivo)) > 0)
);

/* =====================================================================
   4. VERIFICACIÓN RÁPIDA
   ===================================================================== */
-- Debe listar las 11 tablas creadas
SELECT table_name
FROM   information_schema.tables
WHERE  table_schema = 'public' AND table_type = 'BASE TABLE'
ORDER  BY table_name;
