/* =====================================================================
   SCRIPT 5 - USUARIO DE SOLO LECTURA PARA LA APLICACIÓN
   Ejecutar conectado como 'postgres' a la base de datos del proyecto
   (la misma donde cargó los scripts 01 a 04).

   ¿Para qué sirve?
   La aplicación no debe conectarse con el superusuario 'postgres'. Se crea
   un usuario 'app_lectura' que solo puede LEER (SELECT): aunque alguien
   escriba un DELETE o un DROP TABLE desde la app, la base de datos lo rechaza.

   IMPORTANTE: cambie la contraseña antes de ejecutar el script.
   ===================================================================== */

-- 1. Crear el usuario solo si no existe (así se puede ejecutar varias veces)
DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'app_lectura') THEN
        CREATE ROLE app_lectura LOGIN PASSWORD 'CambieEstaClave_123';
    END IF;
END
$$;

-- 2. Permiso para "entrar" al esquema donde están las tablas
GRANT USAGE ON SCHEMA public TO app_lectura;

-- 3. Permiso de LECTURA sobre todas las tablas actuales
GRANT SELECT ON ALL TABLES IN SCHEMA public TO app_lectura;

-- 4. Lo mismo para las tablas que se creen en el futuro
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT SELECT ON TABLES TO app_lectura;

-- 5. Seguro adicional: toda transacción de este usuario es de solo lectura
ALTER ROLE app_lectura SET default_transaction_read_only = on;

-- 6. Verificación: debe mostrar app_lectura con privilegio SELECT en las 11 tablas
SELECT grantee, COUNT(*) AS tablas_con_select
FROM   information_schema.role_table_grants
WHERE  grantee = 'app_lectura' AND privilege_type = 'SELECT'
GROUP  BY grantee;
