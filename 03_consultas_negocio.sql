/* =====================================================================
   SCRIPT 3 - CONSULTAS DE NEGOCIO (HITO 2)
   10 consultas de complejidad media-alta sobre el modelo SOC.
   Ejecutar DESPUÉS de 01_ddl_estructura.sql y 02_dml_datos.sql

   Cada consulta indica:
     - Pregunta de negocio que responde
     - Tablas y tipo de JOIN usados
     - Técnicas aplicadas (filtros, agregaciones, GROUP BY / HAVING, etc.)

   RECORDATORIO DE SQL (orden lógico de ejecución):
     FROM/JOIN -> WHERE -> GROUP BY -> HAVING -> SELECT -> ORDER BY -> LIMIT
     * WHERE filtra filas ANTES de agrupar.
     * HAVING filtra grupos DESPUÉS de agrupar (permite usar COUNT, SUM, AVG).
   ===================================================================== */

SET client_encoding = 'UTF8';


/* =====================================================================
   CONSULTA 1
   Pregunta: ¿Qué tipos de amenaza generan más incidentes desde 2025 y
             cuánto tarda el SOC en dar la primera respuesta?
   Tablas  : tipos_amenaza INNER JOIN incidentes
             LEFT JOIN (subconsulta con la primera mitigación de cada incidente)
   Técnicas: COUNT DISTINCT, COUNT FILTER, AVG, subconsulta en el FROM,
             GROUP BY + HAVING
   ===================================================================== */
SELECT
    ta.nombre_amenaza,
    ta.nivel_riesgo,
    COUNT(DISTINCT i.id_incidente)                                         AS total_incidentes,
    -- FILTER cuenta solo las filas que cumplen la condición
    COUNT(DISTINCT i.id_incidente) FILTER (WHERE i.estado <> 'Resuelto')   AS sin_resolver,
    -- Tiempo promedio (en horas) entre la detección y la PRIMERA mitigación
    ROUND(AVG(EXTRACT(EPOCH FROM (pm.primera_resolucion - i.fecha_deteccion)) / 3600)::NUMERIC, 1)
                                                                           AS horas_promedio_respuesta
FROM tipos_amenaza ta
INNER JOIN incidentes i
        ON i.tipo_amenaza_id = ta.id_amenaza
-- LEFT JOIN: conserva los incidentes aunque todavía no tengan mitigación
LEFT JOIN (
        SELECT incidente_id, MIN(fecha_resolucion) AS primera_resolucion
        FROM   mitigaciones
        GROUP  BY incidente_id
     ) pm ON pm.incidente_id = i.id_incidente
WHERE i.fecha_deteccion >= '2025-01-01'
GROUP BY ta.id_amenaza, ta.nombre_amenaza, ta.nivel_riesgo
HAVING COUNT(DISTINCT i.id_incidente) >= 2          -- solo amenazas recurrentes
ORDER BY total_incidentes DESC, horas_promedio_respuesta DESC;


/* =====================================================================
   CONSULTA 2
   Pregunta: ¿Qué activos de criticidad Alta o Media tienen incidentes sin
             resolver y cuántos días llevan abiertos?
   Tablas  : activos_red INNER JOIN incidentes INNER JOIN tipos_amenaza
   Técnicas: filtros con IN, STRING_AGG, BOOL_OR, GROUP BY + HAVING
   ===================================================================== */
SELECT
    ar.nombre_host,
    ar.tipo_dispositivo,
    ar.criticidad,
    COUNT(*)                                       AS incidentes_sin_resolver,
    -- STRING_AGG une en una sola celda las amenazas distintas
    STRING_AGG(DISTINCT ta.nombre_amenaza, ', ')   AS amenazas,
    -- Días transcurridos desde el incidente abierto más antiguo
    MAX(CURRENT_DATE - i.fecha_deteccion::DATE)    AS dias_abierto_maximo
FROM activos_red ar
INNER JOIN incidentes    i  ON i.activo_id       = ar.id_activo
INNER JOIN tipos_amenaza ta ON ta.id_amenaza     = i.tipo_amenaza_id
WHERE ar.criticidad IN ('Alta', 'Media')
  AND i.estado IN ('Abierto', 'En Investigación')
GROUP BY ar.id_activo, ar.nombre_host, ar.tipo_dispositivo, ar.criticidad
-- BOOL_OR devuelve TRUE si ALGUNA fila del grupo cumple la condición:
-- solo interesan activos con al menos una amenaza Crítica o Alta
HAVING BOOL_OR(ta.nivel_riesgo IN ('Crítico', 'Alto'))
ORDER BY dias_abierto_maximo DESC;


/* =====================================================================
   CONSULTA 3
   Pregunta: ¿Qué activos tienen mayor exposición por vulnerabilidades que
             aún no están parcheadas?
   Tablas  : activos_red INNER JOIN activo_vulnerabilidad
             INNER JOIN vulnerabilidades_conocidas
   Técnicas: COUNT, AVG, MAX, SUM, filtro WHERE, GROUP BY + HAVING
   ===================================================================== */
SELECT
    ar.nombre_host,
    ar.criticidad,
    COUNT(*)                          AS vulnerabilidades_abiertas,
    ROUND(AVG(v.puntaje_cvss), 2)     AS cvss_promedio,
    MAX(v.puntaje_cvss)               AS cvss_maximo,
    SUM(v.puntaje_cvss)               AS exposicion_total      -- suma de CVSS como "puntos de riesgo"
FROM activos_red ar
INNER JOIN activo_vulnerabilidad     av ON av.activo_id         = ar.id_activo
INNER JOIN vulnerabilidades_conocidas v ON v.id_vulnerabilidad  = av.vulnerabilidad_id
WHERE av.estado_parcheo IN ('Pendiente', 'Mitigado')            -- todo lo que no está 'Parcheado'
GROUP BY ar.id_activo, ar.nombre_host, ar.criticidad
HAVING SUM(v.puntaje_cvss) >= 15                                -- exposición acumulada relevante
ORDER BY exposicion_total DESC, cvss_maximo DESC;


/* =====================================================================
   CONSULTA 4
   Pregunta: ¿Cómo se reparte la carga de trabajo del SOC por turno y nivel
             de certificación?
   Tablas  : analistas_soc LEFT JOIN mitigaciones LEFT JOIN incidentes
             LEFT JOIN tipos_amenaza
   Técnicas: LEFT JOIN encadenados (incluye analistas sin mitigaciones),
             COUNT DISTINCT, AVG, división segura con NULLIF, GROUP BY + HAVING
   ===================================================================== */
SELECT
    an.turno,
    an.nivel_certificacion,
    COUNT(DISTINCT an.id_analista)                                   AS analistas,
    COUNT(m.id_mitigacion)                                           AS mitigaciones,
    -- Mitigaciones por analista (los analistas sin trabajo también cuentan en el divisor)
    ROUND(COUNT(m.id_mitigacion)::NUMERIC / NULLIF(COUNT(DISTINCT an.id_analista), 0), 2)
                                                                     AS mitigaciones_por_analista,
    COUNT(m.id_mitigacion) FILTER (WHERE ta.nivel_riesgo = 'Crítico') AS incidentes_criticos_atendidos,
    ROUND(AVG(EXTRACT(EPOCH FROM (m.fecha_resolucion - i.fecha_deteccion)) / 3600)::NUMERIC, 1)
                                                                     AS horas_promedio_resolucion
FROM analistas_soc an
LEFT JOIN mitigaciones  m  ON m.analista_soc_id = an.id_analista
LEFT JOIN incidentes    i  ON i.id_incidente    = m.incidente_id
LEFT JOIN tipos_amenaza ta ON ta.id_amenaza     = i.tipo_amenaza_id
GROUP BY an.turno, an.nivel_certificacion
HAVING COUNT(DISTINCT an.id_analista) >= 2                       -- grupos con al menos 2 analistas
ORDER BY mitigaciones_por_analista DESC;


/* =====================================================================
   CONSULTA 5
   Pregunta: ¿Qué departamentos concentran más incidentes en los equipos que
             hoy tienen asignados?
   Tablas  : incidentes INNER JOIN activos_red INNER JOIN asignaciones_activos
             INNER JOIN empleados INNER JOIN tipos_amenaza  (5 tablas)
   Técnicas: JOIN con condición compuesta, filtro entre fechas, CASE dentro de
             SUM, GROUP BY + HAVING
   ===================================================================== */
SELECT
    e.departamento,
    COUNT(DISTINCT e.id_empleado)                       AS responsables_actuales,
    COUNT(*)                                            AS incidentes,
    SUM(CASE WHEN ta.nivel_riesgo = 'Crítico' THEN 1 ELSE 0 END) AS incidentes_criticos,
    COUNT(*) FILTER (WHERE i.estado <> 'Resuelto')      AS incidentes_sin_resolver
FROM incidentes i
INNER JOIN activos_red ar            ON ar.id_activo   = i.activo_id
-- Solo la asignación VIGENTE de cada equipo (el responsable actual)
INNER JOIN asignaciones_activos aa   ON aa.activo_id   = ar.id_activo
                                    AND aa.estado      = 'Vigente'
INNER JOIN empleados e               ON e.id_empleado  = aa.empleado_id
INNER JOIN tipos_amenaza ta          ON ta.id_amenaza  = i.tipo_amenaza_id
-- Solo incidentes ocurridos mientras ese responsable tenía el equipo
WHERE i.fecha_deteccion::DATE >= aa.fecha_asignacion
GROUP BY e.departamento
HAVING COUNT(*) >= 2
ORDER BY incidentes DESC;


/* =====================================================================
   CONSULTA 6
   Pregunta: ¿Cuántos empleados activos NO tienen ningún equipo asignado,
             por departamento?
   Tablas  : empleados LEFT JOIN asignaciones_activos LEFT JOIN activos_red
   Técnicas: LEFT JOIN con condición en el ON (para no perder empleados sin
             asignación), COUNT DISTINCT + FILTER, porcentaje, GROUP BY + HAVING
   ===================================================================== */
SELECT
    e.departamento,
    COUNT(DISTINCT e.id_empleado)                                         AS empleados_activos,
    COUNT(DISTINCT e.id_empleado) FILTER (WHERE aa.id_asignacion IS NULL) AS sin_equipo,
    COUNT(DISTINCT e.id_empleado) FILTER (WHERE aa.id_asignacion IS NOT NULL) AS con_equipo,
    COUNT(DISTINCT e.id_empleado) FILTER (WHERE ar.criticidad = 'Alta')   AS con_equipo_critico,
    ROUND(100.0 * COUNT(DISTINCT e.id_empleado) FILTER (WHERE aa.id_asignacion IS NULL)
          / COUNT(DISTINCT e.id_empleado), 1)                             AS pct_sin_equipo
FROM empleados e
-- La condición 'Vigente' va en el ON (no en el WHERE) para que los empleados
-- sin asignación sigan apareciendo con NULL en las columnas de aa
LEFT JOIN asignaciones_activos aa ON aa.empleado_id = e.id_empleado
                                 AND aa.estado      = 'Vigente'
LEFT JOIN activos_red ar          ON ar.id_activo   = aa.activo_id
WHERE e.estado = 'Activo'
GROUP BY e.departamento
HAVING COUNT(DISTINCT e.id_empleado) FILTER (WHERE aa.id_asignacion IS NULL) >= 1
ORDER BY pct_sin_equipo DESC;


/* =====================================================================
   CONSULTA 7
   Pregunta: ¿Cuántos activos se reasignaron por renuncias y despidos, y a
             qué departamentos afectó más? (usa la tabla de auditoría)
   Tablas  : auditoria INNER JOIN empleados (anterior) INNER JOIN empleados
             (nuevo) INNER JOIN activos_red  -> "self join" con 2 alias
   Técnicas: la misma tabla unida dos veces, filtro entre columnas de
             distintos alias, MIN/MAX de fechas, STRING_AGG, GROUP BY + HAVING
   ===================================================================== */
SELECT
    ea.departamento                                   AS departamento,
    au.motivo,
    COUNT(*)                                          AS reasignaciones,
    COUNT(DISTINCT au.activo_id)                      AS activos_distintos,
    COUNT(DISTINCT au.empleado_anterior_id)           AS empleados_retirados,
    COUNT(DISTINCT au.empleado_nuevo_id)              AS empleados_receptores,
    MIN(au.fecha_reasignacion)::DATE                  AS primera_reasignacion,
    MAX(au.fecha_reasignacion)::DATE                  AS ultima_reasignacion,
    STRING_AGG(DISTINCT ar.tipo_dispositivo, ', ')    AS tipos_de_equipo
FROM auditoria au
INNER JOIN empleados   ea ON ea.id_empleado = au.empleado_anterior_id   -- quien se retiró
INNER JOIN empleados   en ON en.id_empleado = au.empleado_nuevo_id      -- quien recibe el equipo
INNER JOIN activos_red ar ON ar.id_activo   = au.activo_id
WHERE ea.departamento = en.departamento           -- regla: el equipo se queda en el mismo departamento
GROUP BY ea.departamento, au.motivo
HAVING COUNT(*) >= 3
ORDER BY reasignaciones DESC, departamento;


/* =====================================================================
   CONSULTA 8
   Pregunta: ¿Cuáles son los 10 activos de mayor riesgo combinando incidentes
             sufridos y vulnerabilidades pendientes?
   Tablas  : activos_red INNER JOIN CTE de incidentes INNER JOIN CTE de
             vulnerabilidades (que usa INNER JOIN con 2 tablas más)
   Técnicas: CTE (WITH), agregaciones separadas para evitar duplicar filas,
             HAVING dentro de cada CTE, CASE como multiplicador, LIMIT
   ===================================================================== */
WITH inc AS (                                   -- resumen de incidentes por activo
    SELECT activo_id,
           COUNT(*)                                       AS total_incidentes,
           COUNT(*) FILTER (WHERE estado <> 'Resuelto')   AS incidentes_abiertos
    FROM   incidentes
    GROUP  BY activo_id
    HAVING COUNT(*) >= 1
),
vul AS (                                        -- resumen de vulnerabilidades pendientes por activo
    SELECT av.activo_id,
           COUNT(*)            AS vulnerabilidades_pendientes,
           MAX(v.puntaje_cvss) AS cvss_maximo
    FROM   activo_vulnerabilidad av
    INNER JOIN vulnerabilidades_conocidas v ON v.id_vulnerabilidad = av.vulnerabilidad_id
    WHERE  av.estado_parcheo = 'Pendiente'
    GROUP  BY av.activo_id
    HAVING MAX(v.puntaje_cvss) >= 7.0           -- solo vulnerabilidades altas o críticas
)
SELECT
    ar.nombre_host,
    ar.tipo_dispositivo,
    ar.criticidad,
    inc.total_incidentes,
    inc.incidentes_abiertos,
    vul.vulnerabilidades_pendientes,
    vul.cvss_maximo,
    -- Índice de riesgo (ponderación propuesta): incidentes + vulnerabilidades,
    -- multiplicado por la criticidad del activo
    ROUND(
        (inc.total_incidentes * 2 + inc.incidentes_abiertos * 3
         + vul.vulnerabilidades_pendientes * 2 + vul.cvss_maximo)
        * CASE ar.criticidad WHEN 'Alta' THEN 1.5 WHEN 'Media' THEN 1.2 ELSE 1.0 END
    , 1) AS indice_riesgo
FROM activos_red ar
INNER JOIN inc ON inc.activo_id = ar.id_activo
INNER JOIN vul ON vul.activo_id = ar.id_activo
ORDER BY indice_riesgo DESC
LIMIT 10;


/* =====================================================================
   CONSULTA 9
   Pregunta: ¿Cómo evolucionan los incidentes trimestre a trimestre?
   Tablas  : incidentes INNER JOIN tipos_amenaza
             LEFT JOIN (primera mitigación por incidente)
   Técnicas: DATE_TRUNC, función de ventana SUM() OVER para el acumulado,
             GROUP BY + HAVING
   Nota    : la función de ventana se calcula DESPUÉS del HAVING, por eso el
             acumulado solo suma los trimestres que pasan el filtro.
   ===================================================================== */
SELECT
    DATE_TRUNC('quarter', i.fecha_deteccion)::DATE                          AS trimestre,
    COUNT(*)                                                                AS incidentes,
    COUNT(*) FILTER (WHERE ta.nivel_riesgo = 'Crítico')                     AS criticos,
    COUNT(DISTINCT i.activo_id)                                             AS activos_afectados,
    ROUND(AVG(EXTRACT(EPOCH FROM (pm.primera_resolucion - i.fecha_deteccion)) / 3600)::NUMERIC, 1)
                                                                            AS horas_promedio_resolucion,
    -- Total acumulado: suma el conteo de cada trimestre con los anteriores
    SUM(COUNT(*)) OVER (ORDER BY DATE_TRUNC('quarter', i.fecha_deteccion))  AS acumulado
FROM incidentes i
INNER JOIN tipos_amenaza ta ON ta.id_amenaza = i.tipo_amenaza_id
LEFT JOIN (
        SELECT incidente_id, MIN(fecha_resolucion) AS primera_resolucion
        FROM   mitigaciones
        GROUP  BY incidente_id
     ) pm ON pm.incidente_id = i.id_incidente
WHERE i.fecha_deteccion >= '2025-01-01'
GROUP BY DATE_TRUNC('quarter', i.fecha_deteccion)
HAVING COUNT(*) >= 2
ORDER BY trimestre;


/* =====================================================================
   CONSULTA 10
   Pregunta: ¿Qué vulnerabilidades graves (CVSS >= 7) están más extendidas en
             la red y qué porcentaje ya está parcheado?
   Tablas  : vulnerabilidades_conocidas INNER JOIN activo_vulnerabilidad
             INNER JOIN activos_red
   Técnicas: COUNT DISTINCT, COUNT FILTER, porcentaje, STRING_AGG,
             GROUP BY + HAVING con FILTER
   ===================================================================== */
SELECT
    v.cve_code,
    v.puntaje_cvss,
    COUNT(DISTINCT ar.id_activo)                                         AS activos_afectados,
    COUNT(*) FILTER (WHERE av.estado_parcheo = 'Pendiente')              AS pendientes,
    COUNT(*) FILTER (WHERE av.estado_parcheo = 'Mitigado')               AS mitigados,
    COUNT(*) FILTER (WHERE av.estado_parcheo = 'Parcheado')              AS parcheados,
    ROUND(100.0 * COUNT(*) FILTER (WHERE av.estado_parcheo = 'Parcheado') / COUNT(*), 1)
                                                                         AS pct_parcheado,
    STRING_AGG(DISTINCT ar.tipo_dispositivo, ', ')                       AS tipos_de_equipo
FROM vulnerabilidades_conocidas v
INNER JOIN activo_vulnerabilidad av ON av.vulnerabilidad_id = v.id_vulnerabilidad
INNER JOIN activos_red           ar ON ar.id_activo         = av.activo_id
WHERE v.puntaje_cvss >= 7.0
GROUP BY v.id_vulnerabilidad, v.cve_code, v.puntaje_cvss
HAVING COUNT(*) FILTER (WHERE av.estado_parcheo = 'Pendiente') >= 1     -- al menos un activo sin parchear
ORDER BY pendientes DESC, v.puntaje_cvss DESC, activos_afectados DESC;
