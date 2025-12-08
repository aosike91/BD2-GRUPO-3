-- ==========================================================
-- PROGRAMA DE BECAS EDUCATIVAS - FUNDACIÓN EDUCA PERÚ
-- SCRIPT DE PRUEBAS DE FUNCIONALIDADES
-- Requiere haber ejecutado previamente:
--   1) EDUCA_CreaciónBD_y_CargadeDatos.sql
--   2) EDUCA_Lógica.sql   (paquete EDU_PKG_GESTION y proc. BUSCAR_ALUMNO_*)
-- ==========================================================

SET SERVEROUTPUT ON;

-------------------------------------------------------------
-- PRUEBA 1: FLUJO PRINCIPAL
--   - Registrar postulación
--   - Asignar beca
-------------------------------------------------------------
DECLARE
    v_dni            VARCHAR2(15) := '12345678'; -- alumno de prueba
    v_id_postulacion NUMBER;
BEGIN
    DBMS_OUTPUT.PUT_LINE('--- 1. REGISTRANDO POSTULACIÓN ---');
    EDU_PKG_GESTION.REGISTRAR_POSTULACION(v_dni);

    -- Obtenemos el ID de postulación recién creado
    SELECT MAX(ID_POSTULACION)
    INTO   v_id_postulacion
    FROM   EDU_POSTULACION p
    JOIN   EDU_ESTUDIANTE e ON p.ID_ESTUDIANTE = e.ID_ESTUDIANTE
    WHERE  e.DNI = v_dni;

    DBMS_OUTPUT.PUT_LINE('Postulación creada con ID: ' || v_id_postulacion);

    DBMS_OUTPUT.PUT_LINE('--- 2. ASIGNANDO BECA ---');
    EDU_PKG_GESTION.ASIGNAR_BECA(
        p_id_postulacion  => v_id_postulacion,
        p_monto_mensual   => 1000,
        p_usuario_auditor => 'COORD_BECAS'
    );

    DBMS_OUTPUT.PUT_LINE('¡Éxito! Beca asignada y fondos descontados.');
END;
/
-- Consultas de verificación
PROMPT ==== Verificación de postulación y beca ====
SELECT ID_POSTULACION, ID_ESTUDIANTE, ESTADO, DOCUMENTOS_COMPLETOS
FROM   EDU_POSTULACION
ORDER BY ID_POSTULACION;

SELECT ID_BECA, ID_ESTUDIANTE, ESTADO, FECHA_INICIO, FECHA_FIN
FROM   EDU_BECA_ESTUDIANTE
ORDER BY ID_BECA, ID_ESTUDIANTE;

SELECT ID_FINANCIAMIENTO, MONTO_ASIGNADO, SALDO_DISPONIBLE
FROM   EDU_FINANCIAMIENTO;

-------------------------------------------------------------
-- PRUEBA 2: CONTROL DE TRANSACCIONES Y ROLLBACK
--   - Guarda auditoría válida
--   - Intenta registrar pago inválido (-500)
--   - Hace ROLLBACK al SAVEPOINT
-------------------------------------------------------------
DECLARE
    v_id_beca NUMBER := 1;
    v_id_est  NUMBER := 1;
BEGIN
    DBMS_OUTPUT.PUT_LINE('--- INICIO DE DEMOSTRACIÓN DE TRANSACCIONES ---');

    -- 1) Operación válida: auditoría de inicio
    INSERT INTO EDU_AUDITORIA (ID_AUDITORIA, ENTIDAD, OPERACION, DETALLE)
    VALUES (EDU_SEQ_AUDITORIA.NEXTVAL,
            'DEMO_TRX',
            'INICIO',
            'Iniciando proceso de pagos de prueba');

    -- Creamos SAVEPOINT
    SAVEPOINT punto_seguro;
    DBMS_OUTPUT.PUT_LINE('Paso 1 completado. SAVEPOINT creado.');

    DBMS_OUTPUT.PUT_LINE('Paso 2: Intentando registrar pago con monto inválido (-500)...');

    BEGIN
        INSERT INTO EDU_PAGO (ID_PAGO, ID_BECA, ID_ESTUDIANTE, MONTO, ESTADO)
        VALUES (EDU_SEQ_PAGO.NEXTVAL, v_id_beca, v_id_est, -500, 'ERROR');

        IF -500 < 0 THEN
            RAISE_APPLICATION_ERROR(-20099, 'Error: El monto no puede ser negativo.');
        END IF;

    EXCEPTION
        WHEN OTHERS THEN
            DBMS_OUTPUT.PUT_LINE('¡ALERTA DETECTADA!: ' || SQLERRM);
            DBMS_OUTPUT.PUT_LINE('>>> Ejecutando ROLLBACK TO punto_seguro...');
            ROLLBACK TO punto_seguro;
    END;

    COMMIT;
    DBMS_OUTPUT.PUT_LINE('--- FIN DE TRANSACCIÓN: auditoría guardada, pago inválido descartado. ---');
END;
/
-- Verificación de auditoría
PROMPT ==== Verificación de auditoría de transacciones ====
SELECT ID_AUDITORIA, ENTIDAD, OPERACION, DETALLE, FECHA_EVENTO
FROM   EDU_AUDITORIA
WHERE  ENTIDAD = 'DEMO_TRX'
ORDER BY ID_AUDITORIA;

-------------------------------------------------------------
-- PRUEBA 3: SEGURIDAD – INYECCIÓN SQL
--   - Compara procedimiento vulnerable vs seguro
-------------------------------------------------------------
BEGIN
    DBMS_OUTPUT.PUT_LINE('--- PRUEBA DE SEGURIDAD (INYECCIÓN SQL) ---');

    DBMS_OUTPUT.PUT_LINE('1) Intento de hackeo en procedimiento INSEGURO:');
    -- El truco ' OR '1'='1 intenta devolver todos los alumnos
    BUSCAR_ALUMNO_INSEGURO(''' OR ''1''=''1');

    DBMS_OUTPUT.PUT_LINE('-------------------------------------------');

    DBMS_OUTPUT.PUT_LINE('2) Intento de hackeo en procedimiento SEGURO:');
    -- Aquí solo busca literalmente ese texto; no devuelve filas
    BUSCAR_ALUMNO_SEGURO(''' OR ''1''=''1');

    DBMS_OUTPUT.PUT_LINE('--- FIN PRUEBA DE SEGURIDAD ---');
END;
/
