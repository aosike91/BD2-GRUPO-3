-- ==========================================================
-- PROGRAMA DE BECAS EDUCATIVAS - FUNDACIÓN EDUCA PERÚ
-- SCRIPT DE EXPORTACIÓN DEL ESQUEMA (DDL)
--   Genera el archivo: EDUCA_DDL.sql
-- ==========================================================

SET PAGESIZE 0
SET LONG 100000
SET LONGCHUNKSIZE 10000
SET LINESIZE 200
SET FEEDBACK OFF
SET ECHO OFF

SPOOL EDUCA_DDL.sql

SELECT DBMS_METADATA.GET_DDL(OBJECT_TYPE, OBJECT_NAME)
FROM   USER_OBJECTS
WHERE  OBJECT_NAME LIKE 'EDU_%'
AND    OBJECT_TYPE IN ('TABLE',
                       'SEQUENCE',
                       'INDEX',
                       'TRIGGER',
                       'VIEW',
                       'PACKAGE',
                       'PACKAGE BODY')
ORDER BY OBJECT_TYPE, OBJECT_NAME;

SPOOL OFF;

SET FEEDBACK ON
SET ECHO ON
