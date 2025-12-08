-- Agregar columna para controlar el saldo restante
ALTER TABLE EDU_FINANCIAMIENTO ADD SALDO_DISPONIBLE NUMBER(10,2);

-- Inicializar el saldo (por ahora igual al monto asignado)
UPDATE EDU_FINANCIAMIENTO SET SALDO_DISPONIBLE = MONTO_ASIGNADO;
COMMIT;

-- INSERTANDO DATOS DE PRUEBA
-- 1. Crear una Institución
INSERT INTO EDU_INSTITUCION (ID_INSTITUCION, NOMBRE, TIPO, DIRECCION, TELEFONO, EMAIL)
VALUES (EDU_SEQ_INSTITUCION.NEXTVAL, 'Colegio Mayor', 'Escuela', 'Av. Central 123', '555-1234', 'contacto@colegio.edu');

-- 2. Crear un Estudiante (DNI: 12345678)
INSERT INTO EDU_ESTUDIANTE (ID_ESTUDIANTE, DNI, NOMBRES, APELLIDOS, FECHA_NACIMIENTO, GENERO, ID_INSTITUCION, PROMEDIO_ACTUAL)
VALUES (EDU_SEQ_ESTUDIANTE.NEXTVAL, '12345678', 'Juan', 'Perez', TO_DATE('2005-01-01','YYYY-MM-DD'), 'M', 1, 16.5);

-- 3. Crear un Programa de Beca (ID: 1)
INSERT INTO EDU_BECA (ID_BECA, NOMBRE_PROGRAMA, TIPO, MONTO_TOTAL, DURACION_MESES)
VALUES (EDU_SEQ_BECA.NEXTVAL, 'Beca Excelencia 2025', 'Total', 10000, 10);

-- 4. Crear un Donante
INSERT INTO EDU_DONANTE (ID_DONANTE, NOMBRE, TIPO, CONTACTO)
VALUES (EDU_SEQ_DONANTE.NEXTVAL, 'Fundación Futuro', 'ONG', 'admin@futuro.org');

-- 5. Crear el FINANCIAMIENTO (Aquí está el dinero: 50,000 soles)
INSERT INTO EDU_FINANCIAMIENTO (ID_FINANCIAMIENTO, ID_DONANTE, ID_BECA, MONTO_ASIGNADO, SALDO_DISPONIBLE)
VALUES (EDU_SEQ_FINANCIAMIENTO.NEXTVAL, 1, 1, 50000, 50000);

COMMIT;
-- PASO 2

CREATE OR REPLACE PACKAGE EDU_PKG_GESTION AS
    -- Procedimiento 1: Registrar postulaciones
    PROCEDURE REGISTRAR_POSTULACION(
        p_dni IN VARCHAR2
    );

    -- Procedimiento 2: Registrar seguimiento
    PROCEDURE REGISTRAR_SEGUIMIENTO(
        p_dni IN VARCHAR2,
        p_periodo IN VARCHAR2,
        p_promedio IN NUMBER
    );

    -- Procedimiento 3: Asignar Beca (CON CONTROL DE CONCURRENCIA)
    PROCEDURE ASIGNAR_BECA(
        p_id_postulacion IN NUMBER,
        p_monto_mensual IN NUMBER,
        p_usuario_auditor IN VARCHAR2
    );
END EDU_PKG_GESTION;
/

CREATE OR REPLACE PACKAGE BODY EDU_PKG_GESTION AS

    -- 1. REGISTRAR POSTULACIÓN
    PROCEDURE REGISTRAR_POSTULACION(p_dni IN VARCHAR2) IS
        v_id_est NUMBER;
    BEGIN
        SELECT ID_ESTUDIANTE INTO v_id_est FROM EDU_ESTUDIANTE WHERE DNI = p_dni;
        
        INSERT INTO EDU_POSTULACION (ID_POSTULACION, ID_ESTUDIANTE, FECHA_POSTULACION, ESTADO, DOCUMENTOS_COMPLETOS)
        VALUES (EDU_SEQ_POSTULACION.NEXTVAL, v_id_est, SYSDATE, 'PENDIENTE', 'N');
        
        COMMIT;
    EXCEPTION
        WHEN NO_DATA_FOUND THEN
            RAISE_APPLICATION_ERROR(-20001, 'El estudiante con DNI '||p_dni||' no existe.');
    END;

    -- 2. REGISTRAR SEGUIMIENTO
    PROCEDURE REGISTRAR_SEGUIMIENTO(p_dni IN VARCHAR2, p_periodo IN VARCHAR2, p_promedio IN NUMBER) IS
        v_id_est NUMBER;
    BEGIN
        SELECT ID_ESTUDIANTE INTO v_id_est FROM EDU_ESTUDIANTE WHERE DNI = p_dni;
        
        INSERT INTO EDU_SEGUIMIENTO (ID_SEGUIMIENTO, ID_ESTUDIANTE, PERIODO, PROMEDIO, ESTADO_ACADEMICO)
        VALUES (EDU_SEQ_SEGUIMIENTO.NEXTVAL, v_id_est, p_periodo, p_promedio, 
                CASE WHEN p_promedio >= 13 THEN 'APROBADO' ELSE 'OBSERVADO' END);
        COMMIT;
    END;

    -- 3. ASIGNAR BECA
    PROCEDURE ASIGNAR_BECA(
        p_id_postulacion IN NUMBER,
        p_monto_mensual IN NUMBER,
        p_usuario_auditor IN VARCHAR2
    ) IS
        v_id_fin NUMBER;
        v_saldo NUMBER;
        v_id_est NUMBER;
        v_id_beca NUMBER := 1; 
    BEGIN
        -- A. Obtener datos de la postulación
        SELECT ID_ESTUDIANTE INTO v_id_est 
        FROM EDU_POSTULACION WHERE ID_POSTULACION = p_id_postulacion;

        -- B. ESTRATEGIA DE BLOQUEO EN DOS PASOS
        -- Paso 1: Identificar el financiamiento disponible (Lectura)
        BEGIN
            SELECT ID_FINANCIAMIENTO 
            INTO v_id_fin
            FROM (
                SELECT ID_FINANCIAMIENTO
                FROM EDU_FINANCIAMIENTO
                WHERE ID_BECA = v_id_beca AND SALDO_DISPONIBLE >= p_monto_mensual
                ORDER BY FECHA_APORTE ASC
            )
            WHERE ROWNUM = 1; -- Tomamos solo el primero
        EXCEPTION
            WHEN NO_DATA_FOUND THEN
                 RAISE_APPLICATION_ERROR(-20002, 'No hay fondos disponibles suficientes.');
        END;

        -- Paso 2: Aplicar el candado (Concurrencia)
        -- Si otra sesión tiene esta fila, el sistema ESPERA aquí.
        SELECT SALDO_DISPONIBLE
        INTO v_saldo
        FROM EDU_FINANCIAMIENTO
        WHERE ID_FINANCIAMIENTO = v_id_fin
        FOR UPDATE; -- <--- Bloqueo Pesimista para evitar doble gasto

        -- C. Descontar el dinero
        UPDATE EDU_FINANCIAMIENTO 
        SET SALDO_DISPONIBLE = SALDO_DISPONIBLE - p_monto_mensual
        WHERE ID_FINANCIAMIENTO = v_id_fin;

        -- D. Aprobar la postulación
        UPDATE EDU_POSTULACION 
        SET ESTADO = 'APROBADA' 
        WHERE ID_POSTULACION = p_id_postulacion;

        -- E. Programar el pago
        INSERT INTO EDU_PAGO (ID_PAGO, ID_BECA, ID_ESTUDIANTE, MONTO, ESTADO)
        VALUES (EDU_SEQ_PAGO.NEXTVAL, v_id_beca, v_id_est, p_monto_mensual, 'PENDIENTE');

        -- F. Auditoría
        INSERT INTO EDU_AUDITORIA (ID_AUDITORIA, ENTIDAD, OPERACION, USUARIO, DETALLE)
        VALUES (EDU_SEQ_AUDITORIA.NEXTVAL, 'EDU_BECA', 'ASIGNACION', p_usuario_auditor, 'Beca asignada con fondo '||v_id_fin);

        COMMIT;
        
    EXCEPTION
        WHEN NO_DATA_FOUND THEN
            ROLLBACK;
            RAISE_APPLICATION_ERROR(-20002, 'No se encontró el registro para procesar.');
        WHEN OTHERS THEN
            ROLLBACK;
            RAISE;
    END;

END EDU_PKG_GESTION;
/
-- Paso 3

SET SERVEROUTPUT ON;
DECLARE
    v_dni VARCHAR2(15) := '12345678'; -- El alumno que creamos
    v_id_postulacion NUMBER;
BEGIN
    DBMS_OUTPUT.PUT_LINE('--- 1. REGISTRANDO POSTULACIÓN ---');
    EDU_PKG_GESTION.REGISTRAR_POSTULACION(v_dni);
    
    -- Obtenemos el ID generado para usarlo en el siguiente paso
    SELECT MAX(ID_POSTULACION) INTO v_id_postulacion FROM EDU_POSTULACION;
    DBMS_OUTPUT.PUT_LINE('Postulación creada con ID: ' || v_id_postulacion);

    DBMS_OUTPUT.PUT_LINE('--- 2. EJECUTANDO ASIGNACIÓN DE BECA ---');
    -- Intentamos asignar una beca de 1,000 soles mensuales
    EDU_PKG_GESTION.ASIGNAR_BECA(
        p_id_postulacion => v_id_postulacion, 
        p_monto_mensual => 1000, 
        p_usuario_auditor => 'COORD_BECAS'
    );
    
    DBMS_OUTPUT.PUT_LINE('¡Éxito! Beca asignada y fondos descontados.');
END;
/
-- Verificación

SELECT 'FINANCIAMIENTO' AS TABLA, SALDO_DISPONIBLE FROM EDU_FINANCIAMIENTO
UNION ALL
SELECT 'PAGO GENERADO', MONTO FROM EDU_PAGO WHERE ESTADO = 'PENDIENTE';

-- Paso 4

SET SERVEROUTPUT ON;
DECLARE
    v_id_beca NUMBER := 1; 
    v_id_est NUMBER := 1; 
BEGIN
    DBMS_OUTPUT.PUT_LINE('--- INICIO DE DEMOSTRACIÓN DE TRANSACCIONES ---');
    
    -- 1. Operación válida: Registramos una auditoría de inicio
    -- Esto SÍ queremos que se guarde.
    INSERT INTO EDU_AUDITORIA (ID_AUDITORIA, ENTIDAD, OPERACION, DETALLE)
    VALUES (EDU_SEQ_AUDITORIA.NEXTVAL, 'DEMO_TRX', 'INICIO', 'Iniciando proceso de pagos');
    
    -- Creamos un punto de restauración aquí
    SAVEPOINT punto_seguro;
    DBMS_OUTPUT.PUT_LINE('Paso 1 completado. SAVEPOINT creado.');

    -- 2. Operación Errónea: Intentamos registrar un pago con monto negativo
    DBMS_OUTPUT.PUT_LINE('Intentando registrar pago con monto inválido (-500)...');
    
    BEGIN
        INSERT INTO EDU_PAGO (ID_PAGO, ID_BECA, ID_ESTUDIANTE, MONTO, ESTADO)
        VALUES (EDU_SEQ_PAGO.NEXTVAL, v_id_beca, v_id_est, -500, 'ERROR');
        
        -- Validación de negocio simulada
        IF -500 < 0 THEN
            RAISE_APPLICATION_ERROR(-20099, 'Error: El monto no puede ser negativo.');
        END IF;
        
    EXCEPTION
        WHEN OTHERS THEN
            DBMS_OUTPUT.PUT_LINE('¡ALERTA DETECTADA!: ' || SQLERRM);
            DBMS_OUTPUT.PUT_LINE('>>> Ejecutando ROLLBACK TO punto_seguro...');
            -- Aquí está la magia: Deshacemos el pago malo, pero la auditoría del paso 1 se queda.
            ROLLBACK TO punto_seguro;
    END;
    
    COMMIT; 
    DBMS_OUTPUT.PUT_LINE('--- FIN DE TRANSACCIÓN: Se guardó la auditoría, se descartó el error. ---');
END;
/
--Paso 5

-- 1. PROCEDIMIENTO VULNERABLE (MALO)
-- Permite que le pasen código malicioso porque usa concatenación (||)
CREATE OR REPLACE PROCEDURE BUSCAR_ALUMNO_INSEGURO (p_dni IN VARCHAR2) IS
    v_sql VARCHAR2(200);
    v_nombre VARCHAR2(100);
    TYPE c_type IS REF CURSOR;
    c_res c_type;
BEGIN
    v_sql := 'SELECT NOMBRES FROM EDU_ESTUDIANTE WHERE DNI = ''' || p_dni || '''';
    OPEN c_res FOR v_sql;
    LOOP
        FETCH c_res INTO v_nombre;
        EXIT WHEN c_res%NOTFOUND;
        DBMS_OUTPUT.PUT_LINE('[VULNERABLE] Alumno encontrado: ' || v_nombre);
    END LOOP;
    CLOSE c_res;
END;
/

-- 2. PROCEDIMIENTO SEGURO (BUENO)
-- Usa Bind Variables (Oracle separa el dato del código)
CREATE OR REPLACE PROCEDURE BUSCAR_ALUMNO_SEGURO (p_dni IN VARCHAR2) IS
BEGIN
    FOR r IN (SELECT NOMBRES FROM EDU_ESTUDIANTE WHERE DNI = p_dni) LOOP
        DBMS_OUTPUT.PUT_LINE('[SEGURO] Alumno encontrado: ' || r.NOMBRES);
    END LOOP;
END;
/

SET SERVEROUTPUT ON;
BEGIN
    DBMS_OUTPUT.PUT_LINE('--- PRUEBA DE SEGURIDAD (INYECCIÓN SQL) ---');
    
    DBMS_OUTPUT.PUT_LINE('1. Intento de hackeo en procedimiento INSEGURO:');
    -- El truco ' OR '1'='1 engaña al código para mostrar TODOS los alumnos
    BUSCAR_ALUMNO_INSEGURO(''' OR ''1''=''1'); 
    
    DBMS_OUTPUT.PUT_LINE('-------------------------------------------');
    
    DBMS_OUTPUT.PUT_LINE('2. Intento de hackeo en procedimiento SEGURO:');
    -- Aquí Oracle busca literalmente un DNI llamado " OR '1'='1", que no existe.
    BUSCAR_ALUMNO_SEGURO(''' OR ''1''=''1');
    
    DBMS_OUTPUT.PUT_LINE('--- FIN DE PRUEBA ---');
END;
/