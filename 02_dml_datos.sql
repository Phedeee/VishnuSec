/* =====================================================================
   SCRIPT 2 - DATOS (DML)
   Carga de datos de ejemplo: entre 30 y 40 registros por tabla.
   Ejecutar DESPUÉS de 01_ddl_estructura.sql

     psql -U postgres -d su_base_de_datos -f 02_dml_datos.sql

   NOTAS IMPORTANTES
   - Los id (SERIAL) se generan automáticamente en el orden de inserción
     (1, 2, 3...). Por eso las tablas hijas usan esos números como FK.
     Cada INSERT se carga en el orden correcto: primero las tablas
     maestras y al final las que dependen de ellas.
   - TRUNCATE ... RESTART IDENTITY reinicia las tablas y los contadores,
     así el script se puede ejecutar varias veces sin errores.
   - Los comentarios (-- ...) al final de cada fila explican a qué
     equipo, empleado o amenaza corresponde cada número.
   - Los CVE son vulnerabilidades reales y conocidas; los puntajes CVSS
     son aproximados y se usan con fines académicos.
   - Los empleados, equipos e incidentes son datos ficticios.
   ===================================================================== */

SET client_encoding = 'UTF8';

BEGIN;   -- Todo el script se ejecuta como una sola transacción:
         -- o se cargan todos los datos o no se carga ninguno.

TRUNCATE TABLE inconsistencias, auditoria, activo_vulnerabilidad, mitigaciones, incidentes,
               asignaciones_activos, vulnerabilidades_conocidas, analistas_soc, tipos_amenaza,
               empleados, activos_red
RESTART IDENTITY CASCADE;

/* ---------------------------------------------------------------------
   1. activos_red  (40 registros)
   Inventario: 30 equipos de infraestructura y 10 equipos personales (workstations y laptops).
   --------------------------------------------------------------------- */
INSERT INTO activos_red (direccion_ip, nombre_host, tipo_dispositivo, criticidad) VALUES
  ('10.10.1.11', 'SRV-DB-01', 'Servidor', 'Alta'),  -- id 1
  ('10.10.1.12', 'SRV-DB-02', 'Servidor', 'Alta'),  -- id 2
  ('10.10.1.21', 'SRV-WEB-01', 'Servidor', 'Alta'),  -- id 3
  ('10.10.1.22', 'SRV-WEB-02', 'Servidor', 'Media'),  -- id 4
  ('10.10.1.31', 'SRV-APP-01', 'Servidor', 'Alta'),  -- id 5
  ('10.10.1.32', 'SRV-APP-02', 'Servidor', 'Media'),  -- id 6
  ('10.10.1.5', 'SRV-AD-01', 'Servidor', 'Alta'),  -- id 7
  ('10.10.1.41', 'SRV-MAIL-01', 'Servidor', 'Alta'),  -- id 8
  ('10.10.1.51', 'SRV-FILE-01', 'Servidor', 'Media'),  -- id 9
  ('10.10.1.61', 'SRV-BKP-01', 'Servidor', 'Media'),  -- id 10
  ('10.10.0.1', 'RTR-CORE-01', 'Router', 'Alta'),  -- id 11
  ('10.10.0.2', 'RTR-CORE-02', 'Router', 'Alta'),  -- id 12
  ('10.10.0.3', 'RTR-EDGE-01', 'Router', 'Alta'),  -- id 13
  ('10.10.0.4', 'RTR-SUC-01', 'Router', 'Media'),  -- id 14
  ('10.10.2.1', 'SW-CORE-01', 'Switch', 'Alta'),  -- id 15
  ('10.10.2.2', 'SW-CORE-02', 'Switch', 'Alta'),  -- id 16
  ('10.10.2.11', 'SW-DIST-01', 'Switch', 'Media'),  -- id 17
  ('10.10.2.12', 'SW-DIST-02', 'Switch', 'Media'),  -- id 18
  ('10.10.2.21', 'SW-ACC-01', 'Switch', 'Baja'),  -- id 19
  ('10.10.2.22', 'SW-ACC-02', 'Switch', 'Baja'),  -- id 20
  ('10.10.0.250', 'FW-PERIM-01', 'Firewall', 'Alta'),  -- id 21
  ('10.10.0.251', 'FW-PERIM-02', 'Firewall', 'Alta'),  -- id 22
  ('10.10.0.252', 'FW-DMZ-01', 'Firewall', 'Alta'),  -- id 23
  ('10.10.0.253', 'FW-INT-01', 'Firewall', 'Media'),  -- id 24
  ('10.10.3.1', 'AP-PISO1-01', 'Access Point', 'Media'),  -- id 25
  ('10.10.3.2', 'AP-PISO2-01', 'Access Point', 'Media'),  -- id 26
  ('10.10.3.3', 'AP-BODEGA-01', 'Access Point', 'Baja'),  -- id 27
  ('10.10.4.1', 'PRN-ADM-01', 'Impresora', 'Baja'),  -- id 28
  ('10.10.4.2', 'PRN-FIN-01', 'Impresora', 'Baja'),  -- id 29
  ('10.10.4.3', 'PRN-LOG-01', 'Impresora', 'Baja'),  -- id 30
  ('10.20.10.11', 'WS-TI-01', 'Workstation', 'Media'),  -- id 31
  ('10.20.10.12', 'WS-TI-02', 'Workstation', 'Media'),  -- id 32
  ('10.20.10.101', 'LT-TI-01', 'Laptop', 'Media'),  -- id 33
  ('10.20.20.11', 'WS-FIN-01', 'Workstation', 'Alta'),  -- id 34
  ('10.20.20.12', 'WS-FIN-02', 'Workstation', 'Media'),  -- id 35
  ('10.20.20.101', 'LT-FIN-01', 'Laptop', 'Alta'),  -- id 36
  ('10.20.30.11', 'WS-OPE-01', 'Workstation', 'Baja'),  -- id 37
  ('10.20.30.101', 'LT-OPE-01', 'Laptop', 'Media'),  -- id 38
  ('10.20.40.11', 'WS-COM-01', 'Workstation', 'Baja'),  -- id 39
  ('10.20.40.101', 'LT-COM-01', 'Laptop', 'Media');  -- id 40

/* ---------------------------------------------------------------------
   2. empleados  (40 registros)
   Los 12 empleados 'Inactivo' ya se retiraron (renuncia o despido); sus activos fueron reasignados (ver auditoria).
   --------------------------------------------------------------------- */
INSERT INTO empleados (nombre, correo, departamento, estado, motivo_retiro, fecha_retiro) VALUES
  ('Andrés Gómez Mejía', 'andres.gomez@corpred.com.co', 'TI', 'Inactivo', 'Renuncia', '2023-02-17 17:30:00'),  -- id 1
  ('Carolina Rodríguez Ariza', 'carolina.rodriguez@corpred.com.co', 'TI', 'Inactivo', 'Despido', '2023-09-08 16:45:00'),  -- id 2
  ('Julián Martínez Gaitán', 'julian.martinez@corpred.com.co', 'TI', 'Inactivo', 'Renuncia', '2024-04-26 18:00:00'),  -- id 3
  ('Marcela López Zapata', 'marcela.lopez@corpred.com.co', 'TI', 'Activo', NULL, NULL),  -- id 4
  ('Santiago Hernández Rincón', 'santiago.hernandez@corpred.com.co', 'TI', 'Activo', NULL, NULL),  -- id 5
  ('Paola García Prieto', 'paola.garcia@corpred.com.co', 'TI', 'Activo', NULL, NULL),  -- id 6
  ('Camilo Ramírez Cano', 'camilo.ramirez@corpred.com.co', 'TI', 'Activo', NULL, NULL),  -- id 7
  ('Daniela Torres Pinzón', 'daniela.torres@corpred.com.co', 'TI', 'Activo', NULL, NULL),  -- id 8
  ('Felipe Díaz Camacho', 'felipe.diaz@corpred.com.co', 'TI', 'Activo', NULL, NULL),  -- id 9
  ('Natalia Vargas Montoya', 'natalia.vargas@corpred.com.co', 'Finanzas', 'Inactivo', 'Despido', '2023-03-31 17:15:00'),  -- id 10
  ('Sebastián Castro Leal', 'sebastian.castro@corpred.com.co', 'Finanzas', 'Inactivo', 'Renuncia', '2023-11-24 17:50:00'),  -- id 11
  ('Valentina Moreno Tamayo', 'valentina.moreno@corpred.com.co', 'Finanzas', 'Inactivo', 'Renuncia', '2024-06-14 16:30:00'),  -- id 12
  ('Mauricio Rojas Osorio', 'mauricio.rojas@corpred.com.co', 'Finanzas', 'Activo', NULL, NULL),  -- id 13
  ('Lorena Ortiz Barrios', 'lorena.ortiz@corpred.com.co', 'Finanzas', 'Activo', NULL, NULL),  -- id 14
  ('Esteban Silva Bernal', 'esteban.silva@corpred.com.co', 'Finanzas', 'Activo', NULL, NULL),  -- id 15
  ('Juliana Cárdenas Forero', 'juliana.cardenas@corpred.com.co', 'Finanzas', 'Activo', NULL, NULL),  -- id 16
  ('Jorge Mendoza Vega', 'jorge.mendoza@corpred.com.co', 'Finanzas', 'Activo', NULL, NULL),  -- id 17
  ('Diana Herrera Meza', 'diana.herrera@corpred.com.co', 'Operaciones', 'Inactivo', 'Renuncia', '2023-05-12 17:00:00'),  -- id 18
  ('Ricardo Jiménez Uribe', 'ricardo.jimenez@corpred.com.co', 'Operaciones', 'Inactivo', 'Despido', '2024-01-19 15:40:00'),  -- id 19
  ('Catalina Pardo Lozano', 'catalina.pardo@corpred.com.co', 'Operaciones', 'Inactivo', 'Despido', '2024-08-30 17:20:00'),  -- id 20
  ('Héctor Arias Mejía', 'hector.arias@corpred.com.co', 'Operaciones', 'Activo', NULL, NULL),  -- id 21
  ('Sandra Suárez Ariza', 'sandra.suarez@corpred.com.co', 'Operaciones', 'Activo', NULL, NULL),  -- id 22
  ('Óscar Navarro Gaitán', 'oscar.navarro@corpred.com.co', 'Operaciones', 'Activo', NULL, NULL),  -- id 23
  ('Angélica Quintero Zapata', 'angelica.quintero@corpred.com.co', 'Operaciones', 'Activo', NULL, NULL),  -- id 24
  ('Iván Peña Rincón', 'ivan.pena@corpred.com.co', 'Operaciones', 'Activo', NULL, NULL),  -- id 25
  ('Viviana Becerra Prieto', 'viviana.becerra@corpred.com.co', 'Comercial', 'Inactivo', 'Renuncia', '2023-07-07 17:10:00'),  -- id 26
  ('Fabián Salazar Cano', 'fabian.salazar@corpred.com.co', 'Comercial', 'Inactivo', 'Despido', '2024-03-08 16:00:00'),  -- id 27
  ('Laura Cortés Pinzón', 'laura.cortes@corpred.com.co', 'Comercial', 'Inactivo', 'Renuncia', '2024-10-11 17:45:00'),  -- id 28
  ('Gustavo Ríos Camacho', 'gustavo.rios@corpred.com.co', 'Comercial', 'Activo', NULL, NULL),  -- id 29
  ('Mónica Acosta Montoya', 'monica.acosta@corpred.com.co', 'Comercial', 'Activo', NULL, NULL),  -- id 30
  ('Alejandro Duarte Leal', 'alejandro.duarte@corpred.com.co', 'Comercial', 'Activo', NULL, NULL),  -- id 31
  ('Tatiana Parra Tamayo', 'tatiana.parra@corpred.com.co', 'Comercial', 'Activo', NULL, NULL),  -- id 32
  ('Rodrigo Valencia Osorio', 'rodrigo.valencia@corpred.com.co', 'Comercial', 'Activo', NULL, NULL),  -- id 33
  ('Yesenia Ballesteros Barrios', 'yesenia.ballesteros@corpred.com.co', 'Recursos Humanos', 'Activo', NULL, NULL),  -- id 34
  ('Nicolás Ospina Bernal', 'nicolas.ospina@corpred.com.co', 'Recursos Humanos', 'Activo', NULL, NULL),  -- id 35
  ('Adriana Franco Forero', 'adriana.franco@corpred.com.co', 'Recursos Humanos', 'Activo', NULL, NULL),  -- id 36
  ('Cristian Medina Vega', 'cristian.medina@corpred.com.co', 'Recursos Humanos', 'Activo', NULL, NULL),  -- id 37
  ('Liliana Beltrán Meza', 'liliana.beltran@corpred.com.co', 'Logística', 'Activo', NULL, NULL),  -- id 38
  ('Wilson Cruz Uribe', 'wilson.cruz@corpred.com.co', 'Logística', 'Activo', NULL, NULL),  -- id 39
  ('Patricia Reyes Lozano', 'patricia.reyes@corpred.com.co', 'Logística', 'Activo', NULL, NULL);  -- id 40

/* ---------------------------------------------------------------------
   3. tipos_amenaza  (35 registros)
   Catálogo de amenazas con su nivel de riesgo.
   --------------------------------------------------------------------- */
INSERT INTO tipos_amenaza (nombre_amenaza, nivel_riesgo, descripcion) VALUES
  ('Phishing', 'Alto', 'Correos fraudulentos masivos que suplantan a una entidad legítima para robar credenciales.'),  -- id 1
  ('Spear phishing', 'Alto', 'Phishing dirigido a una persona o cargo específico con información personalizada.'),  -- id 2
  ('Ransomware', 'Crítico', 'Malware que cifra los archivos de la víctima y exige un rescate para devolver el acceso.'),  -- id 3
  ('Malware genérico', 'Alto', 'Software malicioso no clasificado que compromete la integridad del equipo.'),  -- id 4
  ('Troyano', 'Alto', 'Programa que aparenta ser legítimo pero abre la puerta a un atacante.'),  -- id 5
  ('Spyware', 'Moderado', 'Software que recopila información del usuario sin su consentimiento.'),  -- id 6
  ('Keylogger', 'Alto', 'Registra las pulsaciones del teclado para capturar contraseñas y datos sensibles.'),  -- id 7
  ('Botnet', 'Alto', 'Equipo infectado que forma parte de una red controlada remotamente por un atacante.'),  -- id 8
  ('DDoS', 'Alto', 'Saturación de un servicio con tráfico masivo para dejarlo no disponible.'),  -- id 9
  ('Fuerza bruta', 'Moderado', 'Intentos automatizados y repetidos de adivinar credenciales de acceso.'),  -- id 10
  ('SQL Injection', 'Crítico', 'Inyección de sentencias SQL a través de formularios o parámetros mal validados.'),  -- id 11
  ('Cross-Site Scripting (XSS)', 'Moderado', 'Inyección de scripts en páginas web que se ejecutan en el navegador de otras personas.'),  -- id 12
  ('Man-in-the-Middle', 'Alto', 'Interceptación de comunicaciones entre dos partes sin que estas lo noten.'),  -- id 13
  ('Escalada de privilegios', 'Crítico', 'Obtención de permisos superiores a los asignados para controlar el sistema.'),  -- id 14
  ('Exfiltración de datos', 'Crítico', 'Transferencia no autorizada de información sensible fuera de la organización.'),  -- id 15
  ('Amenaza interna (Insider)', 'Alto', 'Uso indebido de accesos legítimos por parte de personal de la organización.'),  -- id 16
  ('Cryptojacking', 'Moderado', 'Uso no autorizado de recursos del equipo para minar criptomonedas.'),  -- id 17
  ('Rootkit', 'Crítico', 'Software que oculta su presencia y mantiene acceso privilegiado persistente.'),  -- id 18
  ('Zero-day exploit', 'Crítico', 'Explotación de una vulnerabilidad desconocida para la cual aún no existe parche.'),  -- id 19
  ('Credential stuffing', 'Alto', 'Reutilización de credenciales filtradas en otros servicios para acceder a cuentas.'),  -- id 20
  ('DNS spoofing', 'Alto', 'Alteración de respuestas DNS para redirigir a la víctima a sitios falsos.'),  -- id 21
  ('ARP spoofing', 'Moderado', 'Falsificación de mensajes ARP para desviar el tráfico de la red local.'),  -- id 22
  ('Backdoor', 'Crítico', 'Acceso oculto que permite a un atacante volver a ingresar al sistema.'),  -- id 23
  ('Ingeniería social', 'Moderado', 'Manipulación psicológica para que una persona revele información o realice acciones.'),  -- id 24
  ('Acceso no autorizado', 'Alto', 'Ingreso a un sistema o recurso sin los permisos correspondientes.'),  -- id 25
  ('Configuración insegura', 'Moderado', 'Parámetros por defecto o erróneos que dejan expuesto un servicio o equipo.'),  -- id 26
  ('Pérdida o robo de dispositivo', 'Moderado', 'Extravío o hurto de un equipo con información corporativa.'),  -- id 27
  ('Punto de acceso Wi-Fi falso (Rogue AP)', 'Alto', 'Red inalámbrica falsa que imita a la legítima para capturar tráfico.'),  -- id 28
  ('Ataque a la cadena de suministro', 'Crítico', 'Compromiso de un proveedor o componente de software para llegar a la organización.'),  -- id 29
  ('Amenaza persistente avanzada (APT)', 'Crítico', 'Intrusión prolongada y sigilosa realizada por un grupo con muchos recursos.'),  -- id 30
  ('Web shell', 'Crítico', 'Script malicioso cargado en un servidor web que permite controlarlo de forma remota.'),  -- id 31
  ('Escaneo de puertos', 'Moderado', 'Exploración de puertos abiertos para identificar servicios vulnerables.'),  -- id 32
  ('Secuestro de sesión', 'Alto', 'Robo de una sesión activa para suplantar a un usuario autenticado.'),  -- id 33
  ('Typosquatting', 'Moderado', 'Dominios con errores tipográficos creados para engañar a usuarios.'),  -- id 34
  ('Ransomware con doble extorsión', 'Crítico', 'Cifrado de archivos más amenaza de publicar la información robada.');  -- id 35

/* ---------------------------------------------------------------------
   4. analistas_soc  (32 registros)
   Equipo del SOC distribuido en tres turnos.
   --------------------------------------------------------------------- */
INSERT INTO analistas_soc (nombre, nivel_certificacion, turno) VALUES
  ('Mariana Aguirre', 'CISSP', 'Mañana'),  -- id 1
  ('Daniel Bolaños', 'Senior', 'Tarde'),  -- id 2
  ('Luisa Cabrera', 'Senior', 'Noche'),  -- id 3
  ('Samuel Delgado', 'Junior', 'Mañana'),  -- id 4
  ('Karen Escobar', 'Junior', 'Tarde'),  -- id 5
  ('Brayan Fonseca', 'Junior', 'Noche'),  -- id 6
  ('Melissa Guerrero', 'CISSP', 'Mañana'),  -- id 7
  ('Leonardo Hurtado', 'CISSP', 'Tarde'),  -- id 8
  ('Stefany Ibarra', 'Senior', 'Noche'),  -- id 9
  ('Edwin Jaramillo', 'Junior', 'Mañana'),  -- id 10
  ('Gabriela Londoño', 'Junior', 'Tarde'),  -- id 11
  ('Hernán Murcia', 'CISSP', 'Noche'),  -- id 12
  ('Jessica Niño', 'Junior', 'Mañana'),  -- id 13
  ('Mateo Orozco', 'Junior', 'Tarde'),  -- id 14
  ('Lucía Pineda', 'Junior', 'Noche'),  -- id 15
  ('Álvaro Quiroga', 'CISSP', 'Mañana'),  -- id 16
  ('Andrea Restrepo', 'Senior', 'Tarde'),  -- id 17
  ('Cesar Sarmiento', 'CISSP', 'Noche'),  -- id 18
  ('Natalie Trujillo', 'Junior', 'Mañana'),  -- id 19
  ('Julio Urrego', 'Senior', 'Tarde'),  -- id 20
  ('Ximena Villamizar', 'Senior', 'Noche'),  -- id 21
  ('Orlando Wilches', 'Senior', 'Mañana'),  -- id 22
  ('Paula Yepes', 'Senior', 'Tarde'),  -- id 23
  ('Ramiro Zambrano', 'Junior', 'Noche'),  -- id 24
  ('Sofía Barón', 'Senior', 'Mañana'),  -- id 25
  ('Tomás Castaño', 'Senior', 'Tarde'),  -- id 26
  ('Verónica Domínguez', 'CISSP', 'Noche'),  -- id 27
  ('Bruno Espinosa', 'Junior', 'Mañana'),  -- id 28
  ('Clara Figueroa', 'Senior', 'Tarde'),  -- id 29
  ('Darío Galvis', 'CISSP', 'Noche'),  -- id 30
  ('Elena Henao', 'Junior', 'Mañana'),  -- id 31
  ('Fernando Ibáñez', 'Senior', 'Tarde');  -- id 32

/* ---------------------------------------------------------------------
   5. vulnerabilidades_conocidas  (35 registros)
   Catálogo de CVEs reales (puntaje CVSS aproximado).
   --------------------------------------------------------------------- */
INSERT INTO vulnerabilidades_conocidas (cve_code, descripcion_tecnica, puntaje_cvss) VALUES
  ('CVE-2021-44228', 'Ejecución remota de código en Apache Log4j 2 (Log4Shell) mediante búsquedas JNDI en mensajes de registro.', 10.0),  -- id 1
  ('CVE-2017-0144', 'Ejecución remota de código en Microsoft SMBv1 (EternalBlue) mediante paquetes especialmente diseñados.', 8.1),  -- id 2
  ('CVE-2014-0160', 'Lectura de memoria en OpenSSL (Heartbleed) por validación incorrecta de la extensión Heartbeat de TLS.', 7.5),  -- id 3
  ('CVE-2019-0708', 'Ejecución remota de código en Servicios de Escritorio Remoto de Windows (BlueKeep) sin autenticación.', 9.8),  -- id 4
  ('CVE-2020-1472', 'Elevación de privilegios en Netlogon (Zerologon) que permite comprometer un controlador de dominio.', 10.0),  -- id 5
  ('CVE-2021-34527', 'Ejecución remota de código en el servicio Print Spooler de Windows (PrintNightmare).', 8.8),  -- id 6
  ('CVE-2022-22965', 'Ejecución remota de código en Spring Framework (Spring4Shell) por enlace de datos inseguro.', 9.8),  -- id 7
  ('CVE-2014-6271', 'Ejecución de comandos arbitrarios en GNU Bash (Shellshock) mediante variables de entorno manipuladas.', 9.8),  -- id 8
  ('CVE-2018-13379', 'Lectura arbitraria de archivos (path traversal) en FortiOS SSL VPN.', 9.8),  -- id 9
  ('CVE-2019-11510', 'Lectura arbitraria de archivos previa a la autenticación en Pulse Connect Secure.', 10.0),  -- id 10
  ('CVE-2021-26855', 'Falsificación de solicitudes del lado del servidor en Microsoft Exchange (ProxyLogon).', 9.8),  -- id 11
  ('CVE-2021-21972', 'Ejecución remota de código en el cliente vSphere de VMware vCenter Server.', 9.8),  -- id 12
  ('CVE-2023-4966', 'Divulgación de información sensible en Citrix NetScaler ADC y Gateway (Citrix Bleed).', 9.4),  -- id 13
  ('CVE-2023-34362', 'Inyección SQL en MOVEit Transfer que permite acceso no autorizado a la base de datos.', 9.8),  -- id 14
  ('CVE-2022-26134', 'Inyección OGNL con ejecución remota de código en Atlassian Confluence Server.', 9.8),  -- id 15
  ('CVE-2021-41773', 'Recorrido de rutas en Apache HTTP Server 2.4.49 que permite leer archivos fuera del directorio raíz.', 7.5),  -- id 16
  ('CVE-2017-5638', 'Ejecución remota de código en Apache Struts 2 por el analizador Jakarta Multipart.', 10.0),  -- id 17
  ('CVE-2018-11776', 'Ejecución remota de código en Apache Struts 2 por validación incorrecta del espacio de nombres.', 8.1),  -- id 18
  ('CVE-2019-19781', 'Recorrido de directorios en Citrix ADC y Gateway con ejecución remota de código.', 9.8),  -- id 19
  ('CVE-2020-0601', 'Suplantación en la validación de certificados criptográficos de Windows (CurveBall).', 8.1),  -- id 20
  ('CVE-2021-3156', 'Desbordamiento de memoria en sudo (Baron Samedit) que permite elevar privilegios a root.', 7.8),  -- id 21
  ('CVE-2016-5195', 'Condición de carrera en el kernel de Linux (Dirty COW) que permite escribir en memoria de solo lectura.', 7.0),  -- id 22
  ('CVE-2022-0847', 'Sobrescritura de archivos de solo lectura en el kernel de Linux (Dirty Pipe).', 7.8),  -- id 23
  ('CVE-2021-4034', 'Elevación de privilegios local en pkexec de Polkit (PwnKit).', 7.8),  -- id 24
  ('CVE-2023-23397', 'Elevación de privilegios en Microsoft Outlook mediante un mensaje con recordatorio malicioso.', 9.8),  -- id 25
  ('CVE-2022-30190', 'Ejecución remota de código en la herramienta de diagnóstico MSDT de Windows (Follina).', 7.8),  -- id 26
  ('CVE-2020-5902', 'Ejecución remota de código en la interfaz de administración (TMUI) de F5 BIG-IP.', 9.8),  -- id 27
  ('CVE-2021-22205', 'Ejecución remota de código en GitLab por el manejo de imágenes con ExifTool.', 10.0),  -- id 28
  ('CVE-2022-1388', 'Omisión de autenticación en iControl REST de F5 BIG-IP.', 9.8),  -- id 29
  ('CVE-2020-1938', 'Lectura y ejecución de archivos por el conector AJP de Apache Tomcat (Ghostcat).', 9.8),  -- id 30
  ('CVE-2023-44487', 'Denegación de servicio en el protocolo HTTP/2 mediante ataque Rapid Reset.', 7.5),  -- id 31
  ('CVE-2024-3094', 'Puerta trasera introducida en las bibliotecas xz/liblzma que compromete SSH.', 10.0),  -- id 32
  ('CVE-2023-38831', 'Ejecución de código en WinRAR al abrir archivos comprimidos especialmente construidos.', 7.8),  -- id 33
  ('CVE-2022-41040', 'Falsificación de solicitudes del lado del servidor en Exchange (ProxyNotShell).', 8.8),  -- id 34
  ('CVE-2024-6387', 'Condición de carrera en OpenSSH (regreSSHion) con posible ejecución remota de código como root.', 8.1);  -- id 35

/* ---------------------------------------------------------------------
   6. asignaciones_activos  (40 registros)
   Historial de responsables de los 10 equipos personales.
   Cada equipo pasó por 4 responsables: 3 ya retirados (Finalizada) y 1 actual (Vigente).
   --------------------------------------------------------------------- */
INSERT INTO asignaciones_activos (activo_id, empleado_id, fecha_asignacion, fecha_fin, estado) VALUES
  (32, 1, '2022-02-10', '2023-02-17', 'Finalizada'),  -- WS-TI-02 -> Andrés Gómez Mejía (TI)
  (31, 1, '2022-02-13', '2023-02-17', 'Finalizada'),  -- WS-TI-01 -> Andrés Gómez Mejía (TI)
  (39, 26, '2022-02-13', '2023-07-07', 'Finalizada'),  -- WS-COM-01 -> Viviana Becerra Prieto (Comercial)
  (40, 26, '2022-05-12', '2023-07-07', 'Finalizada'),  -- LT-COM-01 -> Viviana Becerra Prieto (Comercial)
  (37, 18, '2022-06-09', '2023-05-12', 'Finalizada'),  -- WS-OPE-01 -> Diana Herrera Meza (Operaciones)
  (38, 18, '2022-06-15', '2023-05-12', 'Finalizada'),  -- LT-OPE-01 -> Diana Herrera Meza (Operaciones)
  (33, 1, '2022-07-21', '2023-02-17', 'Finalizada'),  -- LT-TI-01 -> Andrés Gómez Mejía (TI)
  (36, 10, '2022-08-03', '2023-03-31', 'Finalizada'),  -- LT-FIN-01 -> Natalia Vargas Montoya (Finanzas)
  (34, 10, '2022-08-21', '2023-03-31', 'Finalizada'),  -- WS-FIN-01 -> Natalia Vargas Montoya (Finanzas)
  (35, 10, '2022-10-05', '2023-03-31', 'Finalizada'),  -- WS-FIN-02 -> Natalia Vargas Montoya (Finanzas)
  (31, 2, '2023-02-17', '2023-09-08', 'Finalizada'),  -- WS-TI-01 -> Carolina Rodríguez Ariza (TI)
  (32, 2, '2023-02-17', '2023-09-08', 'Finalizada'),  -- WS-TI-02 -> Carolina Rodríguez Ariza (TI)
  (33, 2, '2023-02-17', '2023-09-08', 'Finalizada'),  -- LT-TI-01 -> Carolina Rodríguez Ariza (TI)
  (34, 11, '2023-03-31', '2023-11-24', 'Finalizada'),  -- WS-FIN-01 -> Sebastián Castro Leal (Finanzas)
  (35, 11, '2023-03-31', '2023-11-24', 'Finalizada'),  -- WS-FIN-02 -> Sebastián Castro Leal (Finanzas)
  (36, 11, '2023-03-31', '2023-11-24', 'Finalizada'),  -- LT-FIN-01 -> Sebastián Castro Leal (Finanzas)
  (37, 19, '2023-05-12', '2024-01-19', 'Finalizada'),  -- WS-OPE-01 -> Ricardo Jiménez Uribe (Operaciones)
  (38, 19, '2023-05-12', '2024-01-19', 'Finalizada'),  -- LT-OPE-01 -> Ricardo Jiménez Uribe (Operaciones)
  (39, 27, '2023-07-07', '2024-03-08', 'Finalizada'),  -- WS-COM-01 -> Fabián Salazar Cano (Comercial)
  (40, 27, '2023-07-07', '2024-03-08', 'Finalizada'),  -- LT-COM-01 -> Fabián Salazar Cano (Comercial)
  (31, 3, '2023-09-08', '2024-04-26', 'Finalizada'),  -- WS-TI-01 -> Julián Martínez Gaitán (TI)
  (32, 3, '2023-09-08', '2024-04-26', 'Finalizada'),  -- WS-TI-02 -> Julián Martínez Gaitán (TI)
  (33, 3, '2023-09-08', '2024-04-26', 'Finalizada'),  -- LT-TI-01 -> Julián Martínez Gaitán (TI)
  (34, 12, '2023-11-24', '2024-06-14', 'Finalizada'),  -- WS-FIN-01 -> Valentina Moreno Tamayo (Finanzas)
  (35, 12, '2023-11-24', '2024-06-14', 'Finalizada'),  -- WS-FIN-02 -> Valentina Moreno Tamayo (Finanzas)
  (36, 12, '2023-11-24', '2024-06-14', 'Finalizada'),  -- LT-FIN-01 -> Valentina Moreno Tamayo (Finanzas)
  (37, 20, '2024-01-19', '2024-08-30', 'Finalizada'),  -- WS-OPE-01 -> Catalina Pardo Lozano (Operaciones)
  (38, 20, '2024-01-19', '2024-08-30', 'Finalizada'),  -- LT-OPE-01 -> Catalina Pardo Lozano (Operaciones)
  (39, 28, '2024-03-08', '2024-10-11', 'Finalizada'),  -- WS-COM-01 -> Laura Cortés Pinzón (Comercial)
  (40, 28, '2024-03-08', '2024-10-11', 'Finalizada'),  -- LT-COM-01 -> Laura Cortés Pinzón (Comercial)
  (31, 4, '2024-04-26', NULL, 'Vigente'),  -- WS-TI-01 -> Marcela López Zapata (TI)
  (32, 5, '2024-04-26', NULL, 'Vigente'),  -- WS-TI-02 -> Santiago Hernández Rincón (TI)
  (33, 6, '2024-04-26', NULL, 'Vigente'),  -- LT-TI-01 -> Paola García Prieto (TI)
  (34, 13, '2024-06-14', NULL, 'Vigente'),  -- WS-FIN-01 -> Mauricio Rojas Osorio (Finanzas)
  (35, 14, '2024-06-14', NULL, 'Vigente'),  -- WS-FIN-02 -> Lorena Ortiz Barrios (Finanzas)
  (36, 15, '2024-06-14', NULL, 'Vigente'),  -- LT-FIN-01 -> Esteban Silva Bernal (Finanzas)
  (37, 21, '2024-08-30', NULL, 'Vigente'),  -- WS-OPE-01 -> Héctor Arias Mejía (Operaciones)
  (38, 22, '2024-08-30', NULL, 'Vigente'),  -- LT-OPE-01 -> Sandra Suárez Ariza (Operaciones)
  (39, 29, '2024-10-11', NULL, 'Vigente'),  -- WS-COM-01 -> Gustavo Ríos Camacho (Comercial)
  (40, 30, '2024-10-11', NULL, 'Vigente');  -- LT-COM-01 -> Mónica Acosta Montoya (Comercial)

/* ---------------------------------------------------------------------
   7. incidentes  (40 registros)
   Eventos de seguridad ordenados por fecha de detección.
   Hay 30 Resueltos, 5 Abiertos y 5 En Investigación.
   --------------------------------------------------------------------- */
INSERT INTO incidentes (activo_id, tipo_amenaza_id, fecha_deteccion, estado) VALUES
  (9, 19, '2025-04-14 18:29:30', 'Resuelto'),  -- SRV-FILE-01 / Zero-day exploit
  (22, 19, '2025-04-30 14:45:44', 'Resuelto'),  -- FW-PERIM-02 / Zero-day exploit
  (36, 17, '2025-06-16 07:27:28', 'Resuelto'),  -- LT-FIN-01 / Cryptojacking
  (32, 1, '2025-07-06 19:30:48', 'Resuelto'),  -- WS-TI-02 / Phishing
  (36, 6, '2025-07-23 23:05:59', 'Resuelto'),  -- LT-FIN-01 / Spyware
  (22, 10, '2025-08-06 23:11:36', 'Resuelto'),  -- FW-PERIM-02 / Fuerza bruta
  (21, 25, '2025-08-26 15:31:54', 'Resuelto'),  -- FW-PERIM-01 / Acceso no autorizado
  (9, 12, '2025-09-05 22:35:17', 'Resuelto'),  -- SRV-FILE-01 / Cross-Site Scripting (XSS)
  (40, 34, '2025-11-18 04:51:16', 'Resuelto'),  -- LT-COM-01 / Typosquatting
  (23, 10, '2025-11-18 07:19:13', 'Resuelto'),  -- FW-DMZ-01 / Fuerza bruta
  (32, 24, '2025-12-09 12:46:25', 'Resuelto'),  -- WS-TI-02 / Ingeniería social
  (15, 21, '2025-12-12 08:57:03', 'Resuelto'),  -- SW-CORE-01 / DNS spoofing
  (34, 7, '2025-12-30 19:18:03', 'Resuelto'),  -- WS-FIN-01 / Keylogger
  (5, 10, '2026-01-09 14:21:45', 'Resuelto'),  -- SRV-APP-01 / Fuerza bruta
  (4, 19, '2026-01-10 02:11:12', 'Resuelto'),  -- SRV-WEB-02 / Zero-day exploit
  (29, 26, '2026-01-16 23:12:38', 'Resuelto'),  -- PRN-FIN-01 / Configuración insegura
  (31, 4, '2026-01-19 11:14:23', 'Resuelto'),  -- WS-TI-01 / Malware genérico
  (9, 25, '2026-02-03 20:05:12', 'Resuelto'),  -- SRV-FILE-01 / Acceso no autorizado
  (2, 9, '2026-03-09 19:19:21', 'Resuelto'),  -- SRV-DB-02 / DDoS
  (39, 23, '2026-03-11 18:13:45', 'Resuelto'),  -- WS-COM-01 / Backdoor
  (34, 6, '2026-03-20 19:21:17', 'Resuelto'),  -- WS-FIN-01 / Spyware
  (6, 15, '2026-05-08 08:41:36', 'Resuelto'),  -- SRV-APP-02 / Exfiltración de datos
  (32, 20, '2026-05-11 17:59:05', 'Resuelto'),  -- WS-TI-02 / Credential stuffing
  (35, 24, '2026-05-27 10:24:03', 'Resuelto'),  -- WS-FIN-02 / Ingeniería social
  (33, 3, '2026-06-14 05:07:05', 'Resuelto'),  -- LT-TI-01 / Ransomware
  (26, 33, '2026-06-17 17:55:19', 'Resuelto'),  -- AP-PISO2-01 / Secuestro de sesión
  (29, 23, '2026-07-06 09:41:40', 'Resuelto'),  -- PRN-FIN-01 / Backdoor
  (3, 26, '2026-07-08 06:07:52', 'Resuelto'),  -- SRV-WEB-01 / Configuración insegura
  (6, 12, '2026-07-18 23:40:47', 'Resuelto'),  -- SRV-APP-02 / Cross-Site Scripting (XSS)
  (35, 20, '2026-07-21 03:34:53', 'Resuelto'),  -- WS-FIN-02 / Credential stuffing
  (11, 32, '2026-09-08 09:39:19', 'En Investigación'),  -- RTR-CORE-01 / Escaneo de puertos
  (17, 13, '2026-09-20 10:48:30', 'Abierto'),  -- SW-DIST-01 / Man-in-the-Middle
  (24, 21, '2026-09-21 14:34:30', 'Abierto'),  -- FW-INT-01 / DNS spoofing
  (16, 10, '2026-09-23 22:42:40', 'En Investigación'),  -- SW-CORE-02 / Fuerza bruta
  (17, 10, '2026-09-27 06:34:50', 'Abierto'),  -- SW-DIST-01 / Fuerza bruta
  (2, 15, '2026-10-03 11:44:50', 'En Investigación'),  -- SRV-DB-02 / Exfiltración de datos
  (32, 27, '2026-10-06 12:39:30', 'En Investigación'),  -- WS-TI-02 / Pérdida o robo de dispositivo
  (39, 1, '2026-10-09 18:25:09', 'En Investigación'),  -- WS-COM-01 / Phishing
  (24, 26, '2026-10-18 23:52:25', 'Abierto'),  -- FW-INT-01 / Configuración insegura
  (33, 24, '2026-10-21 19:52:44', 'Abierto');  -- LT-TI-01 / Ingeniería social

/* ---------------------------------------------------------------------
   8. mitigaciones  (34 registros)
   Cada incidente Resuelto tiene al menos una mitigación; 4 de ellos tienen una segunda de seguimiento.
   --------------------------------------------------------------------- */
INSERT INTO mitigaciones (incidente_id, analista_soc_id, acciones_tomadas, fecha_resolucion) VALUES
  (1, 20, 'Se activó el plan de respuesta, se contuvo el movimiento lateral y se coordinó con el proveedor la corrección definitiva.', '2025-04-15 03:00:30'),  -- incidente 1 (Zero-day exploit)
  (1, 10, 'Seguimiento posterior al incidente: se validó la efectividad de la contención, se documentaron las lecciones aprendidas y se actualizaron los procedimientos del SOC.', '2025-04-15 12:00:30'),  -- incidente 1 (Zero-day exploit)
  (2, 30, 'Se aplicó el parche del fabricante, se aisló el sistema comprometido y se realizó una búsqueda de indicadores de compromiso en la red.', '2025-05-02 07:36:44'),  -- incidente 2 (Zero-day exploit)
  (2, 4, 'Seguimiento posterior al incidente: se validó la efectividad de la contención, se documentaron las lecciones aprendidas y se actualizaron los procedimientos del SOC.', '2025-05-03 10:36:44'),  -- incidente 2 (Zero-day exploit)
  (3, 10, 'Se ejecutó un análisis completo con EDR, se eliminó el artefacto malicioso y se reinstaló el sistema desde una imagen limpia.', '2025-06-19 15:00:28'),  -- incidente 3 (Cryptojacking)
  (4, 28, 'Se eliminó el correo malicioso de todos los buzones, se reforzó el filtro antiphishing y se capacitó al usuario afectado.', '2025-07-10 06:51:48'),  -- incidente 4 (Phishing)
  (4, 18, 'Seguimiento posterior al incidente: se validó la efectividad de la contención, se documentaron las lecciones aprendidas y se actualizaron los procedimientos del SOC.', '2025-07-11 06:51:48'),  -- incidente 4 (Phishing)
  (5, 15, 'Se ejecutó un análisis completo con EDR, se eliminó el artefacto malicioso y se reinstaló el sistema desde una imagen limpia.', '2025-07-27 17:50:59'),  -- incidente 5 (Spyware)
  (6, 26, 'Se bloquearon las cuentas comprometidas, se forzó el cambio de contraseñas, se activó el doble factor y se limitaron los intentos de inicio de sesión.', '2025-08-07 07:23:36'),  -- incidente 6 (Fuerza bruta)
  (7, 3, 'Se bloquearon las cuentas comprometidas, se forzó el cambio de contraseñas, se activó el doble factor y se limitaron los intentos de inicio de sesión.', '2025-08-30 06:05:54'),  -- incidente 7 (Acceso no autorizado)
  (8, 29, 'Se aplicó el parche de la aplicación, se sanitizaron los campos afectados y se auditaron los accesos a la base de datos.', '2025-09-09 12:47:17'),  -- incidente 8 (Cross-Site Scripting (XSS))
  (9, 2, 'Se aisló el equipo de la red, se restablecieron las credenciales del usuario y se bloqueó el dominio remitente en el gateway de correo.', '2025-11-19 01:32:16'),  -- incidente 9 (Typosquatting)
  (10, 9, 'Se bloquearon las cuentas comprometidas, se forzó el cambio de contraseñas, se activó el doble factor y se limitaron los intentos de inicio de sesión.', '2025-11-19 08:01:13'),  -- incidente 10 (Fuerza bruta)
  (11, 25, 'Se eliminó el correo malicioso de todos los buzones, se reforzó el filtro antiphishing y se capacitó al usuario afectado.', '2025-12-11 03:13:25'),  -- incidente 11 (Ingeniería social)
  (12, 6, 'Se aislaron los puertos afectados, se activó la inspección dinámica de ARP/DNS y se actualizó la configuración de segmentación.', '2025-12-14 14:16:03'),  -- incidente 12 (DNS spoofing)
  (13, 23, 'Se aisló el activo, se eliminaron los procesos y llaves de registro persistentes y se actualizaron las firmas antimalware.', '2025-12-31 21:34:03'),  -- incidente 13 (Keylogger)
  (15, 9, 'Se activó el plan de respuesta, se contuvo el movimiento lateral y se coordinó con el proveedor la corrección definitiva.', '2026-01-10 23:44:12'),  -- incidente 15 (Zero-day exploit)
  (14, 32, 'Se revisaron los registros de autenticación, se bloquearon las IP de origen y se habilitó el bloqueo temporal por intentos fallidos.', '2026-01-11 23:39:45'),  -- incidente 14 (Fuerza bruta)
  (14, 8, 'Seguimiento posterior al incidente: se validó la efectividad de la contención, se documentaron las lecciones aprendidas y se actualizaron los procedimientos del SOC.', '2026-01-12 05:39:45'),  -- incidente 14 (Fuerza bruta)
  (16, 29, 'Se aplicó borrado remoto, se bloqueó el dispositivo y se emitieron nuevas credenciales al usuario.', '2026-01-17 18:45:38'),  -- incidente 16 (Configuración insegura)
  (17, 7, 'Se ejecutó un análisis completo con EDR, se eliminó el artefacto malicioso y se reinstaló el sistema desde una imagen limpia.', '2026-01-20 18:28:23'),  -- incidente 17 (Malware genérico)
  (18, 6, 'Se revisaron los registros de autenticación, se bloquearon las IP de origen y se habilitó el bloqueo temporal por intentos fallidos.', '2026-02-06 10:46:12'),  -- incidente 18 (Acceso no autorizado)
  (20, 1, 'Se ejecutó un análisis completo con EDR, se eliminó el artefacto malicioso y se reinstaló el sistema desde una imagen limpia.', '2026-03-12 18:07:45'),  -- incidente 20 (Backdoor)
  (19, 27, 'Se activó la mitigación en el proveedor de internet, se aplicaron reglas de limitación de tasa y se bloquearon los rangos de IP atacantes.', '2026-03-12 21:09:21'),  -- incidente 19 (DDoS)
  (21, 23, 'Se ejecutó un análisis completo con EDR, se eliminó el artefacto malicioso y se reinstaló el sistema desde una imagen limpia.', '2026-03-23 23:04:17'),  -- incidente 21 (Spyware)
  (22, 7, 'Se bloqueó la cuenta involucrada, se auditaron los accesos a información sensible y se notificó al área de cumplimiento.', '2026-05-10 01:26:36'),  -- incidente 22 (Exfiltración de datos)
  (23, 14, 'Se revisaron los registros de autenticación, se bloquearon las IP de origen y se habilitó el bloqueo temporal por intentos fallidos.', '2026-05-14 22:17:05'),  -- incidente 23 (Credential stuffing)
  (24, 9, 'Se eliminó el correo malicioso de todos los buzones, se reforzó el filtro antiphishing y se capacitó al usuario afectado.', '2026-05-28 03:14:03'),  -- incidente 24 (Ingeniería social)
  (25, 7, 'Se desconectó el equipo, se restauró la información desde la última copia de respaldo íntegra y se aplicaron los parches pendientes.', '2026-06-15 09:17:05'),  -- incidente 25 (Ransomware)
  (26, 4, 'Se bloquearon las cuentas comprometidas, se forzó el cambio de contraseñas, se activó el doble factor y se limitaron los intentos de inicio de sesión.', '2026-06-19 19:41:19'),  -- incidente 26 (Secuestro de sesión)
  (27, 7, 'Se aisló el activo, se eliminaron los procesos y llaves de registro persistentes y se actualizaron las firmas antimalware.', '2026-07-07 19:01:40'),  -- incidente 27 (Backdoor)
  (28, 5, 'Se aplicó borrado remoto, se bloqueó el dispositivo y se emitieron nuevas credenciales al usuario.', '2026-07-10 00:06:52'),  -- incidente 28 (Configuración insegura)
  (29, 11, 'Se corrigió la validación de entradas con consultas parametrizadas, se desplegó una regla en el WAF y se revisó la base de datos en busca de alteraciones.', '2026-07-20 12:56:47'),  -- incidente 29 (Cross-Site Scripting (XSS))
  (30, 1, 'Se revisaron los registros de autenticación, se bloquearon las IP de origen y se habilitó el bloqueo temporal por intentos fallidos.', '2026-07-23 12:29:53');  -- incidente 30 (Credential stuffing)

/* ---------------------------------------------------------------------
   9. activo_vulnerabilidad  (40 registros)
   Vulnerabilidades que afectan a cada activo y su estado de parcheo.
   --------------------------------------------------------------------- */
INSERT INTO activo_vulnerabilidad (activo_id, vulnerabilidad_id, estado_parcheo) VALUES
  (2, 21, 'Parcheado'),  -- SRV-DB-02 / CVE-2021-3156
  (2, 23, 'Parcheado'),  -- SRV-DB-02 / CVE-2022-0847
  (2, 32, 'Pendiente'),  -- SRV-DB-02 / CVE-2024-3094
  (3, 8, 'Parcheado'),  -- SRV-WEB-01 / CVE-2014-6271
  (3, 23, 'Parcheado'),  -- SRV-WEB-01 / CVE-2022-0847
  (3, 24, 'Pendiente'),  -- SRV-WEB-01 / CVE-2021-4034
  (5, 8, 'Pendiente'),  -- SRV-APP-01 / CVE-2014-6271
  (5, 15, 'Mitigado'),  -- SRV-APP-01 / CVE-2022-26134
  (5, 16, 'Pendiente'),  -- SRV-APP-01 / CVE-2021-41773
  (5, 17, 'Parcheado'),  -- SRV-APP-01 / CVE-2017-5638
  (5, 21, 'Parcheado'),  -- SRV-APP-01 / CVE-2021-3156
  (6, 21, 'Parcheado'),  -- SRV-APP-02 / CVE-2021-3156
  (7, 34, 'Parcheado'),  -- SRV-AD-01 / CVE-2022-41040
  (8, 33, 'Parcheado'),  -- SRV-MAIL-01 / CVE-2023-38831
  (10, 32, 'Pendiente'),  -- SRV-BKP-01 / CVE-2024-3094
  (12, 29, 'Parcheado'),  -- RTR-CORE-02 / CVE-2022-1388
  (13, 10, 'Parcheado'),  -- RTR-EDGE-01 / CVE-2019-11510
  (13, 13, 'Mitigado'),  -- RTR-EDGE-01 / CVE-2023-4966
  (13, 29, 'Pendiente'),  -- RTR-EDGE-01 / CVE-2022-1388
  (14, 3, 'Mitigado'),  -- RTR-SUC-01 / CVE-2014-0160
  (14, 31, 'Pendiente'),  -- RTR-SUC-01 / CVE-2023-44487
  (15, 31, 'Pendiente'),  -- SW-CORE-01 / CVE-2023-44487
  (18, 31, 'Mitigado'),  -- SW-DIST-02 / CVE-2023-44487
  (21, 9, 'Pendiente'),  -- FW-PERIM-01 / CVE-2018-13379
  (21, 27, 'Parcheado'),  -- FW-PERIM-01 / CVE-2020-5902
  (21, 31, 'Pendiente'),  -- FW-PERIM-01 / CVE-2023-44487
  (22, 3, 'Mitigado'),  -- FW-PERIM-02 / CVE-2014-0160
  (23, 9, 'Parcheado'),  -- FW-DMZ-01 / CVE-2018-13379
  (24, 9, 'Pendiente'),  -- FW-INT-01 / CVE-2018-13379
  (25, 3, 'Parcheado'),  -- AP-PISO1-01 / CVE-2014-0160
  (31, 2, 'Mitigado'),  -- WS-TI-01 / CVE-2017-0144
  (31, 4, 'Pendiente'),  -- WS-TI-01 / CVE-2019-0708
  (31, 26, 'Mitigado'),  -- WS-TI-01 / CVE-2022-30190
  (31, 33, 'Pendiente'),  -- WS-TI-01 / CVE-2023-38831
  (32, 25, 'Mitigado'),  -- WS-TI-02 / CVE-2023-23397
  (34, 2, 'Mitigado'),  -- WS-FIN-01 / CVE-2017-0144
  (34, 20, 'Mitigado'),  -- WS-FIN-01 / CVE-2020-0601
  (37, 6, 'Parcheado'),  -- WS-OPE-01 / CVE-2021-34527
  (38, 33, 'Mitigado'),  -- LT-OPE-01 / CVE-2023-38831
  (40, 6, 'Mitigado');  -- LT-COM-01 / CVE-2021-34527

/* ---------------------------------------------------------------------
   10. auditoria  (30 registros)
   Reasignaciones de activos cuando un empleado renuncia o es despedido.
   Coincide con las asignaciones Finalizada/Vigente de la tabla asignaciones_activos.
   --------------------------------------------------------------------- */
INSERT INTO auditoria (activo_id, empleado_anterior_id, empleado_nuevo_id, motivo, fecha_reasignacion) VALUES
  (31, 1, 2, 'Renuncia', '2023-02-17 17:34:32'),  -- WS-TI-01: Andrés Gómez Mejía -> Carolina Rodríguez Ariza
  (33, 1, 2, 'Renuncia', '2023-02-17 17:34:35'),  -- LT-TI-01: Andrés Gómez Mejía -> Carolina Rodríguez Ariza
  (32, 1, 2, 'Renuncia', '2023-02-17 17:34:38'),  -- WS-TI-02: Andrés Gómez Mejía -> Carolina Rodríguez Ariza
  (35, 10, 11, 'Despido', '2023-03-31 17:19:07'),  -- WS-FIN-02: Natalia Vargas Montoya -> Sebastián Castro Leal
  (34, 10, 11, 'Despido', '2023-03-31 17:19:28'),  -- WS-FIN-01: Natalia Vargas Montoya -> Sebastián Castro Leal
  (36, 10, 11, 'Despido', '2023-03-31 17:19:43'),  -- LT-FIN-01: Natalia Vargas Montoya -> Sebastián Castro Leal
  (37, 18, 19, 'Renuncia', '2023-05-12 17:04:25'),  -- WS-OPE-01: Diana Herrera Meza -> Ricardo Jiménez Uribe
  (38, 18, 19, 'Renuncia', '2023-05-12 17:04:47'),  -- LT-OPE-01: Diana Herrera Meza -> Ricardo Jiménez Uribe
  (39, 26, 27, 'Renuncia', '2023-07-07 17:14:05'),  -- WS-COM-01: Viviana Becerra Prieto -> Fabián Salazar Cano
  (40, 26, 27, 'Renuncia', '2023-07-07 17:14:29'),  -- LT-COM-01: Viviana Becerra Prieto -> Fabián Salazar Cano
  (31, 2, 3, 'Despido', '2023-09-08 16:49:32'),  -- WS-TI-01: Carolina Rodríguez Ariza -> Julián Martínez Gaitán
  (32, 2, 3, 'Despido', '2023-09-08 16:49:39'),  -- WS-TI-02: Carolina Rodríguez Ariza -> Julián Martínez Gaitán
  (33, 2, 3, 'Despido', '2023-09-08 16:49:46'),  -- LT-TI-01: Carolina Rodríguez Ariza -> Julián Martínez Gaitán
  (34, 11, 12, 'Renuncia', '2023-11-24 17:54:15'),  -- WS-FIN-01: Sebastián Castro Leal -> Valentina Moreno Tamayo
  (35, 11, 12, 'Renuncia', '2023-11-24 17:54:18'),  -- WS-FIN-02: Sebastián Castro Leal -> Valentina Moreno Tamayo
  (36, 11, 12, 'Renuncia', '2023-11-24 17:54:31'),  -- LT-FIN-01: Sebastián Castro Leal -> Valentina Moreno Tamayo
  (37, 19, 20, 'Despido', '2024-01-19 15:44:16'),  -- WS-OPE-01: Ricardo Jiménez Uribe -> Catalina Pardo Lozano
  (38, 19, 20, 'Despido', '2024-01-19 15:44:32'),  -- LT-OPE-01: Ricardo Jiménez Uribe -> Catalina Pardo Lozano
  (40, 27, 28, 'Despido', '2024-03-08 16:04:09'),  -- LT-COM-01: Fabián Salazar Cano -> Laura Cortés Pinzón
  (39, 27, 28, 'Despido', '2024-03-08 16:04:35'),  -- WS-COM-01: Fabián Salazar Cano -> Laura Cortés Pinzón
  (32, 3, 5, 'Renuncia', '2024-04-26 18:04:35'),  -- WS-TI-02: Julián Martínez Gaitán -> Santiago Hernández Rincón
  (31, 3, 4, 'Renuncia', '2024-04-26 18:04:41'),  -- WS-TI-01: Julián Martínez Gaitán -> Marcela López Zapata
  (33, 3, 6, 'Renuncia', '2024-04-26 18:04:49'),  -- LT-TI-01: Julián Martínez Gaitán -> Paola García Prieto
  (34, 12, 13, 'Renuncia', '2024-06-14 16:34:00'),  -- WS-FIN-01: Valentina Moreno Tamayo -> Mauricio Rojas Osorio
  (35, 12, 14, 'Renuncia', '2024-06-14 16:34:06'),  -- WS-FIN-02: Valentina Moreno Tamayo -> Lorena Ortiz Barrios
  (36, 12, 15, 'Renuncia', '2024-06-14 16:34:43'),  -- LT-FIN-01: Valentina Moreno Tamayo -> Esteban Silva Bernal
  (37, 20, 21, 'Despido', '2024-08-30 17:24:22'),  -- WS-OPE-01: Catalina Pardo Lozano -> Héctor Arias Mejía
  (38, 20, 22, 'Despido', '2024-08-30 17:24:40'),  -- LT-OPE-01: Catalina Pardo Lozano -> Sandra Suárez Ariza
  (39, 28, 29, 'Renuncia', '2024-10-11 17:49:34'),  -- WS-COM-01: Laura Cortés Pinzón -> Gustavo Ríos Camacho
  (40, 28, 30, 'Renuncia', '2024-10-11 17:49:41');  -- LT-COM-01: Laura Cortés Pinzón -> Mónica Acosta Montoya

/* ---------------------------------------------------------------------
   11. inconsistencias  (32 registros)
   Registros que el sistema rechazó por incumplir alguna regla de negocio.
   --------------------------------------------------------------------- */
INSERT INTO inconsistencias (tabla_origen, operacion, registro_id, datos_rechazados, motivo, fecha_registro) VALUES
  ('asignaciones_activos', 'INSERT', NULL, 'activo_id=9, empleado_id=28, estado=Vigente', 'El empleado 28 está Inactivo; solo se pueden asignar activos vigentes a empleados Activos.', '2024-01-23 06:02:18'),
  ('asignaciones_activos', 'INSERT', NULL, 'activo_id=34, empleado_id=30, estado=Vigente', 'El activo 34 ya tiene una asignación Vigente; primero debe finalizarse la anterior.', '2024-03-13 06:20:08'),
  ('asignaciones_activos', 'INSERT', NULL, 'activo_id=WS-OPE-01, departamento=Recursos Humanos', 'No se encontró un empleado Activo en el departamento Recursos Humanos para reasignar el activo.', '2024-05-24 19:28:34'),
  ('activos_red', 'INSERT', NULL, 'direccion_ip=10.10.0.1, nombre_host=NUEVO-75', 'Dirección IP duplicada: 10.10.0.1 ya pertenece al activo RTR-CORE-01.', '2024-09-09 21:19:13'),
  ('empleados', 'INSERT', NULL, 'nombre=Registro duplicado, correo=ivan.pena@corpred.com.co', 'Correo duplicado: ivan.pena@corpred.com.co ya existe en la tabla empleados.', '2024-09-16 21:38:11'),
  ('mitigaciones', 'INSERT', NULL, 'incidente_id=10, analista_soc_id=3, fecha_resolucion=2025-11-17 12:19:13', 'La fecha de resolución es anterior a la fecha de detección del incidente 10 (2025-11-18 07:19:13).', '2024-10-09 01:58:44'),
  ('vulnerabilidades_conocidas', 'INSERT', NULL, 'cve_code=CVE-2025-9866, puntaje_cvss=12.0', 'El puntaje CVSS 12.0 está fuera del rango permitido (0.0 a 10.0).', '2024-11-01 21:30:16'),
  ('empleados', 'UPDATE', 22, 'id_empleado=22, estado=Inactivo, motivo_retiro=NULL', 'No se puede inactivar a un empleado sin indicar el motivo de retiro (Renuncia o Despido).', '2024-11-22 05:03:18'),
  ('asignaciones_activos', 'INSERT', NULL, 'activo_id=13, empleado_id=28, estado=Vigente', 'El empleado 28 está Inactivo; solo se pueden asignar activos vigentes a empleados Activos.', '2025-01-10 04:42:09'),
  ('asignaciones_activos', 'INSERT', NULL, 'activo_id=38, empleado_id=33, estado=Vigente', 'El activo 38 ya tiene una asignación Vigente; primero debe finalizarse la anterior.', '2025-03-01 16:28:13'),
  ('asignaciones_activos', 'INSERT', NULL, 'activo_id=WS-COM-01, departamento=Logística', 'No se encontró un empleado Activo en el departamento Logística para reasignar el activo.', '2025-03-18 09:09:02'),
  ('activos_red', 'INSERT', NULL, 'direccion_ip=10.20.20.12, nombre_host=NUEVO-28', 'Dirección IP duplicada: 10.20.20.12 ya pertenece al activo WS-FIN-02.', '2025-04-23 12:52:40'),
  ('empleados', 'INSERT', NULL, 'nombre=Registro duplicado, correo=rodrigo.valencia@corpred.com.co', 'Correo duplicado: rodrigo.valencia@corpred.com.co ya existe en la tabla empleados.', '2025-05-13 23:25:23'),
  ('mitigaciones', 'INSERT', NULL, 'incidente_id=12, analista_soc_id=20, fecha_resolucion=2025-12-12 01:57:03', 'La fecha de resolución es anterior a la fecha de detección del incidente 12 (2025-12-12 08:57:03).', '2025-07-01 21:36:55'),
  ('vulnerabilidades_conocidas', 'INSERT', NULL, 'cve_code=CVE-2025-5065, puntaje_cvss=15.3', 'El puntaje CVSS 15.3 está fuera del rango permitido (0.0 a 10.0).', '2025-07-18 14:11:35'),
  ('empleados', 'UPDATE', 25, 'id_empleado=25, estado=Inactivo, motivo_retiro=NULL', 'No se puede inactivar a un empleado sin indicar el motivo de retiro (Renuncia o Despido).', '2025-07-25 20:32:59'),
  ('asignaciones_activos', 'INSERT', NULL, 'activo_id=7, empleado_id=28, estado=Vigente', 'El empleado 28 está Inactivo; solo se pueden asignar activos vigentes a empleados Activos.', '2025-08-16 02:45:45'),
  ('asignaciones_activos', 'INSERT', NULL, 'activo_id=35, empleado_id=32, estado=Vigente', 'El activo 35 ya tiene una asignación Vigente; primero debe finalizarse la anterior.', '2025-08-19 02:49:02'),
  ('asignaciones_activos', 'INSERT', NULL, 'activo_id=WS-TI-02, departamento=Finanzas', 'No se encontró un empleado Activo en el departamento Finanzas para reasignar el activo.', '2025-10-10 07:31:46'),
  ('activos_red', 'INSERT', NULL, 'direccion_ip=10.10.0.252, nombre_host=NUEVO-97', 'Dirección IP duplicada: 10.10.0.252 ya pertenece al activo FW-DMZ-01.', '2025-10-13 17:58:27'),
  ('empleados', 'INSERT', NULL, 'nombre=Registro duplicado, correo=paola.garcia@corpred.com.co', 'Correo duplicado: paola.garcia@corpred.com.co ya existe en la tabla empleados.', '2025-12-25 19:04:51'),
  ('mitigaciones', 'INSERT', NULL, 'incidente_id=16, analista_soc_id=20, fecha_resolucion=2026-01-16 14:12:38', 'La fecha de resolución es anterior a la fecha de detección del incidente 16 (2026-01-16 23:12:38).', '2025-12-28 10:44:30'),
  ('vulnerabilidades_conocidas', 'INSERT', NULL, 'cve_code=CVE-2025-9294, puntaje_cvss=-1.0', 'El puntaje CVSS -1.0 está fuera del rango permitido (0.0 a 10.0).', '2026-01-20 10:20:12'),
  ('empleados', 'UPDATE', 36, 'id_empleado=36, estado=Inactivo, motivo_retiro=NULL', 'No se puede inactivar a un empleado sin indicar el motivo de retiro (Renuncia o Despido).', '2026-02-06 04:46:04'),
  ('asignaciones_activos', 'INSERT', NULL, 'activo_id=32, empleado_id=18, estado=Vigente', 'El empleado 18 está Inactivo; solo se pueden asignar activos vigentes a empleados Activos.', '2026-04-06 19:20:29'),
  ('asignaciones_activos', 'INSERT', NULL, 'activo_id=38, empleado_id=38, estado=Vigente', 'El activo 38 ya tiene una asignación Vigente; primero debe finalizarse la anterior.', '2026-05-13 07:22:03'),
  ('asignaciones_activos', 'INSERT', NULL, 'activo_id=WS-OPE-01, departamento=TI', 'No se encontró un empleado Activo en el departamento TI para reasignar el activo.', '2026-05-16 12:34:46'),
  ('activos_red', 'INSERT', NULL, 'direccion_ip=10.10.1.61, nombre_host=NUEVO-66', 'Dirección IP duplicada: 10.10.1.61 ya pertenece al activo SRV-BKP-01.', '2026-06-05 09:36:05'),
  ('empleados', 'INSERT', NULL, 'nombre=Registro duplicado, correo=felipe.diaz@corpred.com.co', 'Correo duplicado: felipe.diaz@corpred.com.co ya existe en la tabla empleados.', '2026-07-04 21:34:48'),
  ('mitigaciones', 'INSERT', NULL, 'incidente_id=27, analista_soc_id=8, fecha_resolucion=2026-07-05 22:41:40', 'La fecha de resolución es anterior a la fecha de detección del incidente 27 (2026-07-06 09:41:40).', '2026-09-16 14:09:20'),
  ('vulnerabilidades_conocidas', 'INSERT', NULL, 'cve_code=CVE-2025-9931, puntaje_cvss=10.5', 'El puntaje CVSS 10.5 está fuera del rango permitido (0.0 a 10.0).', '2026-09-30 13:30:22'),
  ('empleados', 'UPDATE', 8, 'id_empleado=8, estado=Inactivo, motivo_retiro=NULL', 'No se puede inactivar a un empleado sin indicar el motivo de retiro (Renuncia o Despido).', '2026-10-03 19:59:00');

COMMIT;

/* ---------------------------------------------------------------------
   VERIFICACIÓN: cantidad de registros por tabla (todas entre 30 y 40)
   --------------------------------------------------------------------- */
SELECT 'activos_red' AS tabla, COUNT(*) AS registros FROM activos_red
UNION ALL SELECT 'empleados',                  COUNT(*) FROM empleados
UNION ALL SELECT 'tipos_amenaza',              COUNT(*) FROM tipos_amenaza
UNION ALL SELECT 'analistas_soc',              COUNT(*) FROM analistas_soc
UNION ALL SELECT 'vulnerabilidades_conocidas', COUNT(*) FROM vulnerabilidades_conocidas
UNION ALL SELECT 'asignaciones_activos',       COUNT(*) FROM asignaciones_activos
UNION ALL SELECT 'incidentes',                 COUNT(*) FROM incidentes
UNION ALL SELECT 'mitigaciones',               COUNT(*) FROM mitigaciones
UNION ALL SELECT 'activo_vulnerabilidad',      COUNT(*) FROM activo_vulnerabilidad
UNION ALL SELECT 'auditoria',                  COUNT(*) FROM auditoria
UNION ALL SELECT 'inconsistencias',            COUNT(*) FROM inconsistencias
ORDER BY tabla;
