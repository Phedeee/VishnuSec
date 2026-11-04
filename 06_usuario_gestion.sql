/* =====================================================================
   SCRIPT 6 - USUARIO DE GESTIÓN PARA LA APLICACIÓN (ETAPA 5)
   Ejecutar conectado como 'postgres' a la base de datos del proyecto,
   DESPUÉS de los scripts 01 a 05.

   ¿Para qué sirve?
   La pestaña "Gestión de empleados" necesita ESCRIBIR en la base de datos
   (inactivar un empleado y reasignar sus activos). Pero la aplicación no
   debe usar un usuario con permisos de escritura sobre las tablas.

   Solución: el usuario 'app_gestion' NO puede modificar ninguna tabla por su
   cuenta; lo único que puede hacer (además de leer) es EJECUTAR el
   procedimiento sp_inactivar_empleado. Ese procedimiento se declara
   SECURITY DEFINER: se ejecuta con los permisos de su dueño (postgres), así
   que puede escribir en las tablas, pero solo dentro de las reglas y
   validaciones que ya programamos en el procedimiento y en los triggers.

     usuario          permisos
     ---------------  ------------------------------------------------
     app_lectura      solo SELECT                      (script 05)
     app_gestion      SELECT + EJECUTAR sp_inactivar_empleado (este script)

   IMPORTANTE: cambie la contraseña antes de ejecutar el script.
   Este script se puede ejecutar varias veces sin problema.
   ===================================================================== */

-- 0. Comprobación previa: el procedimiento lo crea el script 04
DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_proc WHERE proname = 'sp_inactivar_empleado') THEN
        RAISE EXCEPTION 'No existe el procedimiento sp_inactivar_empleado. Ejecute primero el script 04_topicos_avanzados.sql en esta misma base de datos.';
    END IF;
END
$$;

-- 1. Crear el usuario solo si no existe
DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'app_gestion') THEN
        CREATE ROLE app_gestion LOGIN PASSWORD 'CambieEstaClaveGestion_123';
    END IF;
END
$$;

-- 2. Permiso de LECTURA (igual que app_lectura): entrar al esquema y hacer SELECT
GRANT USAGE ON SCHEMA public TO app_gestion;
GRANT SELECT ON ALL TABLES IN SCHEMA public TO app_gestion;
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT SELECT ON TABLES TO app_gestion;

-- 3. El procedimiento se ejecuta con los permisos de su dueño (SECURITY DEFINER).
--    SET search_path fija dónde buscar las tablas: es una medida de seguridad
--    obligatoria en procedimientos SECURITY DEFINER (evita que alguien "engañe"
--    al procedimiento creando objetos con el mismo nombre en otro esquema).
ALTER PROCEDURE sp_inactivar_empleado(INT, VARCHAR)
    SECURITY DEFINER
    SET search_path = public, pg_temp;

-- 4. Quién puede ejecutarlo: por defecto TODOS (PUBLIC) pueden ejecutar un
--    procedimiento. Se quita ese permiso general y se concede solo a app_gestion.
REVOKE ALL ON PROCEDURE sp_inactivar_empleado(INT, VARCHAR) FROM PUBLIC;
GRANT EXECUTE ON PROCEDURE sp_inactivar_empleado(INT, VARCHAR) TO app_gestion;

-- 5. Verificación
SELECT 'app_gestion puede ejecutar el procedimiento' AS comprobacion,
       has_function_privilege('app_gestion', 'sp_inactivar_empleado(integer, character varying)', 'EXECUTE') AS resultado
UNION ALL
SELECT 'app_lectura NO puede ejecutarlo',
       NOT has_function_privilege('app_lectura', 'sp_inactivar_empleado(integer, character varying)', 'EXECUTE')
UNION ALL
SELECT 'app_gestion NO puede modificar tablas',
       NOT has_table_privilege('app_gestion', 'empleados', 'UPDATE');
