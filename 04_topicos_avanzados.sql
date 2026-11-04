/* =====================================================================
   SCRIPT 4 - TÓPICOS AVANZADOS (PL/pgSQL)  -  HITO 2
   Contenido:
     PARTE 1. TRIGGER   : valida reglas de negocio al asignar un activo
     PARTE 2. PROCEDIMIENTO ALMACENADO : inactiva un empleado y reasigna
                          sus activos de forma automática y transaccional
     PARTE 3. TRIGGER ADICIONAL (opcional) : valida y cierra incidentes
     PARTE 4. OPTIMIZACIÓN : índice B-Tree parcial + prueba con EXPLAIN
   Ejecutar DESPUÉS de los scripts 01, 02 y 03.

     psql -U postgres -d su_base_de_datos -f 04_topicos_avanzados.sql

   CONCEPTOS BÁSICOS (para entender el código)
   - PL/pgSQL es el lenguaje procedural de PostgreSQL: permite usar
     variables, IF, LOOP y manejo de errores dentro de la base de datos.
   - Función de trigger: función especial que se dispara sola cuando ocurre
     un INSERT/UPDATE/DELETE. Dentro de ella:
         NEW = la fila que se está insertando/modificando
         OLD = la fila como estaba antes (en UPDATE/DELETE)
         RETURN NEW  -> deja continuar la operación
         RETURN NULL -> CANCELA la operación en silencio (solo en BEFORE)
   - Procedimiento (PROCEDURE): rutina que se invoca con CALL. Todo lo que
     hace ocurre en UNA sola transacción: si algo falla, se deshace todo.
   ===================================================================== */

SET client_encoding = 'UTF8';

/* Las PARTES 1 a 4 (crear funciones, triggers, procedimiento e índices) se
   ejecutan dentro de una transacción explícita que se confirma con COMMIT
   antes de las pruebas de la PARTE 5. Esto es necesario porque pgAdmin envía
   el script completo como un solo bloque: sin este COMMIT, el primer ROLLBACK
   de las pruebas también desharía la creación del procedimiento y los triggers. */
BEGIN;


/* =====================================================================
   PARTE 1. TRIGGER DE VALIDACIÓN  -  trg_validar_asignacion
   ---------------------------------------------------------------------
   Regla de negocio compleja: antes de guardar una asignación VIGENTE se
   comprueba que:
     1) el empleado exista y esté Activo,
     2) el activo no tenga ya otra asignación Vigente,
     3) el empleado no supere el máximo de 5 activos vigentes.
   Si alguna regla falla, la asignación NO se guarda y el motivo queda
   registrado automáticamente en la tabla 'inconsistencias'
   (responde a: "¿por qué no se dejó incluir?").
   ===================================================================== */
CREATE OR REPLACE FUNCTION fn_validar_asignacion()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
DECLARE
    c_max_activos   CONSTANT INT := 5;     -- límite de activos por empleado
    v_estado_emp    VARCHAR(20);           -- estado del empleado
    v_ocupado       INT;                   -- cuántas asignaciones vigentes tiene el activo
    v_vigentes_emp  INT;                   -- cuántos activos vigentes tiene el empleado
    v_motivo        TEXT := NULL;          -- si queda con texto, la asignación se rechaza
BEGIN
    -- Las filas históricas (Finalizada) no se validan: solo las Vigentes
    IF NEW.estado = 'Vigente' THEN

        -- Regla 1: el empleado debe existir y estar Activo
        SELECT estado INTO v_estado_emp
        FROM   empleados
        WHERE  id_empleado = NEW.empleado_id;

        IF NOT FOUND THEN
            v_motivo := format('El empleado %s no existe.', NEW.empleado_id);
        ELSIF v_estado_emp <> 'Activo' THEN
            v_motivo := format('El empleado %s está Inactivo; solo se pueden asignar activos vigentes a empleados Activos.',
                               NEW.empleado_id);
        ELSE
            -- Regla 2: el activo no puede tener otra asignación vigente
            SELECT COUNT(*) INTO v_ocupado
            FROM   asignaciones_activos
            WHERE  activo_id = NEW.activo_id AND estado = 'Vigente';

            IF v_ocupado > 0 THEN
                v_motivo := format('El activo %s ya tiene una asignación Vigente; primero debe finalizarse la anterior.',
                                   NEW.activo_id);
            ELSE
                -- Regla 3: límite de activos por empleado
                SELECT COUNT(*) INTO v_vigentes_emp
                FROM   asignaciones_activos
                WHERE  empleado_id = NEW.empleado_id AND estado = 'Vigente';

                IF v_vigentes_emp >= c_max_activos THEN
                    v_motivo := format('El empleado %s ya tiene %s activos vigentes (máximo permitido: %s).',
                                       NEW.empleado_id, v_vigentes_emp, c_max_activos);
                END IF;
            END IF;
        END IF;
    END IF;

    -- Si alguna regla falló: registrar en 'inconsistencias' y cancelar el INSERT
    IF v_motivo IS NOT NULL THEN
        INSERT INTO inconsistencias (tabla_origen, operacion, registro_id, datos_rechazados, motivo, fecha_registro)
        VALUES ('asignaciones_activos', 'INSERT', NULL,
                format('activo_id=%s, empleado_id=%s, fecha_asignacion=%s, estado=%s',
                       NEW.activo_id, NEW.empleado_id, NEW.fecha_asignacion, NEW.estado),
                v_motivo, NOW());
        RAISE NOTICE 'Asignación rechazada: %', v_motivo;
        RETURN NULL;       -- cancela el INSERT (la fila NO se guarda)
    END IF;

    RETURN NEW;            -- todo correcto: el INSERT continúa
END;
$$;

-- BEFORE INSERT: se ejecuta ANTES de guardar cada fila (FOR EACH ROW)
DROP TRIGGER IF EXISTS trg_validar_asignacion ON asignaciones_activos;
CREATE TRIGGER trg_validar_asignacion
    BEFORE INSERT ON asignaciones_activos
    FOR EACH ROW
    EXECUTE FUNCTION fn_validar_asignacion();


/* =====================================================================
   PARTE 2. PROCEDIMIENTO ALMACENADO  -  sp_inactivar_empleado
   ---------------------------------------------------------------------
   Automatiza un proceso transaccional completo: cuando un empleado
   renuncia o es despedido:
     1) valida los datos y lo marca como Inactivo (con motivo y fecha),
     2) finaliza todas sus asignaciones vigentes,
     3) reasigna cada activo a OTRO empleado Activo del mismo departamento
        (el que tenga menos activos vigentes),
     4) registra cada reasignación en 'auditoria',
     5) si no hay a quién reasignar, lo registra en 'inconsistencias'.
   Todo ocurre en una sola transacción: si ocurre un error, se deshace
   absolutamente todo (el empleado no queda inactivo a medias).
   ===================================================================== */
CREATE OR REPLACE PROCEDURE sp_inactivar_empleado(
    p_empleado_id  INT,
    p_motivo       VARCHAR
)
LANGUAGE plpgsql
AS $$
DECLARE
    v_emp          empleados%ROWTYPE;   -- fila completa del empleado
    v_asig         RECORD;              -- cada asignación vigente (variable del bucle)
    v_nuevo_id     INT;                 -- empleado que recibe el activo
    v_filas        INT;                 -- filas insertadas (0 si el trigger rechazó)
    v_reasignados  INT := 0;
    v_sin_reemplazo INT := 0;
BEGIN
    -- 1. VALIDACIONES DE ENTRADA ------------------------------------------
    IF p_motivo IS NULL OR p_motivo NOT IN ('Renuncia', 'Despido') THEN
        RAISE EXCEPTION 'Motivo inválido: %. Use ''Renuncia'' o ''Despido''.', p_motivo;
    END IF;

    -- FOR UPDATE bloquea la fila para que nadie más la modifique durante el proceso
    SELECT * INTO v_emp FROM empleados WHERE id_empleado = p_empleado_id FOR UPDATE;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'El empleado % no existe.', p_empleado_id;
    END IF;
    IF v_emp.estado = 'Inactivo' THEN
        RAISE EXCEPTION 'El empleado % (%) ya está Inactivo.', p_empleado_id, v_emp.nombre;
    END IF;

    -- 2. INACTIVAR AL EMPLEADO (no se borra: se conserva el historial) ------
    UPDATE empleados
    SET    estado = 'Inactivo', motivo_retiro = p_motivo, fecha_retiro = NOW()
    WHERE  id_empleado = p_empleado_id;

    -- 3. RECORRER SUS ASIGNACIONES VIGENTES ---------------------------------
    FOR v_asig IN
        SELECT id_asignacion, activo_id
        FROM   asignaciones_activos
        WHERE  empleado_id = p_empleado_id AND estado = 'Vigente'
        ORDER  BY id_asignacion
    LOOP
        -- 3a. Finalizar la asignación del empleado que se retira
        UPDATE asignaciones_activos
        SET    estado = 'Finalizada', fecha_fin = CURRENT_DATE
        WHERE  id_asignacion = v_asig.id_asignacion;

        -- 3b. Buscar reemplazo: mismo departamento, Activo, distinto del que se va,
        --     y con la menor cantidad de activos vigentes (reparto equitativo)
        v_nuevo_id := NULL;
        SELECT e.id_empleado INTO v_nuevo_id
        FROM   empleados e
        LEFT JOIN asignaciones_activos a
               ON a.empleado_id = e.id_empleado AND a.estado = 'Vigente'
        WHERE  e.departamento = v_emp.departamento
          AND  e.estado       = 'Activo'
          AND  e.id_empleado <> p_empleado_id
        GROUP  BY e.id_empleado
        ORDER  BY COUNT(a.id_asignacion) ASC, e.id_empleado ASC
        LIMIT  1;

        IF v_nuevo_id IS NULL THEN
            -- 3c. Nadie disponible: el activo queda sin responsable y se deja constancia
            INSERT INTO inconsistencias (tabla_origen, operacion, registro_id, datos_rechazados, motivo, fecha_registro)
            VALUES ('asignaciones_activos', 'INSERT', NULL,
                    format('activo_id=%s, departamento=%s', v_asig.activo_id, v_emp.departamento),
                    format('No se encontró un empleado Activo en el departamento %s para reasignar el activo %s.',
                           v_emp.departamento, v_asig.activo_id),
                    NOW());
            v_sin_reemplazo := v_sin_reemplazo + 1;
        ELSE
            -- 3d. Crear la nueva asignación (aquí se dispara el trigger de la PARTE 1)
            INSERT INTO asignaciones_activos (activo_id, empleado_id, fecha_asignacion, estado)
            VALUES (v_asig.activo_id, v_nuevo_id, CURRENT_DATE, 'Vigente');

            -- ROW_COUNT dice cuántas filas se insertaron realmente (0 si el trigger la rechazó)
            GET DIAGNOSTICS v_filas = ROW_COUNT;

            IF v_filas = 1 THEN
                -- 3e. Dejar constancia en la tabla de auditoría
                INSERT INTO auditoria (activo_id, empleado_anterior_id, empleado_nuevo_id, motivo, fecha_reasignacion)
                VALUES (v_asig.activo_id, p_empleado_id, v_nuevo_id, p_motivo, NOW());
                v_reasignados := v_reasignados + 1;
            ELSE
                v_sin_reemplazo := v_sin_reemplazo + 1;   -- el trigger ya registró el motivo
            END IF;
        END IF;
    END LOOP;

    -- 4. RESUMEN -------------------------------------------------------------
    RAISE NOTICE 'Empleado % (%) inactivado por %. Activos reasignados: %. Activos sin reemplazo: %.',
                 p_empleado_id, v_emp.nombre, p_motivo, v_reasignados, v_sin_reemplazo;
END;
$$;


/* =====================================================================
   PARTE 3. TRIGGER ADICIONAL (opcional)  -  trg_mitigacion_valida_y_cierra
   ---------------------------------------------------------------------
   Automatiza la relación incidentes <-> mitigaciones:
     - Rechaza una mitigación cuya fecha de resolución sea ANTERIOR a la
       fecha de detección del incidente (esto no se puede validar con un
       CHECK porque compara columnas de dos tablas distintas).
     - Si es válida, marca el incidente como 'Resuelto' automáticamente.
   ===================================================================== */
CREATE OR REPLACE FUNCTION fn_mitigacion_valida_y_cierra()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
DECLARE
    v_deteccion TIMESTAMP;
BEGIN
    SELECT fecha_deteccion INTO v_deteccion
    FROM   incidentes
    WHERE  id_incidente = NEW.incidente_id;

    -- Si el incidente no existe, se deja continuar: la FK lo rechazará con su propio error
    IF NOT FOUND THEN
        RETURN NEW;
    END IF;

    IF NEW.fecha_resolucion < v_deteccion THEN
        INSERT INTO inconsistencias (tabla_origen, operacion, registro_id, datos_rechazados, motivo, fecha_registro)
        VALUES ('mitigaciones', 'INSERT', NULL,
                format('incidente_id=%s, analista_soc_id=%s, fecha_resolucion=%s',
                       NEW.incidente_id, NEW.analista_soc_id, NEW.fecha_resolucion),
                format('La fecha de resolución es anterior a la fecha de detección del incidente %s (%s).',
                       NEW.incidente_id, v_deteccion),
                NOW());
        RAISE NOTICE 'Mitigación rechazada: fecha de resolución anterior a la detección.';
        RETURN NULL;
    END IF;

    -- Mitigación válida: cerrar el incidente
    UPDATE incidentes
    SET    estado = 'Resuelto'
    WHERE  id_incidente = NEW.incidente_id AND estado <> 'Resuelto';

    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_mitigacion_valida_y_cierra ON mitigaciones;
CREATE TRIGGER trg_mitigacion_valida_y_cierra
    BEFORE INSERT ON mitigaciones
    FOR EACH ROW
    EXECUTE FUNCTION fn_mitigacion_valida_y_cierra();


/* =====================================================================
   PARTE 4. ESTRATEGIA DE OPTIMIZACIÓN  -  ÍNDICE B-TREE PARCIAL
   ---------------------------------------------------------------------
   CONSULTA CRÍTICA
   Es la pantalla principal del SOC: "los últimos incidentes que siguen
   sin resolver", y también la base de las consultas 2, 5 y 8:

       SELECT activo_id, tipo_amenaza_id, fecha_deteccion
       FROM   incidentes
       WHERE  estado IN ('Abierto', 'En Investigación')
       ORDER  BY fecha_deteccion DESC
       LIMIT  20;

   PROBLEMA
   Sin índice, PostgreSQL lee la tabla completa (Seq Scan), filtra por
   estado y luego ordena. A medida que 'incidentes' crece a cientos de
   miles de filas, esa lectura completa se vuelve lenta; y casi todos los
   incidentes están 'Resuelto' (en este proyecto 30 de 40), es decir, se
   leen muchas filas que luego se descartan.

   SOLUCIÓN: índice B-Tree PARCIAL sobre (fecha_deteccion DESC)
     - B-Tree (y no Hash): la consulta usa ORDER BY y rangos de fecha;
       un índice Hash solo sirve para igualdad (=) y no almacena orden.
     - PARCIAL (WHERE estado IN (...)): solo indexa los incidentes sin
       resolver. Es muy pequeño, se mantiene rápido en cada INSERT/UPDATE
       y cabe en memoria.
     - fecha_deteccion DESC: el índice ya está ordenado como lo pide el
       ORDER BY, así PostgreSQL evita el paso de ordenamiento (Sort) y,
       con LIMIT 20, se detiene tras leer solo 20 entradas.
     - INCLUDE (activo_id, tipo_amenaza_id): guarda en el índice las
       columnas que la consulta muestra, lo que permite un 'Index Only
       Scan' (sin tocar la tabla).
   ===================================================================== */

-- 4.1 Índice definitivo sobre la tabla real
DROP INDEX IF EXISTS idx_incidentes_sin_resolver;
CREATE INDEX idx_incidentes_sin_resolver
    ON incidentes (fecha_deteccion DESC)
    INCLUDE (activo_id, tipo_amenaza_id)
    WHERE estado IN ('Abierto', 'En Investigación');

/* ---------------------------------------------------------------------
   4.2 PRUEBA DE RENDIMIENTO (antes / después)
   Con solo 40 filas PostgreSQL siempre preferirá leer la tabla completa,
   porque es más barato que usar el índice. Para ver el efecto real se
   crea una tabla de prueba con 500.000 incidentes (98% resueltos).
   --------------------------------------------------------------------- */
DROP TABLE IF EXISTS incidentes_prueba;
CREATE TABLE incidentes_prueba (
    id_incidente     SERIAL PRIMARY KEY,
    activo_id        INT,
    tipo_amenaza_id  INT,
    fecha_deteccion  TIMESTAMP NOT NULL,
    estado           VARCHAR(30) NOT NULL
);

INSERT INTO incidentes_prueba (activo_id, tipo_amenaza_id, fecha_deteccion, estado)
SELECT 1 + (g % 40),                                     -- activo 1..40
       1 + (g % 35),                                     -- amenaza 1..35
       TIMESTAMP '2020-01-01' + (g * INTERVAL '1 minute'),
       CASE WHEN g % 100 = 0 THEN 'Abierto'              -- 1% abiertos
            WHEN g % 100 = 1 THEN 'En Investigación'     -- 1% en investigación
            ELSE 'Resuelto' END                          -- 98% resueltos
FROM generate_series(1, 500000) AS g;

ANALYZE incidentes_prueba;       -- actualiza las estadísticas del planificador

-- ANTES: sin índice. Busque en el plan "Seq Scan" y "Sort", y el 'Execution Time'
EXPLAIN (ANALYZE, BUFFERS)
SELECT activo_id, tipo_amenaza_id, fecha_deteccion
FROM   incidentes_prueba
WHERE  estado IN ('Abierto', 'En Investigación')
ORDER  BY fecha_deteccion DESC
LIMIT  20;

-- Se crea el MISMO índice sobre la tabla de prueba
CREATE INDEX idx_prueba_sin_resolver
    ON incidentes_prueba (fecha_deteccion DESC)
    INCLUDE (activo_id, tipo_amenaza_id)
    WHERE estado IN ('Abierto', 'En Investigación');
ANALYZE incidentes_prueba;

-- DESPUÉS: debe aparecer "Index Only Scan using idx_prueba_sin_resolver",
-- sin 'Sort' y con un 'Execution Time' mucho menor
EXPLAIN (ANALYZE, BUFFERS)
SELECT activo_id, tipo_amenaza_id, fecha_deteccion
FROM   incidentes_prueba
WHERE  estado IN ('Abierto', 'En Investigación')
ORDER  BY fecha_deteccion DESC
LIMIT  20;

-- Tamaño del índice parcial frente al de toda la tabla (el parcial es mucho menor)
SELECT pg_size_pretty(pg_relation_size('incidentes_prueba'))       AS tamano_tabla,
       pg_size_pretty(pg_relation_size('idx_prueba_sin_resolver')) AS tamano_indice_parcial,
       pg_size_pretty(pg_relation_size('incidentes_prueba_pkey'))  AS tamano_indice_pk_completo;

-- Limpieza de la tabla de prueba
DROP TABLE incidentes_prueba;


-- Confirma de forma definitiva todo lo creado en las PARTES 1 a 4
COMMIT;

/* =====================================================================
   PARTE 5. PRUEBAS DE FUNCIONAMIENTO
   Cada bloque se ejecuta dentro de una transacción que termina con
   ROLLBACK: se ve el resultado, pero los datos NO quedan modificados.
   ===================================================================== */

/* ---------- PRUEBA A: el trigger rechaza asignaciones inválidas ----------- */
BEGIN;

-- A1. Asignar un activo a un empleado INACTIVO (id 1 se retiró) -> debe rechazarse
INSERT INTO asignaciones_activos (activo_id, empleado_id, fecha_asignacion, estado)
VALUES (1, 1, CURRENT_DATE, 'Vigente');

-- A2. Asignar un activo que YA tiene responsable vigente -> debe rechazarse
INSERT INTO asignaciones_activos (activo_id, empleado_id, fecha_asignacion, estado)
SELECT aa.activo_id,
       (SELECT id_empleado FROM empleados
        WHERE estado = 'Activo' AND id_empleado <> aa.empleado_id
        ORDER BY id_empleado LIMIT 1),
       CURRENT_DATE, 'Vigente'
FROM   asignaciones_activos aa
WHERE  aa.estado = 'Vigente'
LIMIT  1;

-- Ninguna de las dos se guardó, y quedaron registradas en 'inconsistencias':
SELECT id_inconsistencia, tabla_origen, operacion, datos_rechazados, motivo
FROM   inconsistencias
ORDER  BY id_inconsistencia DESC
LIMIT  2;

ROLLBACK;

/* ---------- PRUEBA B: procedimiento con reasignación normal --------------- */
BEGIN;

DO $$
DECLARE v_id INT;
BEGIN
    -- Toma un empleado de TI que tenga un activo vigente
    SELECT e.id_empleado INTO v_id
    FROM   empleados e
    JOIN   asignaciones_activos a ON a.empleado_id = e.id_empleado AND a.estado = 'Vigente'
    WHERE  e.departamento = 'TI' AND e.estado = 'Activo'
    ORDER  BY e.id_empleado
    LIMIT  1;

    CALL sp_inactivar_empleado(v_id, 'Renuncia');
END;
$$;

-- Resultado: el activo cambió de responsable y quedó la constancia en auditoria
SELECT au.id_auditoria, ar.nombre_host,
       ea.nombre AS empleado_anterior, en.nombre AS empleado_nuevo,
       au.motivo, au.fecha_reasignacion
FROM   auditoria au
JOIN   activos_red ar ON ar.id_activo   = au.activo_id
JOIN   empleados   ea ON ea.id_empleado = au.empleado_anterior_id
JOIN   empleados   en ON en.id_empleado = au.empleado_nuevo_id
ORDER  BY au.id_auditoria DESC
LIMIT  3;

ROLLBACK;

/* ---------- PRUEBA C: procedimiento cuando NO hay a quién reasignar ------- */
BEGIN;

-- Se inactiva uno a uno a todo el departamento Comercial; al llegar al último
-- empleado ya no queda nadie activo en el departamento para recibir sus equipos.
DO $$
DECLARE r RECORD;
BEGIN
    FOR r IN SELECT id_empleado FROM empleados
             WHERE departamento = 'Comercial' AND estado = 'Activo'
             ORDER BY id_empleado
    LOOP
        CALL sp_inactivar_empleado(r.id_empleado, 'Despido');
    END LOOP;
END;
$$;

SELECT tabla_origen, datos_rechazados, motivo
FROM   inconsistencias
ORDER  BY id_inconsistencia DESC
LIMIT  2;

ROLLBACK;

/* ---------- PRUEBA D: trigger adicional de mitigaciones ------------------- */
BEGIN;

-- D1. Mitigación con fecha anterior a la detección -> rechazada
INSERT INTO mitigaciones (incidente_id, analista_soc_id, acciones_tomadas, fecha_resolucion)
SELECT id_incidente, 1, 'Prueba con fecha inválida', fecha_deteccion - INTERVAL '1 day'
FROM   incidentes WHERE estado = 'Abierto' ORDER BY id_incidente LIMIT 1;

-- D2. Mitigación válida -> el incidente pasa a 'Resuelto' automáticamente
INSERT INTO mitigaciones (incidente_id, analista_soc_id, acciones_tomadas, fecha_resolucion)
SELECT id_incidente, 1, 'Prueba con fecha válida: amenaza contenida', fecha_deteccion + INTERVAL '3 hours'
FROM   incidentes WHERE estado = 'Abierto' ORDER BY id_incidente LIMIT 1;

SELECT id_incidente, estado
FROM   incidentes
WHERE  id_incidente = (SELECT MIN(id_incidente) FROM incidentes
                       WHERE id_incidente IN (SELECT incidente_id FROM mitigaciones
                                              WHERE acciones_tomadas LIKE 'Prueba con fecha válida%'));

ROLLBACK;

/* ---------- Verificación final: objetos creados --------------------------- */
SELECT tgname AS trigger, tgrelid::regclass AS tabla
FROM   pg_trigger
WHERE  NOT tgisinternal
ORDER  BY tgname;

SELECT routine_name AS rutina, routine_type AS tipo
FROM   information_schema.routines
WHERE  routine_schema = 'public' AND routine_name IN ('sp_inactivar_empleado', 'fn_validar_asignacion', 'fn_mitigacion_valida_y_cierra')
ORDER  BY routine_name;

SELECT indexname, indexdef FROM pg_indexes WHERE indexname = 'idx_incidentes_sin_resolver';
