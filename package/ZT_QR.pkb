CREATE OR REPLACE PACKAGE BODY ZT_QR AS

    --C O N S T A N T S

    --data mode
    cNumericMode CONSTANT pls_integer := 1; 
    cAlphanumericMode CONSTANT pls_integer := 2; 
    cByteMode CONSTANT pls_integer := 3; 
    cDoublebyteMode CONSTANT pls_integer := 4; 


    --V A R I A B L E S
    
    --debug
    gpbDebug boolean := false;
    gpnDebugLevel pls_integer := 1;
    
    --mode and version
    gpnMode pls_integer;
    gpnVersion pls_integer;

    --Error Correction Code Words and Block Information
    TYPE r_err_cor IS RECORD(
        total_no_of_data_cw pls_integer,
        ec_cw_per_block pls_integer,
        blocks_in_g1 pls_integer,
        cw_in_g1 pls_integer,
        blocks_in_g2 pls_integer,
        cw_in_g2 pls_integer);
    
    TYPE t_err_cor IS TABLE OF r_err_cor INDEX BY varchar2(10);
    
    gprErrCorInfo t_err_cor;

    --logs and antilogs
    TYPE t_log_anti IS TABLE OF pls_integer INDEX BY pls_integer;
    gprLog t_log_anti;
    gprAntiLog t_log_anti;

    --matrix
    TYPE t_row IS TABLE OF varchar2(1);
    TYPE t_column IS TABLE OF t_row;
    TYPE t_masking IS TABLE OF t_column INDEX BY pls_integer;
    
    gprMatrix t_column := t_column();
    gprMasking t_masking; 



--DEBUG FUNCS AND PROCS
PROCEDURE p_debug(
    p_text varchar2,
    p_level pls_integer default 1,
    p_new_line boolean default true) IS
BEGIN
    if gpbDebug and p_level <= gpnDebugLevel then
        if p_new_line then
            DBMS_OUTPUT.put_line(p_text);
        else
            DBMS_OUTPUT.put(p_text);
        end if;
    end if;
END;


PROCEDURE p_dbms_output_matrix(
    p_matrix t_column,
    p_level pls_integer default 1) IS
    
    lcQR varchar2(200);
    
BEGIN
    FOR t IN 1 .. p_matrix.count LOOP
        lcQR := null;
        FOR p IN 1 .. p_matrix.count LOOP
            lcQR := lcQR || nvl(p_matrix(t)(p), 'X');
        END LOOP;
        p_debug(lcQR, p_level);
    END LOOP;
END;


--UTILITY FUNCS AND PROCS
FUNCTION bitor(p1 number, p2 number) RETURN number IS
BEGIN
  RETURN p1 - bitand(p1, p2) + p2;
END;

FUNCTION bitxor(p1 number, p2 number) RETURN number IS
BEGIN
  RETURN bitor(p1, p2) - bitand(p1, p2);
END;

FUNCTION bin2dec(binval varchar2) RETURN pls_integer IS
  result            NUMBER := 0;
BEGIN
  FOR t IN 1 .. length(binval) LOOP
     result := (result * 2) + to_number(substr(binval, t, 1));
  END LOOP;
  
  RETURN result;
END bin2dec;

FUNCTION f_integer_2_binary(p_integer pls_integer) RETURN varchar2 IS
    lcBinary varchar2(100);
BEGIN
    SELECT LISTAGG(SIGN(BITAND(p_integer, POWER(2, LEVEL-1))),'') WITHIN GROUP(ORDER BY LEVEL DESC)
    INTO lcBinary
    FROM dual
    CONNECT BY POWER(2, LEVEL-1) <= p_integer;

    RETURN lcBinary;
END;




--INIT FUNCS AND PROCS
PROCEDURE p_fill_log_antilog IS
    lnVal pls_integer;
    lnPrevVal pls_integer;
BEGIN
    FOR t IN 0 .. 255 LOOP
        if t = 0 then
            lnVal := 1;
        else
            lnVal := lnPrevVal * 2;
            if lnVal > 255 then
                lnVal := bitxor(lnVal, 285);
            end if;
        end if;
        
        gprLog(t) := lnVal;
        gprAntiLog(lnVal) := t;
        
        lnPrevVal := lnVal;
        
        p_debug('Log for ' || t || ': ' || gprLog(t), 4);
        
    END LOOP;
END;

FUNCTION f_matrix_size RETURN pls_integer IS
BEGIN
    --minimal matrix size is 21x21 module; every next version is 4 modules larger
    RETURN ((gpnVersion - 1) * 4) + 21;
END;



PROCEDURE p_init_matrix IS

    TYPE t_col IS TABLE OF pls_integer;
    TYPE t_alignment_pos IS TABLE OF t_col;
    lrAlignPos t_alignment_pos := t_alignment_pos();
    
    lcModule varchar2(1);

    PROCEDURE p_add_finder(p_column pls_integer, p_row pls_integer) IS
    BEGIN
        --outer black square 
        FOR t IN 0 .. 6 LOOP
            gprMatrix(p_column + t)(p_row) := '3';
            gprMatrix(p_column + t)(p_row + 6) := '3';
            gprMatrix(p_column)(p_row + t) := '3';
            gprMatrix(p_column + 6)(p_row + t) := '3';
        END LOOP;

        --inner white square
        FOR t IN 0 .. 4 LOOP
            gprMatrix(p_column + 1 + t)(p_row + 1) := '2';
            gprMatrix(p_column + 1 + t)(p_row + 1 + 4) := '2';
            gprMatrix(p_column + 1)(p_row + 1 + t) := '2';
            gprMatrix(p_column + 1 + 4)(p_row + 1 + t) := '2';
        END LOOP;

        --inner black square
        FOR t IN 0 .. 2 LOOP
            FOR p IN 0 .. 2 LOOP
                gprMatrix(p_column + 2 + t)(p_row + 2 + p) := '3';
            END LOOP;
        END LOOP;

    END;

    PROCEDURE p_init_alignment IS
    BEGIN
        lrAlignPos.delete;
        lrAlignPos.extend(40);
        
        lrAlignPos(1) := t_col(0);
        lrAlignPos(2) := t_col(6, 18);
        lrAlignPos(3) := t_col(6, 22);
        lrAlignPos(4) := t_col(6, 26);
        lrAlignPos(5) := t_col(6, 30);
        lrAlignPos(6) := t_col(6, 34);
        lrAlignPos(7) := t_col(6, 22, 38);
        lrAlignPos(8) := t_col(6, 24, 42);
        lrAlignPos(9) := t_col(6, 26, 46);
        lrAlignPos(10) := t_col(6, 28, 50);
        lrAlignPos(11) := t_col(6, 30, 54);
        lrAlignPos(12) := t_col(6, 32, 58);
        lrAlignPos(13) := t_col(6, 34, 62);
        lrAlignPos(14) := t_col(6, 26, 46, 66);
        lrAlignPos(15) := t_col(6, 26, 48, 70);
        lrAlignPos(16) := t_col(6, 26, 50, 74);
        lrAlignPos(17) := t_col(6, 30, 54, 78);
        lrAlignPos(18) := t_col(6, 30, 56, 82);
        lrAlignPos(19) := t_col(6, 30, 58, 86);
        lrAlignPos(20) := t_col(6, 34, 62, 90);
        lrAlignPos(21) := t_col(6, 28, 50, 72, 94);
        lrAlignPos(22) := t_col(6, 26, 50, 74, 98);
        lrAlignPos(23) := t_col(6, 30, 54, 78, 102);
        lrAlignPos(24) := t_col(6, 28, 54, 80, 106);
        lrAlignPos(25) := t_col(6, 32, 58, 84, 110);
        lrAlignPos(26) := t_col(6, 30, 58, 86, 114);
        lrAlignPos(27) := t_col(6, 34, 62, 90, 118);
        lrAlignPos(28) := t_col(6, 26, 50, 74, 98, 122 );
        lrAlignPos(29) := t_col(6, 30, 54, 78, 102, 126);
        lrAlignPos(30) := t_col(6, 26, 52, 78, 104, 130 );
        lrAlignPos(31) := t_col(6, 30, 56, 82, 108, 134 );
        lrAlignPos(32) := t_col(6, 34, 60, 86, 112, 138 );
        lrAlignPos(33) := t_col(6, 30, 58, 86, 114, 142 );
        lrAlignPos(34) := t_col(6, 34, 62, 90, 118, 146 );
        lrAlignPos(35) := t_col(6, 30, 54, 78, 102, 126, 150);
        lrAlignPos(36) := t_col(6, 24, 50, 76, 102, 128, 154);
        lrAlignPos(37) := t_col(6, 28, 54, 80, 106, 132, 158);
        lrAlignPos(38) := t_col(6, 32, 58, 84, 110, 136, 162);
        lrAlignPos(39) := t_col(6, 26, 54, 82, 110, 138, 166);
        lrAlignPos(40) := t_col(6, 30, 58, 86, 114, 142, 170);
        
    END;

    PROCEDURE p_add_alignment(p_column pls_integer, p_row pls_integer) IS
    BEGIN
        --check if coordinates are OK and alignment is on matrix
        if p_column - 2 < 1 or p_column + 2 > f_matrix_size or p_row - 2 < 1 or p_row + 2 > f_matrix_size then
            p_debug('Alignment on ' || p_column || ', ' || p_row || ' is outside of matrix! Skipping...', 2);
            RETURN;
        end if;
    
        --first check if overlap with existing finders; if overlaps then do not draw finder
        FOR t IN p_column - 2 .. p_column + 2 LOOP
            FOR p IN p_row - 2 .. p_row + 2 LOOP
                if gprMatrix(p)(t) is not null then
                    p_debug('Alignment on ' || p_column || ', ' || p_row || ' overlaps with finder! Skipping...', 2);
                    RETURN;
                end if;
            END LOOP;
        END LOOP;

        --draw alignment
        --outer black square 
        FOR t IN 0 .. 4 LOOP
            gprMatrix(p_row - 2)(p_column - 2 + t) := '3';
            gprMatrix(p_row - 2 + t)(p_column - 2) := '3';
            gprMatrix(p_row + 2)(p_column - 2 + t) := '3';
            gprMatrix(p_row - 2 + t)(p_column + 2) := '3';
        END LOOP;

        --inner white square and center module
        FOR t IN 0 .. 2 LOOP
            FOR p IN 0 .. 2 LOOP
                gprMatrix(p_row - 1 + t)(p_column - 1 + p) := '2';
            END LOOP;
        END LOOP;
        gprMatrix(p_row)(p_column) := '3';
        
        
    END;

BEGIN
    p_debug('Matrix size: ' || f_matrix_size || 'x' || f_matrix_size || ' modules', 2);

    --collection initialization
    gprMatrix.delete;
    
    gprMatrix.extend(f_matrix_size);
    FOR t IN 1 .. f_matrix_size LOOP
        gprMatrix(t) := t_row();
        gprMatrix(t).extend(f_matrix_size);
    END LOOP;
    
    
    --add Finder Patterns (3x)
    p_add_finder(1, 1);
    p_add_finder(f_matrix_size - 6, 1);
    p_add_finder(1, f_matrix_size - 6);


    --add Separators
    FOR t IN 0 .. 7 LOOP
        --upper left
        gprMatrix(1 + t)(1 + 7) := '2';
        gprMatrix(1 + 7)(1 + t) := '2';
        
        --lower left
        gprMatrix(f_matrix_size - 7 + t)(1 + 7) := '2';
        gprMatrix(f_matrix_size - 7)(1 + t) := '2';
        
        --upper right
        gprMatrix(1 + t)(f_matrix_size - 7) := '2';
        gprMatrix(1 + 7)(f_matrix_size - 7 + t) := '2';
    END LOOP;
    

    --add Alignment Patterns (for versions larger then 1)
    p_init_alignment;
    
    if gpnVersion > 1 then
        FOR t IN 1 .. lrAlignPos(gpnVersion).count LOOP
            FOR p IN 1 .. lrAlignPos(gpnVersion).count LOOP
                p_add_alignment(lrAlignPos(gpnVersion)(t) + 1, lrAlignPos(gpnVersion)(p) + 1);
            END LOOP;
        END LOOP;
    end if;
    
    
    --Timing Patterns
    FOR t IN 9 .. f_matrix_size - 8 LOOP
        if t mod 2 <> 0 then
            lcModule := '3';  --first module is black, then white, then black...
        else
            lcModule := '2';
        end if;

        gprMatrix(7)(t) := lcModule;
        gprMatrix(t)(7) := lcModule;
    END LOOP;
    
    
    --Dark Module
    gprMatrix(f_matrix_size - 7)(9) := '3';
    
    --Reserved Areas (Format Information Area, Version Information Area)
    --will be filled with actual values later
    
    --Format Information Area, placeholder values are dots
    FOR t IN 1 .. 9 LOOP
        if gprMatrix(9)(t) is null then 
            gprMatrix(9)(t) := '.';
        end if;

        if gprMatrix(t)(9) is null then 
            gprMatrix(t)(9) := '.';
        end if;
    END LOOP;

    FOR t IN 1 .. 8 LOOP
        if gprMatrix(f_matrix_size - t + 1)(9) is null then 
            gprMatrix(f_matrix_size - t + 1)(9) := '.';
        end if;

        if gprMatrix(9)(f_matrix_size - t + 1) is null then 
            gprMatrix(9)(f_matrix_size - t + 1) := '.';
        end if;
    END LOOP;

    --Version Information Area, placeholder values are *
    --it aplies only to versions 7 and larger
    if gpnVersion >= 7 then
        FOR t IN 1 .. 6 LOOP
            gprMatrix(f_matrix_size - 8)(t) := '*';
            gprMatrix(f_matrix_size - 9)(t) := '*';
            gprMatrix(f_matrix_size - 10)(t) := '*';

            gprMatrix(t)(f_matrix_size - 8) := '*';
            gprMatrix(t)(f_matrix_size - 9) := '*';
            gprMatrix(t)(f_matrix_size - 10) := '*';
            
        END LOOP;
    end if;
END;


PROCEDURE p_fill_err_cor IS
BEGIN
    gprErrCorInfo('1-L').total_no_of_data_cw := 19; gprErrCorInfo('1-L').ec_cw_per_block := 7; gprErrCorInfo('1-L').blocks_in_g1 := 1; gprErrCorInfo('1-L').cw_in_g1 := 19; gprErrCorInfo('1-L').blocks_in_g2 := null; gprErrCorInfo('1-L').cw_in_g2 := null; 
    gprErrCorInfo('1-M').total_no_of_data_cw := 16; gprErrCorInfo('1-M').ec_cw_per_block := 10; gprErrCorInfo('1-M').blocks_in_g1 := 1; gprErrCorInfo('1-M').cw_in_g1 := 16; gprErrCorInfo('1-M').blocks_in_g2 := null; gprErrCorInfo('1-M').cw_in_g2 := null; 
    gprErrCorInfo('1-Q').total_no_of_data_cw := 13; gprErrCorInfo('1-Q').ec_cw_per_block := 13; gprErrCorInfo('1-Q').blocks_in_g1 := 1; gprErrCorInfo('1-Q').cw_in_g1 := 13; gprErrCorInfo('1-Q').blocks_in_g2 := null; gprErrCorInfo('1-Q').cw_in_g2 := null; 
    gprErrCorInfo('1-H').total_no_of_data_cw := 9; gprErrCorInfo('1-H').ec_cw_per_block := 17; gprErrCorInfo('1-H').blocks_in_g1 := 1; gprErrCorInfo('1-H').cw_in_g1 := 9; gprErrCorInfo('1-H').blocks_in_g2 := null; gprErrCorInfo('1-H').cw_in_g2 := null; 
    gprErrCorInfo('2-L').total_no_of_data_cw := 34; gprErrCorInfo('2-L').ec_cw_per_block := 10; gprErrCorInfo('2-L').blocks_in_g1 := 1; gprErrCorInfo('2-L').cw_in_g1 := 34; gprErrCorInfo('2-L').blocks_in_g2 := null; gprErrCorInfo('2-L').cw_in_g2 := null; 
    gprErrCorInfo('2-M').total_no_of_data_cw := 28; gprErrCorInfo('2-M').ec_cw_per_block := 16; gprErrCorInfo('2-M').blocks_in_g1 := 1; gprErrCorInfo('2-M').cw_in_g1 := 28; gprErrCorInfo('2-M').blocks_in_g2 := null; gprErrCorInfo('2-M').cw_in_g2 := null; 
    gprErrCorInfo('2-Q').total_no_of_data_cw := 22; gprErrCorInfo('2-Q').ec_cw_per_block := 22; gprErrCorInfo('2-Q').blocks_in_g1 := 1; gprErrCorInfo('2-Q').cw_in_g1 := 22; gprErrCorInfo('2-Q').blocks_in_g2 := null; gprErrCorInfo('2-Q').cw_in_g2 := null; 
    gprErrCorInfo('2-H').total_no_of_data_cw := 16; gprErrCorInfo('2-H').ec_cw_per_block := 28; gprErrCorInfo('2-H').blocks_in_g1 := 1; gprErrCorInfo('2-H').cw_in_g1 := 16; gprErrCorInfo('2-H').blocks_in_g2 := null; gprErrCorInfo('2-H').cw_in_g2 := null; 
    gprErrCorInfo('3-L').total_no_of_data_cw := 55; gprErrCorInfo('3-L').ec_cw_per_block := 15; gprErrCorInfo('3-L').blocks_in_g1 := 1; gprErrCorInfo('3-L').cw_in_g1 := 55; gprErrCorInfo('3-L').blocks_in_g2 := null; gprErrCorInfo('3-L').cw_in_g2 := null; 
    gprErrCorInfo('3-M').total_no_of_data_cw := 44; gprErrCorInfo('3-M').ec_cw_per_block := 26; gprErrCorInfo('3-M').blocks_in_g1 := 1; gprErrCorInfo('3-M').cw_in_g1 := 44; gprErrCorInfo('3-M').blocks_in_g2 := null; gprErrCorInfo('3-M').cw_in_g2 := null; 
    gprErrCorInfo('3-Q').total_no_of_data_cw := 34; gprErrCorInfo('3-Q').ec_cw_per_block := 18; gprErrCorInfo('3-Q').blocks_in_g1 := 2; gprErrCorInfo('3-Q').cw_in_g1 := 17; gprErrCorInfo('3-Q').blocks_in_g2 := null; gprErrCorInfo('3-Q').cw_in_g2 := null; 
    gprErrCorInfo('3-H').total_no_of_data_cw := 26; gprErrCorInfo('3-H').ec_cw_per_block := 22; gprErrCorInfo('3-H').blocks_in_g1 := 2; gprErrCorInfo('3-H').cw_in_g1 := 13; gprErrCorInfo('3-H').blocks_in_g2 := null; gprErrCorInfo('3-H').cw_in_g2 := null; 
    gprErrCorInfo('4-L').total_no_of_data_cw := 80; gprErrCorInfo('4-L').ec_cw_per_block := 20; gprErrCorInfo('4-L').blocks_in_g1 := 1; gprErrCorInfo('4-L').cw_in_g1 := 80; gprErrCorInfo('4-L').blocks_in_g2 := null; gprErrCorInfo('4-L').cw_in_g2 := null; 
    gprErrCorInfo('4-M').total_no_of_data_cw := 64; gprErrCorInfo('4-M').ec_cw_per_block := 18; gprErrCorInfo('4-M').blocks_in_g1 := 2; gprErrCorInfo('4-M').cw_in_g1 := 32; gprErrCorInfo('4-M').blocks_in_g2 := null; gprErrCorInfo('4-M').cw_in_g2 := null; 
    gprErrCorInfo('4-Q').total_no_of_data_cw := 48; gprErrCorInfo('4-Q').ec_cw_per_block := 26; gprErrCorInfo('4-Q').blocks_in_g1 := 2; gprErrCorInfo('4-Q').cw_in_g1 := 24; gprErrCorInfo('4-Q').blocks_in_g2 := null; gprErrCorInfo('4-Q').cw_in_g2 := null; 
    gprErrCorInfo('4-H').total_no_of_data_cw := 36; gprErrCorInfo('4-H').ec_cw_per_block := 16; gprErrCorInfo('4-H').blocks_in_g1 := 4; gprErrCorInfo('4-H').cw_in_g1 := 9; gprErrCorInfo('4-H').blocks_in_g2 := null; gprErrCorInfo('4-H').cw_in_g2 := null; 
    gprErrCorInfo('5-L').total_no_of_data_cw := 108; gprErrCorInfo('5-L').ec_cw_per_block := 26; gprErrCorInfo('5-L').blocks_in_g1 := 1; gprErrCorInfo('5-L').cw_in_g1 := 108; gprErrCorInfo('5-L').blocks_in_g2 := null; gprErrCorInfo('5-L').cw_in_g2 := null; 
    gprErrCorInfo('5-M').total_no_of_data_cw := 86; gprErrCorInfo('5-M').ec_cw_per_block := 24; gprErrCorInfo('5-M').blocks_in_g1 := 2; gprErrCorInfo('5-M').cw_in_g1 := 43; gprErrCorInfo('5-M').blocks_in_g2 := null; gprErrCorInfo('5-M').cw_in_g2 := null; 
    gprErrCorInfo('5-Q').total_no_of_data_cw := 62; gprErrCorInfo('5-Q').ec_cw_per_block := 18; gprErrCorInfo('5-Q').blocks_in_g1 := 2; gprErrCorInfo('5-Q').cw_in_g1 := 15; gprErrCorInfo('5-Q').blocks_in_g2 := 2; gprErrCorInfo('5-Q').cw_in_g2 := 16; 
    gprErrCorInfo('5-H').total_no_of_data_cw := 46; gprErrCorInfo('5-H').ec_cw_per_block := 22; gprErrCorInfo('5-H').blocks_in_g1 := 2; gprErrCorInfo('5-H').cw_in_g1 := 11; gprErrCorInfo('5-H').blocks_in_g2 := 2; gprErrCorInfo('5-H').cw_in_g2 := 12; 
    gprErrCorInfo('6-L').total_no_of_data_cw := 136; gprErrCorInfo('6-L').ec_cw_per_block := 18; gprErrCorInfo('6-L').blocks_in_g1 := 2; gprErrCorInfo('6-L').cw_in_g1 := 68; gprErrCorInfo('6-L').blocks_in_g2 := null; gprErrCorInfo('6-L').cw_in_g2 := null; 
    gprErrCorInfo('6-M').total_no_of_data_cw := 108; gprErrCorInfo('6-M').ec_cw_per_block := 16; gprErrCorInfo('6-M').blocks_in_g1 := 4; gprErrCorInfo('6-M').cw_in_g1 := 27; gprErrCorInfo('6-M').blocks_in_g2 := null; gprErrCorInfo('6-M').cw_in_g2 := null; 
    gprErrCorInfo('6-Q').total_no_of_data_cw := 76; gprErrCorInfo('6-Q').ec_cw_per_block := 24; gprErrCorInfo('6-Q').blocks_in_g1 := 4; gprErrCorInfo('6-Q').cw_in_g1 := 19; gprErrCorInfo('6-Q').blocks_in_g2 := null; gprErrCorInfo('6-Q').cw_in_g2 := null; 
    gprErrCorInfo('6-H').total_no_of_data_cw := 60; gprErrCorInfo('6-H').ec_cw_per_block := 28; gprErrCorInfo('6-H').blocks_in_g1 := 4; gprErrCorInfo('6-H').cw_in_g1 := 15; gprErrCorInfo('6-H').blocks_in_g2 := null; gprErrCorInfo('6-H').cw_in_g2 := null; 
    gprErrCorInfo('7-L').total_no_of_data_cw := 156; gprErrCorInfo('7-L').ec_cw_per_block := 20; gprErrCorInfo('7-L').blocks_in_g1 := 2; gprErrCorInfo('7-L').cw_in_g1 := 78; gprErrCorInfo('7-L').blocks_in_g2 := null; gprErrCorInfo('7-L').cw_in_g2 := null; 
    gprErrCorInfo('7-M').total_no_of_data_cw := 124; gprErrCorInfo('7-M').ec_cw_per_block := 18; gprErrCorInfo('7-M').blocks_in_g1 := 4; gprErrCorInfo('7-M').cw_in_g1 := 31; gprErrCorInfo('7-M').blocks_in_g2 := null; gprErrCorInfo('7-M').cw_in_g2 := null; 
    gprErrCorInfo('7-Q').total_no_of_data_cw := 88; gprErrCorInfo('7-Q').ec_cw_per_block := 18; gprErrCorInfo('7-Q').blocks_in_g1 := 2; gprErrCorInfo('7-Q').cw_in_g1 := 14; gprErrCorInfo('7-Q').blocks_in_g2 := 4; gprErrCorInfo('7-Q').cw_in_g2 := 15; 
    gprErrCorInfo('7-H').total_no_of_data_cw := 66; gprErrCorInfo('7-H').ec_cw_per_block := 26; gprErrCorInfo('7-H').blocks_in_g1 := 4; gprErrCorInfo('7-H').cw_in_g1 := 13; gprErrCorInfo('7-H').blocks_in_g2 := 1; gprErrCorInfo('7-H').cw_in_g2 := 14; 
    gprErrCorInfo('8-L').total_no_of_data_cw := 194; gprErrCorInfo('8-L').ec_cw_per_block := 24; gprErrCorInfo('8-L').blocks_in_g1 := 2; gprErrCorInfo('8-L').cw_in_g1 := 97; gprErrCorInfo('8-L').blocks_in_g2 := null; gprErrCorInfo('8-L').cw_in_g2 := null; 
    gprErrCorInfo('8-M').total_no_of_data_cw := 154; gprErrCorInfo('8-M').ec_cw_per_block := 22; gprErrCorInfo('8-M').blocks_in_g1 := 2; gprErrCorInfo('8-M').cw_in_g1 := 38; gprErrCorInfo('8-M').blocks_in_g2 := 2; gprErrCorInfo('8-M').cw_in_g2 := 39; 
    gprErrCorInfo('8-Q').total_no_of_data_cw := 110; gprErrCorInfo('8-Q').ec_cw_per_block := 22; gprErrCorInfo('8-Q').blocks_in_g1 := 4; gprErrCorInfo('8-Q').cw_in_g1 := 18; gprErrCorInfo('8-Q').blocks_in_g2 := 2; gprErrCorInfo('8-Q').cw_in_g2 := 19; 
    gprErrCorInfo('8-H').total_no_of_data_cw := 86; gprErrCorInfo('8-H').ec_cw_per_block := 26; gprErrCorInfo('8-H').blocks_in_g1 := 4; gprErrCorInfo('8-H').cw_in_g1 := 14; gprErrCorInfo('8-H').blocks_in_g2 := 2; gprErrCorInfo('8-H').cw_in_g2 := 15; 
    gprErrCorInfo('9-L').total_no_of_data_cw := 232; gprErrCorInfo('9-L').ec_cw_per_block := 30; gprErrCorInfo('9-L').blocks_in_g1 := 2; gprErrCorInfo('9-L').cw_in_g1 := 116; gprErrCorInfo('9-L').blocks_in_g2 := null; gprErrCorInfo('9-L').cw_in_g2 := null; 
    gprErrCorInfo('9-M').total_no_of_data_cw := 182; gprErrCorInfo('9-M').ec_cw_per_block := 22; gprErrCorInfo('9-M').blocks_in_g1 := 3; gprErrCorInfo('9-M').cw_in_g1 := 36; gprErrCorInfo('9-M').blocks_in_g2 := 2; gprErrCorInfo('9-M').cw_in_g2 := 37; 
    gprErrCorInfo('9-Q').total_no_of_data_cw := 132; gprErrCorInfo('9-Q').ec_cw_per_block := 20; gprErrCorInfo('9-Q').blocks_in_g1 := 4; gprErrCorInfo('9-Q').cw_in_g1 := 16; gprErrCorInfo('9-Q').blocks_in_g2 := 4; gprErrCorInfo('9-Q').cw_in_g2 := 17; 
    gprErrCorInfo('9-H').total_no_of_data_cw := 100; gprErrCorInfo('9-H').ec_cw_per_block := 24; gprErrCorInfo('9-H').blocks_in_g1 := 4; gprErrCorInfo('9-H').cw_in_g1 := 12; gprErrCorInfo('9-H').blocks_in_g2 := 4; gprErrCorInfo('9-H').cw_in_g2 := 13; 
    gprErrCorInfo('10-L').total_no_of_data_cw := 274; gprErrCorInfo('10-L').ec_cw_per_block := 18; gprErrCorInfo('10-L').blocks_in_g1 := 2; gprErrCorInfo('10-L').cw_in_g1 := 68; gprErrCorInfo('10-L').blocks_in_g2 := 2; gprErrCorInfo('10-L').cw_in_g2 := 69; 
    gprErrCorInfo('10-M').total_no_of_data_cw := 216; gprErrCorInfo('10-M').ec_cw_per_block := 26; gprErrCorInfo('10-M').blocks_in_g1 := 4; gprErrCorInfo('10-M').cw_in_g1 := 43; gprErrCorInfo('10-M').blocks_in_g2 := 1; gprErrCorInfo('10-M').cw_in_g2 := 44; 
    gprErrCorInfo('10-Q').total_no_of_data_cw := 154; gprErrCorInfo('10-Q').ec_cw_per_block := 24; gprErrCorInfo('10-Q').blocks_in_g1 := 6; gprErrCorInfo('10-Q').cw_in_g1 := 19; gprErrCorInfo('10-Q').blocks_in_g2 := 2; gprErrCorInfo('10-Q').cw_in_g2 := 20; 
    gprErrCorInfo('10-H').total_no_of_data_cw := 122; gprErrCorInfo('10-H').ec_cw_per_block := 28; gprErrCorInfo('10-H').blocks_in_g1 := 6; gprErrCorInfo('10-H').cw_in_g1 := 15; gprErrCorInfo('10-H').blocks_in_g2 := 2; gprErrCorInfo('10-H').cw_in_g2 := 16; 
    gprErrCorInfo('11-L').total_no_of_data_cw := 324; gprErrCorInfo('11-L').ec_cw_per_block := 20; gprErrCorInfo('11-L').blocks_in_g1 := 4; gprErrCorInfo('11-L').cw_in_g1 := 81; gprErrCorInfo('11-L').blocks_in_g2 := null; gprErrCorInfo('11-L').cw_in_g2 := null; 
    gprErrCorInfo('11-M').total_no_of_data_cw := 254; gprErrCorInfo('11-M').ec_cw_per_block := 30; gprErrCorInfo('11-M').blocks_in_g1 := 1; gprErrCorInfo('11-M').cw_in_g1 := 50; gprErrCorInfo('11-M').blocks_in_g2 := 4; gprErrCorInfo('11-M').cw_in_g2 := 51; 
    gprErrCorInfo('11-Q').total_no_of_data_cw := 180; gprErrCorInfo('11-Q').ec_cw_per_block := 28; gprErrCorInfo('11-Q').blocks_in_g1 := 4; gprErrCorInfo('11-Q').cw_in_g1 := 22; gprErrCorInfo('11-Q').blocks_in_g2 := 4; gprErrCorInfo('11-Q').cw_in_g2 := 23; 
    gprErrCorInfo('11-H').total_no_of_data_cw := 140; gprErrCorInfo('11-H').ec_cw_per_block := 24; gprErrCorInfo('11-H').blocks_in_g1 := 3; gprErrCorInfo('11-H').cw_in_g1 := 12; gprErrCorInfo('11-H').blocks_in_g2 := 8; gprErrCorInfo('11-H').cw_in_g2 := 13; 
    gprErrCorInfo('12-L').total_no_of_data_cw := 370; gprErrCorInfo('12-L').ec_cw_per_block := 24; gprErrCorInfo('12-L').blocks_in_g1 := 2; gprErrCorInfo('12-L').cw_in_g1 := 92; gprErrCorInfo('12-L').blocks_in_g2 := 2; gprErrCorInfo('12-L').cw_in_g2 := 93; 
    gprErrCorInfo('12-M').total_no_of_data_cw := 290; gprErrCorInfo('12-M').ec_cw_per_block := 22; gprErrCorInfo('12-M').blocks_in_g1 := 6; gprErrCorInfo('12-M').cw_in_g1 := 36; gprErrCorInfo('12-M').blocks_in_g2 := 2; gprErrCorInfo('12-M').cw_in_g2 := 37; 
    gprErrCorInfo('12-Q').total_no_of_data_cw := 206; gprErrCorInfo('12-Q').ec_cw_per_block := 26; gprErrCorInfo('12-Q').blocks_in_g1 := 4; gprErrCorInfo('12-Q').cw_in_g1 := 20; gprErrCorInfo('12-Q').blocks_in_g2 := 6; gprErrCorInfo('12-Q').cw_in_g2 := 21; 
    gprErrCorInfo('12-H').total_no_of_data_cw := 158; gprErrCorInfo('12-H').ec_cw_per_block := 28; gprErrCorInfo('12-H').blocks_in_g1 := 7; gprErrCorInfo('12-H').cw_in_g1 := 14; gprErrCorInfo('12-H').blocks_in_g2 := 4; gprErrCorInfo('12-H').cw_in_g2 := 15; 
    gprErrCorInfo('13-L').total_no_of_data_cw := 428; gprErrCorInfo('13-L').ec_cw_per_block := 26; gprErrCorInfo('13-L').blocks_in_g1 := 4; gprErrCorInfo('13-L').cw_in_g1 := 107; gprErrCorInfo('13-L').blocks_in_g2 := null; gprErrCorInfo('13-L').cw_in_g2 := null; 
    gprErrCorInfo('13-M').total_no_of_data_cw := 334; gprErrCorInfo('13-M').ec_cw_per_block := 22; gprErrCorInfo('13-M').blocks_in_g1 := 8; gprErrCorInfo('13-M').cw_in_g1 := 37; gprErrCorInfo('13-M').blocks_in_g2 := 1; gprErrCorInfo('13-M').cw_in_g2 := 38; 
    gprErrCorInfo('13-Q').total_no_of_data_cw := 244; gprErrCorInfo('13-Q').ec_cw_per_block := 24; gprErrCorInfo('13-Q').blocks_in_g1 := 8; gprErrCorInfo('13-Q').cw_in_g1 := 20; gprErrCorInfo('13-Q').blocks_in_g2 := 4; gprErrCorInfo('13-Q').cw_in_g2 := 21; 
    gprErrCorInfo('13-H').total_no_of_data_cw := 180; gprErrCorInfo('13-H').ec_cw_per_block := 22; gprErrCorInfo('13-H').blocks_in_g1 := 12; gprErrCorInfo('13-H').cw_in_g1 := 11; gprErrCorInfo('13-H').blocks_in_g2 := 4; gprErrCorInfo('13-H').cw_in_g2 := 12; 
    gprErrCorInfo('14-L').total_no_of_data_cw := 461; gprErrCorInfo('14-L').ec_cw_per_block := 30; gprErrCorInfo('14-L').blocks_in_g1 := 3; gprErrCorInfo('14-L').cw_in_g1 := 115; gprErrCorInfo('14-L').blocks_in_g2 := 1; gprErrCorInfo('14-L').cw_in_g2 := 116; 
    gprErrCorInfo('14-M').total_no_of_data_cw := 365; gprErrCorInfo('14-M').ec_cw_per_block := 24; gprErrCorInfo('14-M').blocks_in_g1 := 4; gprErrCorInfo('14-M').cw_in_g1 := 40; gprErrCorInfo('14-M').blocks_in_g2 := 5; gprErrCorInfo('14-M').cw_in_g2 := 41; 
    gprErrCorInfo('14-Q').total_no_of_data_cw := 261; gprErrCorInfo('14-Q').ec_cw_per_block := 20; gprErrCorInfo('14-Q').blocks_in_g1 := 11; gprErrCorInfo('14-Q').cw_in_g1 := 16; gprErrCorInfo('14-Q').blocks_in_g2 := 5; gprErrCorInfo('14-Q').cw_in_g2 := 17; 
    gprErrCorInfo('14-H').total_no_of_data_cw := 197; gprErrCorInfo('14-H').ec_cw_per_block := 24; gprErrCorInfo('14-H').blocks_in_g1 := 11; gprErrCorInfo('14-H').cw_in_g1 := 12; gprErrCorInfo('14-H').blocks_in_g2 := 5; gprErrCorInfo('14-H').cw_in_g2 := 13; 
    gprErrCorInfo('15-L').total_no_of_data_cw := 523; gprErrCorInfo('15-L').ec_cw_per_block := 22; gprErrCorInfo('15-L').blocks_in_g1 := 5; gprErrCorInfo('15-L').cw_in_g1 := 87; gprErrCorInfo('15-L').blocks_in_g2 := 1; gprErrCorInfo('15-L').cw_in_g2 := 88; 
    gprErrCorInfo('15-M').total_no_of_data_cw := 415; gprErrCorInfo('15-M').ec_cw_per_block := 24; gprErrCorInfo('15-M').blocks_in_g1 := 5; gprErrCorInfo('15-M').cw_in_g1 := 41; gprErrCorInfo('15-M').blocks_in_g2 := 5; gprErrCorInfo('15-M').cw_in_g2 := 42; 
    gprErrCorInfo('15-Q').total_no_of_data_cw := 295; gprErrCorInfo('15-Q').ec_cw_per_block := 30; gprErrCorInfo('15-Q').blocks_in_g1 := 5; gprErrCorInfo('15-Q').cw_in_g1 := 24; gprErrCorInfo('15-Q').blocks_in_g2 := 7; gprErrCorInfo('15-Q').cw_in_g2 := 25; 
    gprErrCorInfo('15-H').total_no_of_data_cw := 223; gprErrCorInfo('15-H').ec_cw_per_block := 24; gprErrCorInfo('15-H').blocks_in_g1 := 11; gprErrCorInfo('15-H').cw_in_g1 := 12; gprErrCorInfo('15-H').blocks_in_g2 := 7; gprErrCorInfo('15-H').cw_in_g2 := 13; 
    gprErrCorInfo('16-L').total_no_of_data_cw := 589; gprErrCorInfo('16-L').ec_cw_per_block := 24; gprErrCorInfo('16-L').blocks_in_g1 := 5; gprErrCorInfo('16-L').cw_in_g1 := 98; gprErrCorInfo('16-L').blocks_in_g2 := 1; gprErrCorInfo('16-L').cw_in_g2 := 99; 
    gprErrCorInfo('16-M').total_no_of_data_cw := 453; gprErrCorInfo('16-M').ec_cw_per_block := 28; gprErrCorInfo('16-M').blocks_in_g1 := 7; gprErrCorInfo('16-M').cw_in_g1 := 45; gprErrCorInfo('16-M').blocks_in_g2 := 3; gprErrCorInfo('16-M').cw_in_g2 := 46; 
    gprErrCorInfo('16-Q').total_no_of_data_cw := 325; gprErrCorInfo('16-Q').ec_cw_per_block := 24; gprErrCorInfo('16-Q').blocks_in_g1 := 15; gprErrCorInfo('16-Q').cw_in_g1 := 19; gprErrCorInfo('16-Q').blocks_in_g2 := 2; gprErrCorInfo('16-Q').cw_in_g2 := 20; 
    gprErrCorInfo('16-H').total_no_of_data_cw := 253; gprErrCorInfo('16-H').ec_cw_per_block := 30; gprErrCorInfo('16-H').blocks_in_g1 := 3; gprErrCorInfo('16-H').cw_in_g1 := 15; gprErrCorInfo('16-H').blocks_in_g2 := 13; gprErrCorInfo('16-H').cw_in_g2 := 16; 
    gprErrCorInfo('17-L').total_no_of_data_cw := 647; gprErrCorInfo('17-L').ec_cw_per_block := 28; gprErrCorInfo('17-L').blocks_in_g1 := 1; gprErrCorInfo('17-L').cw_in_g1 := 107; gprErrCorInfo('17-L').blocks_in_g2 := 5; gprErrCorInfo('17-L').cw_in_g2 := 108; 
    gprErrCorInfo('17-M').total_no_of_data_cw := 507; gprErrCorInfo('17-M').ec_cw_per_block := 28; gprErrCorInfo('17-M').blocks_in_g1 := 10; gprErrCorInfo('17-M').cw_in_g1 := 46; gprErrCorInfo('17-M').blocks_in_g2 := 1; gprErrCorInfo('17-M').cw_in_g2 := 47; 
    gprErrCorInfo('17-Q').total_no_of_data_cw := 367; gprErrCorInfo('17-Q').ec_cw_per_block := 28; gprErrCorInfo('17-Q').blocks_in_g1 := 1; gprErrCorInfo('17-Q').cw_in_g1 := 22; gprErrCorInfo('17-Q').blocks_in_g2 := 15; gprErrCorInfo('17-Q').cw_in_g2 := 23; 
    gprErrCorInfo('17-H').total_no_of_data_cw := 283; gprErrCorInfo('17-H').ec_cw_per_block := 28; gprErrCorInfo('17-H').blocks_in_g1 := 2; gprErrCorInfo('17-H').cw_in_g1 := 14; gprErrCorInfo('17-H').blocks_in_g2 := 17; gprErrCorInfo('17-H').cw_in_g2 := 15; 
    gprErrCorInfo('18-L').total_no_of_data_cw := 721; gprErrCorInfo('18-L').ec_cw_per_block := 30; gprErrCorInfo('18-L').blocks_in_g1 := 5; gprErrCorInfo('18-L').cw_in_g1 := 120; gprErrCorInfo('18-L').blocks_in_g2 := 1; gprErrCorInfo('18-L').cw_in_g2 := 121; 
    gprErrCorInfo('18-M').total_no_of_data_cw := 563; gprErrCorInfo('18-M').ec_cw_per_block := 26; gprErrCorInfo('18-M').blocks_in_g1 := 9; gprErrCorInfo('18-M').cw_in_g1 := 43; gprErrCorInfo('18-M').blocks_in_g2 := 4; gprErrCorInfo('18-M').cw_in_g2 := 44; 
    gprErrCorInfo('18-Q').total_no_of_data_cw := 397; gprErrCorInfo('18-Q').ec_cw_per_block := 28; gprErrCorInfo('18-Q').blocks_in_g1 := 17; gprErrCorInfo('18-Q').cw_in_g1 := 22; gprErrCorInfo('18-Q').blocks_in_g2 := 1; gprErrCorInfo('18-Q').cw_in_g2 := 23; 
    gprErrCorInfo('18-H').total_no_of_data_cw := 313; gprErrCorInfo('18-H').ec_cw_per_block := 28; gprErrCorInfo('18-H').blocks_in_g1 := 2; gprErrCorInfo('18-H').cw_in_g1 := 14; gprErrCorInfo('18-H').blocks_in_g2 := 19; gprErrCorInfo('18-H').cw_in_g2 := 15; 
    gprErrCorInfo('19-L').total_no_of_data_cw := 795; gprErrCorInfo('19-L').ec_cw_per_block := 28; gprErrCorInfo('19-L').blocks_in_g1 := 3; gprErrCorInfo('19-L').cw_in_g1 := 113; gprErrCorInfo('19-L').blocks_in_g2 := 4; gprErrCorInfo('19-L').cw_in_g2 := 114; 
    gprErrCorInfo('19-M').total_no_of_data_cw := 627; gprErrCorInfo('19-M').ec_cw_per_block := 26; gprErrCorInfo('19-M').blocks_in_g1 := 3; gprErrCorInfo('19-M').cw_in_g1 := 44; gprErrCorInfo('19-M').blocks_in_g2 := 11; gprErrCorInfo('19-M').cw_in_g2 := 45; 
    gprErrCorInfo('19-Q').total_no_of_data_cw := 445; gprErrCorInfo('19-Q').ec_cw_per_block := 26; gprErrCorInfo('19-Q').blocks_in_g1 := 17; gprErrCorInfo('19-Q').cw_in_g1 := 21; gprErrCorInfo('19-Q').blocks_in_g2 := 4; gprErrCorInfo('19-Q').cw_in_g2 := 22; 
    gprErrCorInfo('19-H').total_no_of_data_cw := 341; gprErrCorInfo('19-H').ec_cw_per_block := 26; gprErrCorInfo('19-H').blocks_in_g1 := 9; gprErrCorInfo('19-H').cw_in_g1 := 13; gprErrCorInfo('19-H').blocks_in_g2 := 16; gprErrCorInfo('19-H').cw_in_g2 := 14; 
    gprErrCorInfo('20-L').total_no_of_data_cw := 861; gprErrCorInfo('20-L').ec_cw_per_block := 28; gprErrCorInfo('20-L').blocks_in_g1 := 3; gprErrCorInfo('20-L').cw_in_g1 := 107; gprErrCorInfo('20-L').blocks_in_g2 := 5; gprErrCorInfo('20-L').cw_in_g2 := 108; 
    gprErrCorInfo('20-M').total_no_of_data_cw := 669; gprErrCorInfo('20-M').ec_cw_per_block := 26; gprErrCorInfo('20-M').blocks_in_g1 := 3; gprErrCorInfo('20-M').cw_in_g1 := 41; gprErrCorInfo('20-M').blocks_in_g2 := 13; gprErrCorInfo('20-M').cw_in_g2 := 42; 
    gprErrCorInfo('20-Q').total_no_of_data_cw := 485; gprErrCorInfo('20-Q').ec_cw_per_block := 30; gprErrCorInfo('20-Q').blocks_in_g1 := 15; gprErrCorInfo('20-Q').cw_in_g1 := 24; gprErrCorInfo('20-Q').blocks_in_g2 := 5; gprErrCorInfo('20-Q').cw_in_g2 := 25; 
    gprErrCorInfo('20-H').total_no_of_data_cw := 385; gprErrCorInfo('20-H').ec_cw_per_block := 28; gprErrCorInfo('20-H').blocks_in_g1 := 15; gprErrCorInfo('20-H').cw_in_g1 := 15; gprErrCorInfo('20-H').blocks_in_g2 := 10; gprErrCorInfo('20-H').cw_in_g2 := 16; 
    gprErrCorInfo('21-L').total_no_of_data_cw := 932; gprErrCorInfo('21-L').ec_cw_per_block := 28; gprErrCorInfo('21-L').blocks_in_g1 := 4; gprErrCorInfo('21-L').cw_in_g1 := 116; gprErrCorInfo('21-L').blocks_in_g2 := 4; gprErrCorInfo('21-L').cw_in_g2 := 117; 
    gprErrCorInfo('21-M').total_no_of_data_cw := 714; gprErrCorInfo('21-M').ec_cw_per_block := 26; gprErrCorInfo('21-M').blocks_in_g1 := 17; gprErrCorInfo('21-M').cw_in_g1 := 42; gprErrCorInfo('21-M').blocks_in_g2 := null; gprErrCorInfo('21-M').cw_in_g2 := null; 
    gprErrCorInfo('21-Q').total_no_of_data_cw := 512; gprErrCorInfo('21-Q').ec_cw_per_block := 28; gprErrCorInfo('21-Q').blocks_in_g1 := 17; gprErrCorInfo('21-Q').cw_in_g1 := 22; gprErrCorInfo('21-Q').blocks_in_g2 := 6; gprErrCorInfo('21-Q').cw_in_g2 := 23; 
    gprErrCorInfo('21-H').total_no_of_data_cw := 406; gprErrCorInfo('21-H').ec_cw_per_block := 30; gprErrCorInfo('21-H').blocks_in_g1 := 19; gprErrCorInfo('21-H').cw_in_g1 := 16; gprErrCorInfo('21-H').blocks_in_g2 := 6; gprErrCorInfo('21-H').cw_in_g2 := 17; 
    gprErrCorInfo('22-L').total_no_of_data_cw := 1006; gprErrCorInfo('22-L').ec_cw_per_block := 28; gprErrCorInfo('22-L').blocks_in_g1 := 2; gprErrCorInfo('22-L').cw_in_g1 := 111; gprErrCorInfo('22-L').blocks_in_g2 := 7; gprErrCorInfo('22-L').cw_in_g2 := 112; 
    gprErrCorInfo('22-M').total_no_of_data_cw := 782; gprErrCorInfo('22-M').ec_cw_per_block := 28; gprErrCorInfo('22-M').blocks_in_g1 := 17; gprErrCorInfo('22-M').cw_in_g1 := 46; gprErrCorInfo('22-M').blocks_in_g2 := null; gprErrCorInfo('22-M').cw_in_g2 := null; 
    gprErrCorInfo('22-Q').total_no_of_data_cw := 568; gprErrCorInfo('22-Q').ec_cw_per_block := 30; gprErrCorInfo('22-Q').blocks_in_g1 := 7; gprErrCorInfo('22-Q').cw_in_g1 := 24; gprErrCorInfo('22-Q').blocks_in_g2 := 16; gprErrCorInfo('22-Q').cw_in_g2 := 25; 
    gprErrCorInfo('22-H').total_no_of_data_cw := 442; gprErrCorInfo('22-H').ec_cw_per_block := 24; gprErrCorInfo('22-H').blocks_in_g1 := 34; gprErrCorInfo('22-H').cw_in_g1 := 13; gprErrCorInfo('22-H').blocks_in_g2 := null; gprErrCorInfo('22-H').cw_in_g2 := null; 
    gprErrCorInfo('23-L').total_no_of_data_cw := 1094; gprErrCorInfo('23-L').ec_cw_per_block := 30; gprErrCorInfo('23-L').blocks_in_g1 := 4; gprErrCorInfo('23-L').cw_in_g1 := 121; gprErrCorInfo('23-L').blocks_in_g2 := 5; gprErrCorInfo('23-L').cw_in_g2 := 122; 
    gprErrCorInfo('23-M').total_no_of_data_cw := 860; gprErrCorInfo('23-M').ec_cw_per_block := 28; gprErrCorInfo('23-M').blocks_in_g1 := 4; gprErrCorInfo('23-M').cw_in_g1 := 47; gprErrCorInfo('23-M').blocks_in_g2 := 14; gprErrCorInfo('23-M').cw_in_g2 := 48; 
    gprErrCorInfo('23-Q').total_no_of_data_cw := 614; gprErrCorInfo('23-Q').ec_cw_per_block := 30; gprErrCorInfo('23-Q').blocks_in_g1 := 11; gprErrCorInfo('23-Q').cw_in_g1 := 24; gprErrCorInfo('23-Q').blocks_in_g2 := 14; gprErrCorInfo('23-Q').cw_in_g2 := 25; 
    gprErrCorInfo('23-H').total_no_of_data_cw := 464; gprErrCorInfo('23-H').ec_cw_per_block := 30; gprErrCorInfo('23-H').blocks_in_g1 := 16; gprErrCorInfo('23-H').cw_in_g1 := 15; gprErrCorInfo('23-H').blocks_in_g2 := 14; gprErrCorInfo('23-H').cw_in_g2 := 16; 
    gprErrCorInfo('24-L').total_no_of_data_cw := 1174; gprErrCorInfo('24-L').ec_cw_per_block := 30; gprErrCorInfo('24-L').blocks_in_g1 := 6; gprErrCorInfo('24-L').cw_in_g1 := 117; gprErrCorInfo('24-L').blocks_in_g2 := 4; gprErrCorInfo('24-L').cw_in_g2 := 118; 
    gprErrCorInfo('24-M').total_no_of_data_cw := 914; gprErrCorInfo('24-M').ec_cw_per_block := 28; gprErrCorInfo('24-M').blocks_in_g1 := 6; gprErrCorInfo('24-M').cw_in_g1 := 45; gprErrCorInfo('24-M').blocks_in_g2 := 14; gprErrCorInfo('24-M').cw_in_g2 := 46; 
    gprErrCorInfo('24-Q').total_no_of_data_cw := 664; gprErrCorInfo('24-Q').ec_cw_per_block := 30; gprErrCorInfo('24-Q').blocks_in_g1 := 11; gprErrCorInfo('24-Q').cw_in_g1 := 24; gprErrCorInfo('24-Q').blocks_in_g2 := 16; gprErrCorInfo('24-Q').cw_in_g2 := 25; 
    gprErrCorInfo('24-H').total_no_of_data_cw := 514; gprErrCorInfo('24-H').ec_cw_per_block := 30; gprErrCorInfo('24-H').blocks_in_g1 := 30; gprErrCorInfo('24-H').cw_in_g1 := 16; gprErrCorInfo('24-H').blocks_in_g2 := 2; gprErrCorInfo('24-H').cw_in_g2 := 17; 
    gprErrCorInfo('25-L').total_no_of_data_cw := 1276; gprErrCorInfo('25-L').ec_cw_per_block := 26; gprErrCorInfo('25-L').blocks_in_g1 := 8; gprErrCorInfo('25-L').cw_in_g1 := 106; gprErrCorInfo('25-L').blocks_in_g2 := 4; gprErrCorInfo('25-L').cw_in_g2 := 107; 
    gprErrCorInfo('25-M').total_no_of_data_cw := 1000; gprErrCorInfo('25-M').ec_cw_per_block := 28; gprErrCorInfo('25-M').blocks_in_g1 := 8; gprErrCorInfo('25-M').cw_in_g1 := 47; gprErrCorInfo('25-M').blocks_in_g2 := 13; gprErrCorInfo('25-M').cw_in_g2 := 48; 
    gprErrCorInfo('25-Q').total_no_of_data_cw := 718; gprErrCorInfo('25-Q').ec_cw_per_block := 30; gprErrCorInfo('25-Q').blocks_in_g1 := 7; gprErrCorInfo('25-Q').cw_in_g1 := 24; gprErrCorInfo('25-Q').blocks_in_g2 := 22; gprErrCorInfo('25-Q').cw_in_g2 := 25; 
    gprErrCorInfo('25-H').total_no_of_data_cw := 538; gprErrCorInfo('25-H').ec_cw_per_block := 30; gprErrCorInfo('25-H').blocks_in_g1 := 22; gprErrCorInfo('25-H').cw_in_g1 := 15; gprErrCorInfo('25-H').blocks_in_g2 := 13; gprErrCorInfo('25-H').cw_in_g2 := 16; 
    gprErrCorInfo('26-L').total_no_of_data_cw := 1370; gprErrCorInfo('26-L').ec_cw_per_block := 28; gprErrCorInfo('26-L').blocks_in_g1 := 10; gprErrCorInfo('26-L').cw_in_g1 := 114; gprErrCorInfo('26-L').blocks_in_g2 := 2; gprErrCorInfo('26-L').cw_in_g2 := 115; 
    gprErrCorInfo('26-M').total_no_of_data_cw := 1062; gprErrCorInfo('26-M').ec_cw_per_block := 28; gprErrCorInfo('26-M').blocks_in_g1 := 19; gprErrCorInfo('26-M').cw_in_g1 := 46; gprErrCorInfo('26-M').blocks_in_g2 := 4; gprErrCorInfo('26-M').cw_in_g2 := 47; 
    gprErrCorInfo('26-Q').total_no_of_data_cw := 754; gprErrCorInfo('26-Q').ec_cw_per_block := 28; gprErrCorInfo('26-Q').blocks_in_g1 := 28; gprErrCorInfo('26-Q').cw_in_g1 := 22; gprErrCorInfo('26-Q').blocks_in_g2 := 6; gprErrCorInfo('26-Q').cw_in_g2 := 23; 
    gprErrCorInfo('26-H').total_no_of_data_cw := 596; gprErrCorInfo('26-H').ec_cw_per_block := 30; gprErrCorInfo('26-H').blocks_in_g1 := 33; gprErrCorInfo('26-H').cw_in_g1 := 16; gprErrCorInfo('26-H').blocks_in_g2 := 4; gprErrCorInfo('26-H').cw_in_g2 := 17; 
    gprErrCorInfo('27-L').total_no_of_data_cw := 1468; gprErrCorInfo('27-L').ec_cw_per_block := 30; gprErrCorInfo('27-L').blocks_in_g1 := 8; gprErrCorInfo('27-L').cw_in_g1 := 122; gprErrCorInfo('27-L').blocks_in_g2 := 4; gprErrCorInfo('27-L').cw_in_g2 := 123; 
    gprErrCorInfo('27-M').total_no_of_data_cw := 1128; gprErrCorInfo('27-M').ec_cw_per_block := 28; gprErrCorInfo('27-M').blocks_in_g1 := 22; gprErrCorInfo('27-M').cw_in_g1 := 45; gprErrCorInfo('27-M').blocks_in_g2 := 3; gprErrCorInfo('27-M').cw_in_g2 := 46; 
    gprErrCorInfo('27-Q').total_no_of_data_cw := 808; gprErrCorInfo('27-Q').ec_cw_per_block := 30; gprErrCorInfo('27-Q').blocks_in_g1 := 8; gprErrCorInfo('27-Q').cw_in_g1 := 23; gprErrCorInfo('27-Q').blocks_in_g2 := 26; gprErrCorInfo('27-Q').cw_in_g2 := 24; 
    gprErrCorInfo('27-H').total_no_of_data_cw := 628; gprErrCorInfo('27-H').ec_cw_per_block := 30; gprErrCorInfo('27-H').blocks_in_g1 := 12; gprErrCorInfo('27-H').cw_in_g1 := 15; gprErrCorInfo('27-H').blocks_in_g2 := 28; gprErrCorInfo('27-H').cw_in_g2 := 16; 
    gprErrCorInfo('28-L').total_no_of_data_cw := 1531; gprErrCorInfo('28-L').ec_cw_per_block := 30; gprErrCorInfo('28-L').blocks_in_g1 := 3; gprErrCorInfo('28-L').cw_in_g1 := 117; gprErrCorInfo('28-L').blocks_in_g2 := 10; gprErrCorInfo('28-L').cw_in_g2 := 118; 
    gprErrCorInfo('28-M').total_no_of_data_cw := 1193; gprErrCorInfo('28-M').ec_cw_per_block := 28; gprErrCorInfo('28-M').blocks_in_g1 := 3; gprErrCorInfo('28-M').cw_in_g1 := 45; gprErrCorInfo('28-M').blocks_in_g2 := 23; gprErrCorInfo('28-M').cw_in_g2 := 46; 
    gprErrCorInfo('28-Q').total_no_of_data_cw := 871; gprErrCorInfo('28-Q').ec_cw_per_block := 30; gprErrCorInfo('28-Q').blocks_in_g1 := 4; gprErrCorInfo('28-Q').cw_in_g1 := 24; gprErrCorInfo('28-Q').blocks_in_g2 := 31; gprErrCorInfo('28-Q').cw_in_g2 := 25; 
    gprErrCorInfo('28-H').total_no_of_data_cw := 661; gprErrCorInfo('28-H').ec_cw_per_block := 30; gprErrCorInfo('28-H').blocks_in_g1 := 11; gprErrCorInfo('28-H').cw_in_g1 := 15; gprErrCorInfo('28-H').blocks_in_g2 := 31; gprErrCorInfo('28-H').cw_in_g2 := 16; 
    gprErrCorInfo('29-L').total_no_of_data_cw := 1631; gprErrCorInfo('29-L').ec_cw_per_block := 30; gprErrCorInfo('29-L').blocks_in_g1 := 7; gprErrCorInfo('29-L').cw_in_g1 := 116; gprErrCorInfo('29-L').blocks_in_g2 := 7; gprErrCorInfo('29-L').cw_in_g2 := 117; 
    gprErrCorInfo('29-M').total_no_of_data_cw := 1267; gprErrCorInfo('29-M').ec_cw_per_block := 28; gprErrCorInfo('29-M').blocks_in_g1 := 21; gprErrCorInfo('29-M').cw_in_g1 := 45; gprErrCorInfo('29-M').blocks_in_g2 := 7; gprErrCorInfo('29-M').cw_in_g2 := 46; 
    gprErrCorInfo('29-Q').total_no_of_data_cw := 911; gprErrCorInfo('29-Q').ec_cw_per_block := 30; gprErrCorInfo('29-Q').blocks_in_g1 := 1; gprErrCorInfo('29-Q').cw_in_g1 := 23; gprErrCorInfo('29-Q').blocks_in_g2 := 37; gprErrCorInfo('29-Q').cw_in_g2 := 24; 
    gprErrCorInfo('29-H').total_no_of_data_cw := 701; gprErrCorInfo('29-H').ec_cw_per_block := 30; gprErrCorInfo('29-H').blocks_in_g1 := 19; gprErrCorInfo('29-H').cw_in_g1 := 15; gprErrCorInfo('29-H').blocks_in_g2 := 26; gprErrCorInfo('29-H').cw_in_g2 := 16; 
    gprErrCorInfo('30-L').total_no_of_data_cw := 1735; gprErrCorInfo('30-L').ec_cw_per_block := 30; gprErrCorInfo('30-L').blocks_in_g1 := 5; gprErrCorInfo('30-L').cw_in_g1 := 115; gprErrCorInfo('30-L').blocks_in_g2 := 10; gprErrCorInfo('30-L').cw_in_g2 := 116; 
    gprErrCorInfo('30-M').total_no_of_data_cw := 1373; gprErrCorInfo('30-M').ec_cw_per_block := 28; gprErrCorInfo('30-M').blocks_in_g1 := 19; gprErrCorInfo('30-M').cw_in_g1 := 47; gprErrCorInfo('30-M').blocks_in_g2 := 10; gprErrCorInfo('30-M').cw_in_g2 := 48; 
    gprErrCorInfo('30-Q').total_no_of_data_cw := 985; gprErrCorInfo('30-Q').ec_cw_per_block := 30; gprErrCorInfo('30-Q').blocks_in_g1 := 15; gprErrCorInfo('30-Q').cw_in_g1 := 24; gprErrCorInfo('30-Q').blocks_in_g2 := 25; gprErrCorInfo('30-Q').cw_in_g2 := 25; 
    gprErrCorInfo('30-H').total_no_of_data_cw := 745; gprErrCorInfo('30-H').ec_cw_per_block := 30; gprErrCorInfo('30-H').blocks_in_g1 := 23; gprErrCorInfo('30-H').cw_in_g1 := 15; gprErrCorInfo('30-H').blocks_in_g2 := 25; gprErrCorInfo('30-H').cw_in_g2 := 16; 
    gprErrCorInfo('31-L').total_no_of_data_cw := 1843; gprErrCorInfo('31-L').ec_cw_per_block := 30; gprErrCorInfo('31-L').blocks_in_g1 := 13; gprErrCorInfo('31-L').cw_in_g1 := 115; gprErrCorInfo('31-L').blocks_in_g2 := 3; gprErrCorInfo('31-L').cw_in_g2 := 116; 
    gprErrCorInfo('31-M').total_no_of_data_cw := 1455; gprErrCorInfo('31-M').ec_cw_per_block := 28; gprErrCorInfo('31-M').blocks_in_g1 := 2; gprErrCorInfo('31-M').cw_in_g1 := 46; gprErrCorInfo('31-M').blocks_in_g2 := 29; gprErrCorInfo('31-M').cw_in_g2 := 47; 
    gprErrCorInfo('31-Q').total_no_of_data_cw := 1033; gprErrCorInfo('31-Q').ec_cw_per_block := 30; gprErrCorInfo('31-Q').blocks_in_g1 := 42; gprErrCorInfo('31-Q').cw_in_g1 := 24; gprErrCorInfo('31-Q').blocks_in_g2 := 1; gprErrCorInfo('31-Q').cw_in_g2 := 25; 
    gprErrCorInfo('31-H').total_no_of_data_cw := 793; gprErrCorInfo('31-H').ec_cw_per_block := 30; gprErrCorInfo('31-H').blocks_in_g1 := 23; gprErrCorInfo('31-H').cw_in_g1 := 15; gprErrCorInfo('31-H').blocks_in_g2 := 28; gprErrCorInfo('31-H').cw_in_g2 := 16; 
    gprErrCorInfo('32-L').total_no_of_data_cw := 1955; gprErrCorInfo('32-L').ec_cw_per_block := 30; gprErrCorInfo('32-L').blocks_in_g1 := 17; gprErrCorInfo('32-L').cw_in_g1 := 115; gprErrCorInfo('32-L').blocks_in_g2 := null; gprErrCorInfo('32-L').cw_in_g2 := null; 
    gprErrCorInfo('32-M').total_no_of_data_cw := 1541; gprErrCorInfo('32-M').ec_cw_per_block := 28; gprErrCorInfo('32-M').blocks_in_g1 := 10; gprErrCorInfo('32-M').cw_in_g1 := 46; gprErrCorInfo('32-M').blocks_in_g2 := 23; gprErrCorInfo('32-M').cw_in_g2 := 47; 
    gprErrCorInfo('32-Q').total_no_of_data_cw := 1115; gprErrCorInfo('32-Q').ec_cw_per_block := 30; gprErrCorInfo('32-Q').blocks_in_g1 := 10; gprErrCorInfo('32-Q').cw_in_g1 := 24; gprErrCorInfo('32-Q').blocks_in_g2 := 35; gprErrCorInfo('32-Q').cw_in_g2 := 25; 
    gprErrCorInfo('32-H').total_no_of_data_cw := 845; gprErrCorInfo('32-H').ec_cw_per_block := 30; gprErrCorInfo('32-H').blocks_in_g1 := 19; gprErrCorInfo('32-H').cw_in_g1 := 15; gprErrCorInfo('32-H').blocks_in_g2 := 35; gprErrCorInfo('32-H').cw_in_g2 := 16; 
    gprErrCorInfo('33-L').total_no_of_data_cw := 2071; gprErrCorInfo('33-L').ec_cw_per_block := 30; gprErrCorInfo('33-L').blocks_in_g1 := 17; gprErrCorInfo('33-L').cw_in_g1 := 115; gprErrCorInfo('33-L').blocks_in_g2 := 1; gprErrCorInfo('33-L').cw_in_g2 := 116; 
    gprErrCorInfo('33-M').total_no_of_data_cw := 1631; gprErrCorInfo('33-M').ec_cw_per_block := 28; gprErrCorInfo('33-M').blocks_in_g1 := 14; gprErrCorInfo('33-M').cw_in_g1 := 46; gprErrCorInfo('33-M').blocks_in_g2 := 21; gprErrCorInfo('33-M').cw_in_g2 := 47; 
    gprErrCorInfo('33-Q').total_no_of_data_cw := 1171; gprErrCorInfo('33-Q').ec_cw_per_block := 30; gprErrCorInfo('33-Q').blocks_in_g1 := 29; gprErrCorInfo('33-Q').cw_in_g1 := 24; gprErrCorInfo('33-Q').blocks_in_g2 := 19; gprErrCorInfo('33-Q').cw_in_g2 := 25; 
    gprErrCorInfo('33-H').total_no_of_data_cw := 901; gprErrCorInfo('33-H').ec_cw_per_block := 30; gprErrCorInfo('33-H').blocks_in_g1 := 11; gprErrCorInfo('33-H').cw_in_g1 := 15; gprErrCorInfo('33-H').blocks_in_g2 := 46; gprErrCorInfo('33-H').cw_in_g2 := 16; 
    gprErrCorInfo('34-L').total_no_of_data_cw := 2191; gprErrCorInfo('34-L').ec_cw_per_block := 30; gprErrCorInfo('34-L').blocks_in_g1 := 13; gprErrCorInfo('34-L').cw_in_g1 := 115; gprErrCorInfo('34-L').blocks_in_g2 := 6; gprErrCorInfo('34-L').cw_in_g2 := 116; 
    gprErrCorInfo('34-M').total_no_of_data_cw := 1725; gprErrCorInfo('34-M').ec_cw_per_block := 28; gprErrCorInfo('34-M').blocks_in_g1 := 14; gprErrCorInfo('34-M').cw_in_g1 := 46; gprErrCorInfo('34-M').blocks_in_g2 := 23; gprErrCorInfo('34-M').cw_in_g2 := 47; 
    gprErrCorInfo('34-Q').total_no_of_data_cw := 1231; gprErrCorInfo('34-Q').ec_cw_per_block := 30; gprErrCorInfo('34-Q').blocks_in_g1 := 44; gprErrCorInfo('34-Q').cw_in_g1 := 24; gprErrCorInfo('34-Q').blocks_in_g2 := 7; gprErrCorInfo('34-Q').cw_in_g2 := 25; 
    gprErrCorInfo('34-H').total_no_of_data_cw := 961; gprErrCorInfo('34-H').ec_cw_per_block := 30; gprErrCorInfo('34-H').blocks_in_g1 := 59; gprErrCorInfo('34-H').cw_in_g1 := 16; gprErrCorInfo('34-H').blocks_in_g2 := 1; gprErrCorInfo('34-H').cw_in_g2 := 17; 
    gprErrCorInfo('35-L').total_no_of_data_cw := 2306; gprErrCorInfo('35-L').ec_cw_per_block := 30; gprErrCorInfo('35-L').blocks_in_g1 := 12; gprErrCorInfo('35-L').cw_in_g1 := 121; gprErrCorInfo('35-L').blocks_in_g2 := 7; gprErrCorInfo('35-L').cw_in_g2 := 122; 
    gprErrCorInfo('35-M').total_no_of_data_cw := 1812; gprErrCorInfo('35-M').ec_cw_per_block := 28; gprErrCorInfo('35-M').blocks_in_g1 := 12; gprErrCorInfo('35-M').cw_in_g1 := 47; gprErrCorInfo('35-M').blocks_in_g2 := 26; gprErrCorInfo('35-M').cw_in_g2 := 48; 
    gprErrCorInfo('35-Q').total_no_of_data_cw := 1286; gprErrCorInfo('35-Q').ec_cw_per_block := 30; gprErrCorInfo('35-Q').blocks_in_g1 := 39; gprErrCorInfo('35-Q').cw_in_g1 := 24; gprErrCorInfo('35-Q').blocks_in_g2 := 14; gprErrCorInfo('35-Q').cw_in_g2 := 25; 
    gprErrCorInfo('35-H').total_no_of_data_cw := 986; gprErrCorInfo('35-H').ec_cw_per_block := 30; gprErrCorInfo('35-H').blocks_in_g1 := 22; gprErrCorInfo('35-H').cw_in_g1 := 15; gprErrCorInfo('35-H').blocks_in_g2 := 41; gprErrCorInfo('35-H').cw_in_g2 := 16; 
    gprErrCorInfo('36-L').total_no_of_data_cw := 2434; gprErrCorInfo('36-L').ec_cw_per_block := 30; gprErrCorInfo('36-L').blocks_in_g1 := 6; gprErrCorInfo('36-L').cw_in_g1 := 121; gprErrCorInfo('36-L').blocks_in_g2 := 14; gprErrCorInfo('36-L').cw_in_g2 := 122; 
    gprErrCorInfo('36-M').total_no_of_data_cw := 1914; gprErrCorInfo('36-M').ec_cw_per_block := 28; gprErrCorInfo('36-M').blocks_in_g1 := 6; gprErrCorInfo('36-M').cw_in_g1 := 47; gprErrCorInfo('36-M').blocks_in_g2 := 34; gprErrCorInfo('36-M').cw_in_g2 := 48; 
    gprErrCorInfo('36-Q').total_no_of_data_cw := 1354; gprErrCorInfo('36-Q').ec_cw_per_block := 30; gprErrCorInfo('36-Q').blocks_in_g1 := 46; gprErrCorInfo('36-Q').cw_in_g1 := 24; gprErrCorInfo('36-Q').blocks_in_g2 := 10; gprErrCorInfo('36-Q').cw_in_g2 := 25; 
    gprErrCorInfo('36-H').total_no_of_data_cw := 1054; gprErrCorInfo('36-H').ec_cw_per_block := 30; gprErrCorInfo('36-H').blocks_in_g1 := 2; gprErrCorInfo('36-H').cw_in_g1 := 15; gprErrCorInfo('36-H').blocks_in_g2 := 64; gprErrCorInfo('36-H').cw_in_g2 := 16; 
    gprErrCorInfo('37-L').total_no_of_data_cw := 2566; gprErrCorInfo('37-L').ec_cw_per_block := 30; gprErrCorInfo('37-L').blocks_in_g1 := 17; gprErrCorInfo('37-L').cw_in_g1 := 122; gprErrCorInfo('37-L').blocks_in_g2 := 4; gprErrCorInfo('37-L').cw_in_g2 := 123; 
    gprErrCorInfo('37-M').total_no_of_data_cw := 1992; gprErrCorInfo('37-M').ec_cw_per_block := 28; gprErrCorInfo('37-M').blocks_in_g1 := 29; gprErrCorInfo('37-M').cw_in_g1 := 46; gprErrCorInfo('37-M').blocks_in_g2 := 14; gprErrCorInfo('37-M').cw_in_g2 := 47; 
    gprErrCorInfo('37-Q').total_no_of_data_cw := 1426; gprErrCorInfo('37-Q').ec_cw_per_block := 30; gprErrCorInfo('37-Q').blocks_in_g1 := 49; gprErrCorInfo('37-Q').cw_in_g1 := 24; gprErrCorInfo('37-Q').blocks_in_g2 := 10; gprErrCorInfo('37-Q').cw_in_g2 := 25; 
    gprErrCorInfo('37-H').total_no_of_data_cw := 1096; gprErrCorInfo('37-H').ec_cw_per_block := 30; gprErrCorInfo('37-H').blocks_in_g1 := 24; gprErrCorInfo('37-H').cw_in_g1 := 15; gprErrCorInfo('37-H').blocks_in_g2 := 46; gprErrCorInfo('37-H').cw_in_g2 := 16; 
    gprErrCorInfo('38-L').total_no_of_data_cw := 2702; gprErrCorInfo('38-L').ec_cw_per_block := 30; gprErrCorInfo('38-L').blocks_in_g1 := 4; gprErrCorInfo('38-L').cw_in_g1 := 122; gprErrCorInfo('38-L').blocks_in_g2 := 18; gprErrCorInfo('38-L').cw_in_g2 := 123; 
    gprErrCorInfo('38-M').total_no_of_data_cw := 2102; gprErrCorInfo('38-M').ec_cw_per_block := 28; gprErrCorInfo('38-M').blocks_in_g1 := 13; gprErrCorInfo('38-M').cw_in_g1 := 46; gprErrCorInfo('38-M').blocks_in_g2 := 32; gprErrCorInfo('38-M').cw_in_g2 := 47; 
    gprErrCorInfo('38-Q').total_no_of_data_cw := 1502; gprErrCorInfo('38-Q').ec_cw_per_block := 30; gprErrCorInfo('38-Q').blocks_in_g1 := 48; gprErrCorInfo('38-Q').cw_in_g1 := 24; gprErrCorInfo('38-Q').blocks_in_g2 := 14; gprErrCorInfo('38-Q').cw_in_g2 := 25; 
    gprErrCorInfo('38-H').total_no_of_data_cw := 1142; gprErrCorInfo('38-H').ec_cw_per_block := 30; gprErrCorInfo('38-H').blocks_in_g1 := 42; gprErrCorInfo('38-H').cw_in_g1 := 15; gprErrCorInfo('38-H').blocks_in_g2 := 32; gprErrCorInfo('38-H').cw_in_g2 := 16; 
    gprErrCorInfo('39-L').total_no_of_data_cw := 2812; gprErrCorInfo('39-L').ec_cw_per_block := 30; gprErrCorInfo('39-L').blocks_in_g1 := 20; gprErrCorInfo('39-L').cw_in_g1 := 117; gprErrCorInfo('39-L').blocks_in_g2 := 4; gprErrCorInfo('39-L').cw_in_g2 := 118; 
    gprErrCorInfo('39-M').total_no_of_data_cw := 2216; gprErrCorInfo('39-M').ec_cw_per_block := 28; gprErrCorInfo('39-M').blocks_in_g1 := 40; gprErrCorInfo('39-M').cw_in_g1 := 47; gprErrCorInfo('39-M').blocks_in_g2 := 7; gprErrCorInfo('39-M').cw_in_g2 := 48; 
    gprErrCorInfo('39-Q').total_no_of_data_cw := 1582; gprErrCorInfo('39-Q').ec_cw_per_block := 30; gprErrCorInfo('39-Q').blocks_in_g1 := 43; gprErrCorInfo('39-Q').cw_in_g1 := 24; gprErrCorInfo('39-Q').blocks_in_g2 := 22; gprErrCorInfo('39-Q').cw_in_g2 := 25; 
    gprErrCorInfo('39-H').total_no_of_data_cw := 1222; gprErrCorInfo('39-H').ec_cw_per_block := 30; gprErrCorInfo('39-H').blocks_in_g1 := 10; gprErrCorInfo('39-H').cw_in_g1 := 15; gprErrCorInfo('39-H').blocks_in_g2 := 67; gprErrCorInfo('39-H').cw_in_g2 := 16; 
    gprErrCorInfo('40-L').total_no_of_data_cw := 2956; gprErrCorInfo('40-L').ec_cw_per_block := 30; gprErrCorInfo('40-L').blocks_in_g1 := 19; gprErrCorInfo('40-L').cw_in_g1 := 118; gprErrCorInfo('40-L').blocks_in_g2 := 6; gprErrCorInfo('40-L').cw_in_g2 := 119; 
    gprErrCorInfo('40-M').total_no_of_data_cw := 2334; gprErrCorInfo('40-M').ec_cw_per_block := 28; gprErrCorInfo('40-M').blocks_in_g1 := 18; gprErrCorInfo('40-M').cw_in_g1 := 47; gprErrCorInfo('40-M').blocks_in_g2 := 31; gprErrCorInfo('40-M').cw_in_g2 := 48; 
    gprErrCorInfo('40-Q').total_no_of_data_cw := 1666; gprErrCorInfo('40-Q').ec_cw_per_block := 30; gprErrCorInfo('40-Q').blocks_in_g1 := 34; gprErrCorInfo('40-Q').cw_in_g1 := 24; gprErrCorInfo('40-Q').blocks_in_g2 := 34; gprErrCorInfo('40-Q').cw_in_g2 := 25; 
    gprErrCorInfo('40-H').total_no_of_data_cw := 1276; gprErrCorInfo('40-H').ec_cw_per_block := 30; gprErrCorInfo('40-H').blocks_in_g1 := 20; gprErrCorInfo('40-H').cw_in_g1 := 15; gprErrCorInfo('40-H').blocks_in_g2 := 61; gprErrCorInfo('40-H').cw_in_g2 := 16; 
END;


--CALCULATION FUNC AND PROC

FUNCTION f_mode_name(p_type pls_integer) RETURN varchar2 IS
    lcMode varchar2(50);
BEGIN
    lcMode := 
        CASE p_type
            WHEN cNumericMode THEN 'Numeric Mode'
            WHEN cAlphanumericMode THEN 'Alphanumeric Mode'
            WHEN cByteMode THEN 'Byte Mode (ISO-8859-1)'
            WHEN cDoublebyteMode THEN 'Kanji mode (double-byte)'
            ELSE null
            END;
            
    RETURN lcMode;
END;



/*
function returns QR code mode depending of data going to be encoded:
1 - Numeric mode (for decimal digits 0 through 9)
2 - Alphanumeric mode (specific table encoded in this function)
3 - Byte mode (ISO-8859-1 character set)
4 - Double-byte mode (UTF-8, Kanji...)
*/
FUNCTION f_get_mode(p_data varchar2) RETURN pls_integer IS
    lnType pls_integer := 0;
    lcChar varchar2(1);
BEGIN
    FOR t IN 1 .. length(p_data) LOOP
        lcChar := substr(p_data, t, 1);

        if '0123456789' like '%' || lcChar || '%' then  --numeric mode (1)
            lnType := greatest(lnType, cNumericMode);
            
        elsif 'ABCDEFGHIJKLMNOPQRSTUVWXYZ $%*+-./:' like '%' || lcChar || '%' then  --alphanumeric mode (2)
            lnType := greatest(lnType, cAlphanumericMode);
        
        elsif ascii(lcChar) <= 255 then  --Byte mode (3)
            lnType := greatest(lnType, cByteMode);

        else  --double-byte mode (UTF-8) (4)
            lnType := cDoublebyteMode;
            
        end if;

        p_debug('mode: ' || lnType || ' for char ' || lcChar, 2);
    
    END LOOP;

    --debug
    p_debug('mode for qr code: ' || f_mode_name(lnType) );

    RETURN lnType;
END;

FUNCTION f_err_cor_2_number(p_error_correction varchar2) RETURN number IS
    lnNumber pls_integer;
BEGIN
    --conversion to number
    lnNumber := CASE p_error_correction
        WHEN 'L' THEN 1
        WHEN 'M' THEN 2
        WHEN 'Q' THEN 3
        WHEN 'H' THEN 4
        ELSE 0 END;
    
    --error if mode can not be determined
    if lnNumber = 0 then
        RAISE_APPLICATION_ERROR(-20000, 'unknown error correction mode!');    
    end if;
    
    --return value
    RETURN lnNumber;
END f_err_cor_2_number;


/*
4 different indicators which are encoded into QR code
*/
FUNCTION f_mode_indicator RETURN varchar2 IS
    lcMode varchar2(4);
BEGIN
    lcMode := 
        CASE gpnMode 
            WHEN cNumericMode THEN '0001'
            WHEN cAlphanumericMode THEN '0010'
            WHEN cByteMode THEN '0100'
            WHEN cDoublebyteMode THEN '1000'
            ELSE null
            END;
            
    p_debug('Mode indicator: ' || lcMode, 2);
            
    RETURN lcMode;
END;




/*
character count indicator - final length in bits depends of mode and version
*/
FUNCTION f_char_count_indicator(p_data varchar2) RETURN varchar2 IS
    lnLength pls_integer;
    lcIndicator varchar2(16);
    lnCCILength pls_integer;
    
BEGIN
    --length to binary
    lnLength := length(p_data);
    lcIndicator := f_integer_2_binary(lnLength);

    p_debug('CCI Binary: ' || lcIndicator, 2);
    
    --padding
    if gpnVersion <= 9 then
        lnCCILength := 
            CASE gpnMode 
                WHEN cNumericMode THEN 10
                WHEN cAlphanumericMode THEN 9
                WHEN cByteMode THEN 8
                WHEN cDoublebyteMode THEN 8
                ELSE 0
                END;
    elsif gpnVersion between 10 and 26 then
        lnCCILength := 
            CASE gpnMode 
                WHEN cNumericMode THEN 12
                WHEN cAlphanumericMode THEN 11
                WHEN cByteMode THEN 16
                WHEN cDoublebyteMode THEN 10
                ELSE 0
                END;

    elsif gpnVersion >= 27 then
        lnCCILength := 
            CASE gpnMode 
                WHEN cNumericMode THEN 14
                WHEN cAlphanumericMode THEN 13
                WHEN cByteMode THEN 16
                WHEN cDoublebyteMode THEN 12
                ELSE 0
                END;
    
    end if;
    p_debug('Character Count Indicator length: ' || lnCCILength, 2);

    
    lcIndicator := lpad(lcIndicator, lnCCILength, '0');
    
    p_debug('Character Count Indicator: ' || lcIndicator, 2);
    
    
    RETURN lcIndicator;
END;


/*
function determins and returns a QR code version (size), which depends of 3 values:
- error correction level
- mode (numeric, alphanumeric, byte or double byte)
- length of data

Version is determined from a table, where 3 dimensions are values from previous list
We are searching for a smallest value, which can contain our data (error correction level and mode are fixed)

For example, for:
- correction level "M" 
- data "HELLO TO ALL PEOPLE IN THE WORLD" (data length is 32, mode is alphanumeric)
a version is 2, because for given dimensions a version 2 can contain maximal of 38 characters and we have 32 characters
Version 1 can contain maximal 20 characters and it is not enough.
*/
FUNCTION f_get_version(
    p_data varchar2,
    p_error_correction varchar2) RETURN pls_integer IS
    
    TYPE t_values IS TABLE OF varchar2(1000) INDEX BY pls_integer;
    lrValues t_values;

    TYPE t_numbers IS TABLE OF pls_integer;
    lrData t_numbers;

    lnVersion pls_integer := 0;
    lnLength pls_integer;
    
    lnElements pls_integer;
    lnPosition pls_integer;

    
BEGIN
    --initial values to determine version
    lnLength := length(p_data);

    /*
    values are separated in sets; each set has 4 values
    first value in set is for numeric mode, second for alphanumeric, then byte and at the end for double-byte
    first set is for error level "L", next set for "M", then "Q" then "H"
    example for version 1 (values are maximal number of characters for error level correction and mode)
       numeric    alphanumeric    byte     double-byte   
    L       41              25      17              10
    M       34              20      14               8
    Q       27              16      11               7
    H       17              10       7               4
    
    index for variable lrValues is version
    values are parsed in collection during runtime
    */

    lrValues(1) := '41,25,17,10,34,20,14,8,27,16,11,7,17,10,7,4';
    lrValues(2) := '77,47,32,20,63,38,26,16,48,29,20,12,34,20,14,8';
    lrValues(3) := '127,77,53,32,101,61,42,26,77,47,32,20,58,35,24,15';
    lrValues(4) := '187,114,78,48,149,90,62,38,111,67,46,28,82,50,34,21';
    lrValues(5) := '255,154,106,65,202,122,84,52,144,87,60,37,106,64,44,27';
    lrValues(6) := '322,195,134,82,255,154,106,65,178,108,74,45,139,84,58,36';
    lrValues(7) := '370,224,154,95,293,178,122,75,207,125,86,53,154,93,64,39';
    lrValues(8) := '461,279,192,118,365,221,152,93,259,157,108,66,202,122,84,52';
    lrValues(9) := '552,335,230,141,432,262,180,111,312,189,130,80,235,143,98,60';
    lrValues(10) := '652,395,271,167,513,311,213,131,364,221,151,93,288,174,119,74';
    lrValues(11) := '772,468,321,198,604,366,251,155,427,259,177,109,331,200,137,85';
    lrValues(12) := '883,535,367,226,691,419,287,177,489,296,203,125,374,227,155,96';
    lrValues(13) := '1022,619,425,262,796,483,331,204,580,352,241,149,427,259,177,109';
    lrValues(14) := '1101,667,458,282,871,528,362,223,621,376,258,159,468,283,194,120';
    lrValues(15) := '1250,758,520,320,991,600,412,254,703,426,292,180,530,321,220,136';
    lrValues(16) := '1408,854,586,361,1082,656,450,277,775,470,322,198,602,365,250,154';
    lrValues(17) := '1548,938,644,397,1212,734,504,310,876,531,364,224,674,408,280,173';
    lrValues(18) := '1725,1046,718,442,1346,816,560,345,948,574,394,243,746,452,310,191';
    lrValues(19) := '1903,1153,792,488,1500,909,624,384,1063,644,442,272,813,493,338,208';
    lrValues(20) := '2061,1249,858,528,1600,970,666,410,1159,702,482,297,919,557,382,235';
    lrValues(21) := '2232,1352,929,572,1708,1035,711,438,1224,742,509,314,969,587,403,248';
    lrValues(22) := '2409,1460,1003,618,1872,1134,779,480,1358,823,565,348,1056,640,439,270';
    lrValues(23) := '2620,1588,1091,672,2059,1248,857,528,1468,890,611,376,1108,672,461,284';
    lrValues(24) := '2812,1704,1171,721,2188,1326,911,561,1588,963,661,407,1228,744,511,315';
    lrValues(25) := '3057,1853,1273,784,2395,1451,997,614,1718,1041,715,440,1286,779,535,330';
    lrValues(26) := '3283,1990,1367,842,2544,1542,1059,652,1804,1094,751,462,1425,864,593,365';
    lrValues(27) := '3517,2132,1465,902,2701,1637,1125,692,1933,1172,805,496,1501,910,625,385';
    lrValues(28) := '3669,2223,1528,940,2857,1732,1190,732,2085,1263,868,534,1581,958,658,405';
    lrValues(29) := '3909,2369,1628,1002,3035,1839,1264,778,2181,1322,908,559,1677,1016,698,430';
    lrValues(30) := '4158,2520,1732,1066,3289,1994,1370,843,2358,1429,982,604,1782,1080,742,457';
    lrValues(31) := '4417,2677,1840,1132,3486,2113,1452,894,2473,1499,1030,634,1897,1150,790,486';
    lrValues(32) := '4686,2840,1952,1201,3693,2238,1538,947,2670,1618,1112,684,2022,1226,842,518';
    lrValues(33) := '4965,3009,2068,1273,3909,2369,1628,1002,2805,1700,1168,719,2157,1307,898,553';
    lrValues(34) := '5253,3183,2188,1347,4134,2506,1722,1060,2949,1787,1228,756,2301,1394,958,590';
    lrValues(35) := '5529,3351,2303,1417,4343,2632,1809,1113,3081,1867,1283,790,2361,1431,983,605';
    lrValues(36) := '5836,3537,2431,1496,4588,2780,1911,1176,3244,1966,1351,832,2524,1530,1051,647';
    lrValues(37) := '6153,3729,2563,1577,4775,2894,1989,1224,3417,2071,1423,876,2625,1591,1093,673';
    lrValues(38) := '6479,3927,2699,1661,5039,3054,2099,1292,3599,2181,1499,923,2735,1658,1139,701';
    lrValues(39) := '6743,4087,2809,1729,5313,3220,2213,1362,3791,2298,1579,972,2927,1774,1219,750';
    lrValues(40) := '7089,4296,2953,1817,5596,3391,2331,1435,3993,2420,1663,1024,3057,1852,1273,784';


    --a version depending of error correction method, mode and data length
    lnPosition := (f_err_cor_2_number(p_error_correction) - 1) * 4 + gpnMode;
    
    p_debug('length: ' || lnLength, 2);

    FOR t IN 1 .. 40 LOOP
        p_debug(lrValues(t), 4);
        
        SELECT to_number(column_value) a
        BULK COLLECT INTO lrData
        FROM XMLTABLE(lrValues(t));

        p_debug('Value on position ' || lnPosition || ': ' || lrData(lnPosition), 2);
        
        if lrData(lnPosition) >= lnLength then
            lnVersion := t;
            EXIT;
        end if;
        
    END LOOP;
    
    --if version can not be determined then throw error
    if lnVersion = 0 then
        RAISE_APPLICATION_ERROR(-20000, 'Data length is too big to be encoded in one QR code.');    
    end if;

    --debug 
    p_debug('version: ' || lnVersion);

    RETURN lnVersion;
    
END f_get_version;


FUNCTION f_encode_data(
    p_data varchar2,
    p_error_correction varchar2) RETURN varchar2 IS
    
    lcData varchar2(32000);
    lnCounter pls_integer := 1;
    lcSub varchar2(3);
    lnReqNumOfBits pls_integer;

    --function returns value of character in alphanumeric mode
    FUNCTION f_get_code(p_char varchar2) RETURN pls_integer IS
        lnCode pls_integer;
    BEGIN
        --0 - 9
        if '0123456789' like '%' || p_char || '%' then
            lnCode := to_number(p_char);
        elsif 'ABCDEFGHIJKLMNOPQRSTUVWXYZ' like '%' || p_char || '%' then
            lnCode := ascii(p_char) - 55;
        elsif p_char = ' ' then 
            lnCode := 36;
        elsif p_char = '$' then 
            lnCode := 37;
        elsif p_char = '%' then 
            lnCode := 38;
        elsif p_char = '*' then 
            lnCode := 39;
        elsif p_char = '+' then 
            lnCode := 40;
        elsif p_char = '-' then 
            lnCode := 41;
        elsif p_char = '.' then 
            lnCode := 42;
        elsif p_char = '/' then 
            lnCode := 43;
        elsif p_char = ':' then 
            lnCode := 44;
        end if; 
        
        RETURN lnCode;
    END f_get_code;

    
BEGIN
    --encoded data regardless of mode always start with mode indicator and character count indicator
    lcData := f_mode_indicator || f_char_count_indicator(p_data);

    --data encoding - different for different modes 
    if gpnMode = cNumericMode then
        LOOP
            lcSub := ltrim(substr(p_data, lnCounter, 3), '0');
            
            p_debug(lcSub, 2);
            
            if length(lcSub) = 3 then
                lcData := lcData || lpad(f_integer_2_binary( to_number(lcSub) ), 10, '0');
            elsif length(lcSub) = 2 then
                lcData := lcData || lpad(f_integer_2_binary( to_number(lcSub) ), 7, '0');
            elsif length(lcSub) = 1 then
                lcData := lcData || lpad(f_integer_2_binary( to_number(lcSub) ), 4, '0');
            end if;
            
            EXIT WHEN lnCounter >= length(p_data); 
            
            lnCounter := lnCounter + 3;
        END LOOP;
        
    elsif gpnMode = cAlphanumericMode then
        
        LOOP
            lcSub := substr(p_data, lnCounter, 2);
            
            p_debug(lcSub, 2);
            
            if length(lcSub) = 2 then
                lcData := lcData || lpad(f_integer_2_binary( f_get_code(substr(lcSub, 1, 1)) * 45 + f_get_code(substr(lcSub, 2, 1)) ), 11, '0');
            elsif length(lcSub) = 1 then
                lcData := lcData || lpad(f_integer_2_binary( f_get_code(lcSub) ), 6, '0');
            end if;

            EXIT WHEN lnCounter >= length(p_data); 
            
            lnCounter := lnCounter + 2;
        END LOOP;
        
    elsif gpnMode = cByteMode then
        FOR t IN 1 .. length(p_data) LOOP
            lcData := lcData || lpad(f_integer_2_binary( ascii(substr(p_data, t, 1)) ), 8, '0');
        END LOOP;
        
    elsif gpnMode = cDoublebyteMode then
        --TODO for Kanji mode
        null;
    end if;

    p_debug('Data without right padding (number of bits ' || length(lcData) || '): ' || lcData, 2);

    --terminator zeros
    lnReqNumOfBits := gprErrCorInfo(gpnVersion || '-' || p_error_correction).total_no_of_data_cw * 8;
    p_debug('Required number of bits: ' || lnReqNumOfBits, 2);
    
    if lnReqNumOfBits - length(p_data) >= 4 then
        lcData := lcData || '0000';
        p_debug('Terminator zeros: 0000', 2);
    else
        lcData := rpad(lcData, lnReqNumOfBits - length(p_data), '0');
        p_debug('Terminator zeros: ' || rpad(null, lnReqNumOfBits - length(p_data), '0'), 2);
    end if;

    --additional right padding with 0 to reach a string length multiple of 8
     LOOP
        EXIT WHEN length(lcData) mod 8 = 0;
        lcData := lcData || '0';
        p_debug('Additional right padding zeros: 0', 2);
    END LOOP;

    --final filling of data with 11101100 and 00010001 alternatively until full length is reached
     LOOP
        EXIT WHEN length(lcData) = lnReqNumOfBits;
        lcData := lcData || '11101100';
        p_debug('Additional padding with: 11101100', 2);
        EXIT WHEN length(lcData) = lnReqNumOfBits;
        lcData := lcData || '00010001';
        p_debug('Additional padding with: 00010001', 2);
    END LOOP;


    --debug
    p_debug('Data (number of bits ' || length(lcData) || '): ' || lcData);
    
    RETURN lcData;
    
END f_encode_data;



FUNCTION f_final_data_with_ec(
    p_encoded_data varchar2,
    p_error_correction varchar2) RETURN varchar2 IS
    
    TYPE t_cw IS TABLE OF pls_integer;
    TYPE r_block IS RECORD (cw t_cw);
    TYPE t_block IS TABLE OF r_block INDEX BY varchar2(10);
    
    lrBlock t_block;
    
    lcVersionEC varchar2(10);
    lcBlock varchar2(10);
    lnCounter pls_integer := 1;
    lcCW varchar2(8);
    lnCW pls_integer;
    lnGroups pls_integer;
    lcDebug varchar2(10000);
    lnReminderBits pls_integer := 0;
    
    lcResult varchar2(32000);
    
    FUNCTION f_blocks_in_group(p_group pls_integer) RETURN pls_integer IS
    BEGIN
        RETURN
            CASE 
                WHEN p_group = 1 THEN gprErrCorInfo(lcVersionEC).blocks_in_g1 
                ELSE nvl(gprErrCorInfo(lcVersionEC).blocks_in_g2, 0) 
            END;
    END;

    FUNCTION f_cw_in_group(p_group pls_integer) RETURN pls_integer IS
    BEGIN
        RETURN
            CASE 
                WHEN p_group = 1 THEN gprErrCorInfo(lcVersionEC).cw_in_g1 
                ELSE nvl(gprErrCorInfo(lcVersionEC).cw_in_g2, 0)
            END;
    END;

    PROCEDURE p_add_cw_to_block(p_gb varchar2, p_cw pls_integer) IS
    BEGIN
        lrBlock(p_gb).cw.extend;
        lrBlock(p_gb).cw(lrBlock(p_gb).cw.count) := p_cw;
    END;
    
    PROCEDURE p_debug_collection(
        p_description varchar2,
        p_collection t_cw,
        p_level pls_integer default 1) IS
        
    BEGIN
        lcDebug := p_description;
        FOR t IN p_collection.first .. p_collection.last LOOP 
            lcDebug := lcDebug || p_collection(t) || ', ';
        END LOOP;
        p_debug(rtrim(lcDebug, ', '), p_level);
    END;
    
    FUNCTION f_poly_divide(p_mess_poly t_cw, p_gen_poly t_cw) RETURN t_cw IS
        lrEC t_cw := t_cw();
        lrDivider t_cw := t_cw();
        lrResult t_cw := t_cw();
        
        lnAnti pls_integer;
    BEGIN
        --copy message polynomial to lrEC
        lrEC := lrEc MULTISET UNION ALL p_mess_poly;
        
        --To make sure that the exponent of the lead term doesn't become too small during the division
        --multiply the message polynomial by xn where n is the number of error correction codewords that are needed
        --so, we extend the collection and fill those elements with 0
        lrEC.extend(p_gen_poly.count - 1);
        FOR t IN REVERSE lrEC.first .. lrEC.last LOOP
            EXIT WHEN lrEC(t) is not null;
            lrEC(t) := 0;
        END LOOP;
    
        FOR t IN 1 .. p_mess_poly.count LOOP
            p_debug('Step ' || t || ':', 2);
            
            if lrEC(t) > 0 then
                --Lead Term of the Message Polynomial (in first cycle) or result from previous cycle 
                --antilog is needed for multipilcation with generator polynomial (next step)
                lnAnti := gprAntiLog( lrEC(t) );
                p_debug('Lead Term of the Message Polynomial: ' || lrEC(t) || ' (antiLog ' || lnAnti || ')', 2);
                
                --copy generator polynomial to lrDivider
                lrDivider.delete;
                lrDivider := lrDivider MULTISET UNION ALL p_gen_poly;
                
                --Multiply the Generator Polynomial by the Lead Term of the Message Polynomial 
                --everything is happening in antilog - generator polynomial is already in antilog
                --basicly we add two antilogs
                FOR p IN 1 .. lrDivider.count LOOP
                    lrDivider(p) := lrDivider(p) + lnAnti;
                    if lrDivider(p) >= 255 then 
                        lrDivider(p) := lrDivider(p) - 255;
                    end if;
                END LOOP;
                
                p_debug_collection(
                    'Generator polynomial multiplied with Lead Term antiLog (in antiLog): ',
                    lrDivider,
                    2);
                
                --XOR the result with the message polynomial (first cycle) or result from previous cycle
                --Message or result from previous cycle is already in log, so we convert generated polynomial from previous step into log
                --leading terms, which are already 0 are discarded (index is "p + t - 1")
                FOR p IN 1 .. lrDivider.count LOOP
                    lrEC(p + t - 1) := bitxor( lrEC(p + t - 1), gprLog(lrDivider(p)) );
                END LOOP;

                p_debug_collection(
                    'XOR the result with the message polynomial or result from previous cycle (in Log): ',
                    lrEC,
                    2);
            else 
                p_debug('skipping this step and discarding next lead term 0...', 2);
            end if;

        END LOOP;
    
        --last remaining elements are error correction codewords
        FOR t IN lrEC.count - (p_gen_poly.count - 2) .. lrEC.count LOOP
            lrResult.extend;
            lrResult(lrResult.count) := lrEC(t);
        END LOOP;

        RETURN lrResult;
    END;
    
    
BEGIN
    --Version and EC Level
    lcVersionEC := gpnVersion || '-' || p_error_correction;
    p_debug('Version and EC Level: ' || lcVersionEC, 2);

    --generator polynomial - init for all 13 possible options
    --generator polynomial has the same structure as message polynomial (block) and so the same type is used
    lrBlock('7').cw := t_cw(0, 87, 229, 146, 149, 238, 102, 21);
    lrBlock('10').cw := t_cw(0, 251, 67, 46, 61, 118, 70, 64, 94, 32, 45);
    lrBlock('13').cw := t_cw(0, 74, 152, 176, 100, 86, 100, 106, 104, 130, 218, 206, 140, 78);
    lrBlock('15').cw := t_cw(0, 8, 183, 61, 91, 202, 37, 51, 58, 58, 237, 140, 124, 5, 99, 105);
    lrBlock('16').cw := t_cw(0, 120, 104, 107, 109, 102, 161, 76, 3, 91, 191, 147, 169, 182, 194, 225, 120);
    lrBlock('17').cw := t_cw(0, 43, 139, 206, 78, 43, 239, 123, 206, 214, 147, 24, 99, 150, 39, 243, 163, 136);
    lrBlock('18').cw := t_cw(0, 215, 234, 158, 94, 184, 97, 118, 170, 79, 187, 152, 148, 252, 179, 5, 98, 96, 153);
    lrBlock('20').cw := t_cw(0, 17, 60, 79, 50, 61, 163, 26, 187, 202, 180, 221, 225, 83, 239, 156, 164, 212, 212, 188, 190);
    lrBlock('22').cw := t_cw(0, 210, 171, 247, 242, 93, 230, 14, 109, 221, 53, 200, 74, 8, 172, 98, 80, 219, 134, 160, 105, 165, 231);
    lrBlock('24').cw := t_cw(0, 229, 121, 135, 48, 211, 117, 251, 126, 159, 180, 169, 152, 192, 226, 228, 218, 111, 0, 117, 232, 87, 96, 227, 21);
    lrBlock('26').cw := t_cw(0, 173, 125, 158, 2, 103, 182, 118, 17, 145, 201, 111, 28, 165, 53, 161, 21, 245, 142, 13, 102, 48, 227, 153, 145, 218, 70);
    lrBlock('28').cw := t_cw(0, 168, 223, 200, 104, 224, 234, 108, 180, 110, 190, 195, 147, 205, 27, 232, 201, 21, 43, 245, 87, 42, 195, 212, 119, 242, 37, 9, 123);
    lrBlock('30').cw := t_cw(0, 41, 173, 145, 152, 216, 31, 179, 182, 50, 48, 110, 86, 239, 96, 222, 125, 42, 173, 226, 193, 224, 130, 156, 37, 251, 216, 238, 40, 192, 180);

    --debug - Generator Polynomial used
    p_debug_collection(
        'Generator Polynomial (' || gprErrCorInfo(lcVersionEC).ec_cw_per_block || '): ',
        lrBlock(gprErrCorInfo(lcVersionEC).ec_cw_per_block).cw,
        2);
    
    --how many groups
    lnGroups := (CASE WHEN gprErrCorInfo(lcVersionEC).blocks_in_g2 is null THEN 1 ELSE 2 END);
    
    --debug - number of groups and blocks in each group, number of codewords for each block in group
    p_debug('Number of groups: ' || lnGroups, 2);
    FOR gr IN 1 .. lnGroups LOOP
        p_debug('Group ' || gr || ' - number of blocks in group: ' || f_blocks_in_group(gr), 2);
        p_debug('Group ' || gr || ' - number of codewords in each block: ' || f_cw_in_group(gr), 2);
    END LOOP;
    
    --prepare message polynomial for each group and block (G1B1, G1B2 ... G2B1, G2B2...)
    FOR gr IN 1 .. lnGroups LOOP
        FOR blk IN 1 .. f_blocks_in_group(gr) LOOP
            --init block
            lcBlock := 'G' || gr || 'B' || blk;
            lrBlock(lcBlock).cw := t_cw();
            
            p_debug('Group ' || gr || ', block ' || blk || ' - message polynomial:', 2); 
            
            --fill block with data codewords (codewords are converted to decimal)
            FOR cw IN 1 .. f_cw_in_group(gr) LOOP
                lcCW := substr(p_encoded_data, lnCounter, 8);
                lnCW := bin2dec(lcCW);
                
                p_add_cw_to_block(lcBlock, lnCW);
                p_debug('Codeword ' || cw || ': ' || lcCW || ' (' || lnCW || ')', 2);
                
                lnCounter := lnCounter + 8;
            END LOOP;
            
        END LOOP;
    END LOOP;


    --calculate error correction data for each group and block (G1B1EC, G1B2EC... G2B1EC, G2B2EC...)
    FOR gr IN 1 .. lnGroups LOOP
        FOR blk IN 1 .. f_blocks_in_group(gr) LOOP
            lrBlock('G' || gr || 'B' || blk || 'EC').cw := f_poly_divide(
                lrBlock('G' || gr || 'B' || blk).cw, --message polynomial
                lrBlock(gprErrCorInfo(lcVersionEC).ec_cw_per_block).cw  --generator polynomial
                );
            
            p_debug_collection(
                'Final error correction codewords for group ' || gr || ' and block ' || blk || ': ',
                lrBlock('G' || gr || 'B' || blk || 'EC').cw,
                2);
            
        END LOOP;
    END LOOP;
    
    
    --structure final message (interleaving) - data codewords
    lcDebug := 'Interleaved data codewords: ';
    FOR cnt IN 1 .. greatest( f_cw_in_group(1), f_cw_in_group(2) ) LOOP
        FOR gr IN 1 .. lnGroups LOOP
            FOR blk IN 1 .. f_blocks_in_group(gr) LOOP
                
                if lrBlock('G' || gr || 'B' || blk).cw.count >= cnt then
                    lcResult := lcResult || lpad(f_integer_2_binary( lrBlock('G' || gr || 'B' || blk).cw(cnt) ), 8, '0');
                    lcDebug := lcDebug || lrBlock('G' || gr || 'B' || blk).cw(cnt) || ', ';
                end if;
            
            END LOOP;
        END LOOP;
    END LOOP;
    p_debug(rtrim(lcDebug, ', '), 2);


    --structure final message (interleaving) - error correction codewords
    lcDebug := 'Interleaved error correction codewords: ';
    FOR cnt IN 1 .. gprErrCorInfo(lcVersionEC).ec_cw_per_block LOOP
        FOR gr IN 1 .. lnGroups LOOP
            FOR blk IN 1 .. f_blocks_in_group(gr) LOOP
                lcResult := lcResult || lpad(f_integer_2_binary( lrBlock('G' || gr || 'B' || blk || 'EC').cw(cnt) ), 8, '0');
                    lcDebug := lcDebug || lrBlock('G' || gr || 'B' || blk || 'EC').cw(cnt) || ', ';
            END LOOP;
        END LOOP;
    END LOOP;
    p_debug(rtrim(lcDebug, ', '), 2);
    
    
    --Add Remainder Bits for some QR versions, if necessary
    lnReminderBits := 
        CASE
            WHEN gpnVersion between 2 and 6 THEN 7
            WHEN gpnVersion between 21 and 27 THEN 4
            WHEN gpnVersion between 14 and 20 or gpnVersion between 28 and 34 THEN 3
            ELSE 0
            END;
    p_debug('Reminder bits: ' || lnReminderBits, 2);
    
    if lnReminderBits > 0 then
        lcResult := rpad(lcResult, length(lcResult) + lnReminderBits, '0');
    end if;

    p_debug('Final message (length ' || length(lcResult) || '): ' || lcResult);


    RETURN lcResult;
END f_final_data_with_ec;



PROCEDURE p_place_fm_in_matrix(lcData varchar2) IS
    
    lnColumn pls_integer;
    lnRow pls_integer;
    lnDirection pls_integer;
    
    lnCounter pls_integer;
    

    PROCEDURE p_set_module(p_column pls_integer, p_row pls_integer) IS
    BEGIN
        if gprMatrix(p_row)(p_column) is null then
            gprMatrix(p_row)(p_column) := substr(lcData, lnCounter, 1);
            lnCounter := lnCounter + 1;
        end if;
    END;
    
BEGIN
    --staring values
    lnColumn := f_matrix_size;
    
    lnRow := f_matrix_size;
    lnDirection := -1;
    
    lnCounter := 1;

    LOOP
        EXIT WHEN lnColumn < 1;
    
        --fill data in column
        FOR t IN 1 .. f_matrix_size LOOP
            p_set_module(lnColumn, lnRow);
            p_set_module(lnColumn - 1, lnRow);
            
            lnRow := lnRow + lnDirection;
        END LOOP;

        --change of direction
        lnDirection := lnDirection * -1;
        
        --first position for next column (because the last iteration of loop breached through matrix margine)
        lnRow := lnRow + lnDirection; 
        
        --next column
        lnColumn := lnColumn - 2;
        --exception is vertical time pattern - if pattern is reached then column shifts to the first column on the left 
        if lnColumn = 7 then 
            lnColumn := 6;
        end if;

    END LOOP;

    --debug filled matrix
    p_debug('Matrix filled with final message (modules marked with dots are for format data; marked with stars are for version - those data will be filled in masking step):', 2);
    p_dbms_output_matrix(gprMatrix, 2);
END;


PROCEDURE p_masking_format_version(p_error_correction varchar2) IS

    TYPE t_format_version IS TABLE OF varchar2(20) INDEX BY varchar2(2);
    
    lrFormat t_format_version;
    lrVersion t_format_version;
    
    lnR pls_integer;
    lnC pls_integer;

    PROCEDURE p_init_format_version IS
    BEGIN
        --init format
        lrFormat('L0') := '111011111000100';
        lrFormat('L1') := '111001011110011';
        lrFormat('L2') := '111110110101010';
        lrFormat('L3') := '111100010011101';
        lrFormat('L4') := '110011000101111';
        lrFormat('L5') := '110001100011000';
        lrFormat('L6') := '110110001000001';
        lrFormat('L7') := '110100101110110';
        lrFormat('M0') := '101010000010010';
        lrFormat('M1') := '101000100100101';
        lrFormat('M2') := '101111001111100';
        lrFormat('M3') := '101101101001011';
        lrFormat('M4') := '100010111111001';
        lrFormat('M5') := '100000011001110';
        lrFormat('M6') := '100111110010111';
        lrFormat('M7') := '100101010100000';
        lrFormat('Q0') := '011010101011111';
        lrFormat('Q1') := '011000001101000';
        lrFormat('Q2') := '011111100110001';
        lrFormat('Q3') := '011101000000110';
        lrFormat('Q4') := '010010010110100';
        lrFormat('Q5') := '010000110000011';
        lrFormat('Q6') := '010111011011010';
        lrFormat('Q7') := '010101111101101';
        lrFormat('H0') := '001011010001001';
        lrFormat('H1') := '001001110111110';
        lrFormat('H2') := '001110011100111';
        lrFormat('H3') := '001100111010000';
        lrFormat('H4') := '000011101100010';
        lrFormat('H5') := '000001001010101';
        lrFormat('H6') := '000110100001100';
        lrFormat('H7') := '000100000111011';
        
        --init version
        lrVersion('7') := '000111110010010100';
        lrVersion('8') := '001000010110111100';
        lrVersion('9') := '001001101010011001';
        lrVersion('10') := '001010010011010011';
        lrVersion('11') := '001011101111110110';
        lrVersion('12') := '001100011101100010';
        lrVersion('13') := '001101100001000111';
        lrVersion('14') := '001110011000001101';
        lrVersion('15') := '001111100100101000';
        lrVersion('16') := '010000101101111000';
        lrVersion('17') := '010001010001011101';
        lrVersion('18') := '010010101000010111';
        lrVersion('19') := '010011010100110010';
        lrVersion('20') := '010100100110100110';
        lrVersion('21') := '010101011010000011';
        lrVersion('22') := '010110100011001001';
        lrVersion('23') := '010111011111101100';
        lrVersion('24') := '011000111011000100';
        lrVersion('25') := '011001000111100001';
        lrVersion('26') := '011010111110101011';
        lrVersion('27') := '011011000010001110';
        lrVersion('28') := '011100110000011010';
        lrVersion('29') := '011101001100111111';
        lrVersion('30') := '011110110101110101';
        lrVersion('31') := '011111001001010000';
        lrVersion('32') := '100000100111010101';
        lrVersion('33') := '100001011011110000';
        lrVersion('34') := '100010100010111010';
        lrVersion('35') := '100011011110011111';
        lrVersion('36') := '100100101100001011';
        lrVersion('37') := '100101010000101110';
        lrVersion('38') := '100110101001100100';
        lrVersion('39') := '100111010101000001';
        lrVersion('40') := '101000110001101001';
    END p_init_format_version;


    PROCEDURE p_format_version(p_mask pls_integer) IS
        lcFormat varchar2(20);
        lcVersion varchar2(20);
        lnCounter pls_integer;

        PROCEDURE p_set_module(
            p_row pls_integer, 
            p_column pls_integer, 
            p_pos pls_integer, 
            p_format_version varchar2  --F for format and V for version
            ) IS
        BEGIN
            --modules are reserved and values 2 and 3 are set (not 0 and 1)
            gprMasking(p_mask)(p_row)(p_column) := 
                (CASE WHEN substr( (CASE WHEN p_format_version = 'F' THEN lcFormat ELSE lcVersion END), p_pos, 1) = '1' THEN '3' ELSE '2' END);
        END;

    BEGIN
        --put format in matrix (for all 8 maskings)
        lcFormat := lrFormat(p_error_correction || p_mask);
        p_debug('Format for error correction ' || p_error_correction || ' and masking ' || p_mask || ': ' || lcFormat, 3);
        
        --top left finder
        p_set_module(9, 1, 1, 'F');
        p_set_module(9, 2, 2, 'F');
        p_set_module(9, 3, 3, 'F');
        p_set_module(9, 4, 4, 'F');
        p_set_module(9, 5, 5, 'F');
        p_set_module(9, 6, 6, 'F');
        p_set_module(9, 8, 7, 'F');
        p_set_module(9, 9, 8, 'F');
        p_set_module(8, 9, 9, 'F');
        p_set_module(6, 9, 10, 'F');
        p_set_module(5, 9, 11, 'F');
        p_set_module(4, 9, 12, 'F');
        p_set_module(3, 9, 13, 'F');
        p_set_module(2, 9, 14, 'F');
        p_set_module(1, 9, 15, 'F');

        --lower left and top right finder
        p_set_module(f_matrix_size, 9, 1, 'F');
        p_set_module(f_matrix_size - 1, 9, 2, 'F');
        p_set_module(f_matrix_size - 2, 9, 3, 'F');
        p_set_module(f_matrix_size - 3, 9, 4, 'F');
        p_set_module(f_matrix_size - 4, 9, 5, 'F');
        p_set_module(f_matrix_size - 5, 9, 6, 'F');
        p_set_module(f_matrix_size - 6, 9, 7, 'F');
        
        p_set_module(9, f_matrix_size - 7, 8, 'F');
        p_set_module(9, f_matrix_size - 6, 9, 'F');
        p_set_module(9, f_matrix_size - 5, 10, 'F');
        p_set_module(9, f_matrix_size - 4, 11, 'F');
        p_set_module(9, f_matrix_size - 3, 12, 'F');
        p_set_module(9, f_matrix_size - 2, 13, 'F');
        p_set_module(9, f_matrix_size - 1, 14, 'F');
        p_set_module(9, f_matrix_size, 15, 'F');
        
        
        --put version in matrix (for 7 and higher)
        if gpnVersion >= 7 then
            lcVersion := lrVersion(gpnVersion);
            p_debug('Version (' || gpnVersion || ') for matrix: ' || lcVersion, 3);

            
            lnCounter := 1;
            FOR c IN REVERSE 1 .. 6 LOOP
                FOR r IN 8 .. 10 LOOP
                    --bottom left 
                    p_set_module(f_matrix_size - r, c, lnCounter, 'V');
                    
                    --top right
                    p_set_module(c, f_matrix_size - r, lnCounter, 'V');

                    lnCounter := lnCounter + 1;
                END LOOP;
            END LOOP; 

        else
            p_debug('Version (' || gpnVersion || ') is not needed for matrix', 3);
        end if;
        
        
    END p_format_version;
    
BEGIN
    --init format and version collection
    p_init_format_version;

    --copy matrix for 8 different maskings
    FOR t IN 0 .. 7 LOOP
        gprMasking(t) := t_column();
        gprMasking(t) := gprMasking(t) MULTISET UNION ALL gprMatrix;
    END LOOP;

    --mask every copy with different masking
    FOR t IN 0 .. 7 LOOP
        
        FOR r IN 1 .. f_matrix_size LOOP
            FOR c IN 1 .. f_matrix_size LOOP
                
                --matrix (collection) in Oracle begins with 1
                lnR := r - 1;
                lnC := c - 1;
            
                --masking is done only on data and error correction modules (matrix values 0 or 1 - other values are fixed)
                if gprMasking(t)(r)(c) in ('1', '0') then
                
                    --mask patterns
                    if 
                        (t=0 and (lnR + lnC) mod 2 = 0) or
                        (t=1 and lnR mod 2 = 0) or
                        (t=2 and lnC mod 3 = 0) or
                        (t=3 and (lnR + lnC) mod 3 = 0) or
                        (t=4 and (floor(lnR / 2) + floor(lnC / 3)) mod 2 = 0) or
                        (t=5 and ((lnR * lnC) mod 2) + ((lnR * lnC) mod 3) = 0) or
                        (t=6 and (((lnR * lnC) mod 2) + ((lnR * lnC) mod 3)) mod 2 = 0) or
                        (t=7 and (((lnR + lnC) mod 2) + ((lnR * lnC) mod 3)) mod 2 = 0) then

                        --switch black and white module
                        if gprMasking(t)(r)(c) = '1' then
                            gprMasking(t)(r)(c) := '0';
                        else
                            gprMasking(t)(r)(c) := '1';
                        end if;
                        
                    end if;

                end if;
                
            END LOOP;
        END LOOP;

        p_format_version(t);
        
        p_debug('Mask pattern ' || t || ':', 3);
        p_dbms_output_matrix(gprMasking(t), 3);
        p_debug('------------------------------------------------------------------------------------------', 3);
    
    END LOOP;

    --reserved fields marked with 2 and 3 are not necessary any more - change them to 0 and 1
    FOR t IN 0 .. 7 LOOP
        FOR r IN 1 .. f_matrix_size LOOP
            FOR c IN 1 .. f_matrix_size LOOP
                gprMasking(t)(r)(c) := CASE gprMasking(t)(r)(c) WHEN '3' THEN '1' WHEN '2' THEN '0' ELSE gprMasking(t)(r)(c) END;
            END LOOP;
        END LOOP;
    END LOOP;

END p_masking_format_version;


PROCEDURE p_penalty_rules(p_masking_out pls_integer default null) IS
    lnRule1 pls_integer;
    lnRule2 pls_integer;
    lnRule3 pls_integer;
    lnRule4 pls_integer;
    
    lnCounter pls_integer;
    lcPattern varchar2(11);
    lnPercent pls_integer;
    
    lnLowestPenalty pls_integer;
    lnChosenMasking pls_integer;
    
    lnDebugTemp pls_integer;
    
BEGIN
    --large initial values to be sure that first masking (0) is lower than those values
    lnLowestPenalty := 100000000;
    lnChosenMasking := 8;
    

    --iterate through all 8 maskings, calculate penalty and find lowest penalty score
    FOR t IN 0 .. 7 LOOP
    
        --rule 1 - five or more same-colored modules in a row (or column)
        lnRule1 := 0;
        
        FOR r IN 1 .. f_matrix_size LOOP  --horizontal direction
            lnCounter := 1;
            FOR c IN 2 .. f_matrix_size LOOP
                if gprMasking(t)(r)(c) = gprMasking(t)(r)(c - 1) then
                    lnCounter := lnCounter + 1;
                end if;
                if gprMasking(t)(r)(c) <> gprMasking(t)(r)(c - 1) or c = f_matrix_size then
                    if lnCounter >= 5 then
                        lnRule1 := lnRule1 + 3 + (lnCounter - 5);  --if 5 modules are the same color then penalty is 3 plus 1 for every additional module (4 for 6 modules...)
                    end if;
                    lnCounter := 1;
                end if;
            END LOOP;
        END LOOP;
        
        lnDebugTemp := lnRule1;
        p_debug('Masking ' || t || ', rule 1 - horizontal direction: ' || lnRule1, 2);

        FOR c IN 1 .. f_matrix_size LOOP  --vertical direction
            lnCounter := 1;
            FOR r IN 2 .. f_matrix_size LOOP
                if gprMasking(t)(r)(c) = gprMasking(t)(r - 1)(c) then
                    lnCounter := lnCounter + 1;
                end if;
                if gprMasking(t)(r)(c) <> gprMasking(t)(r - 1)(c) or r = f_matrix_size then
                    if lnCounter >= 5 then
                        lnRule1 := lnRule1 + 3 + (lnCounter - 5);  --if 5 modules are the same color then penalty is 3 plus 1 for every additional module (4 for 6 modules...)
                    end if;
                    lnCounter := 1;
                end if;
            END LOOP;
        END LOOP;
        
        p_debug('Masking ' || t || ', rule 1 - vertical direction: ' || (lnRule1 - lnDebugTemp), 2);
        p_debug('Masking ' || t || ', rule 1 - sum: ' || lnRule1, 2);
        p_debug(' ', 2);

        
        --rule 2 - areas of the same color that are 2x2 modules
        lnRule2 := 0;
        
        FOR r IN 1 .. f_matrix_size - 1 LOOP
            FOR c IN 1 .. f_matrix_size - 1 LOOP
                if 
                    gprMasking(t)(r)(c) = gprMasking(t)(r + 1)(c) and 
                    gprMasking(t)(r)(c) = gprMasking(t)(r)(c + 1) and 
                    gprMasking(t)(r)(c) = gprMasking(t)(r + 1)(c + 1) 
                    then
                    lnRule2 := lnRule2 + 3;
                end if;
            END LOOP;
        END LOOP;

        p_debug('Masking ' || t || ', rule 2 - sum: ' || lnRule2, 2);
        p_debug(' ', 2);


        --rule 3 - patterns of dark-light-dark-dark-dark-light-dark that have four light modules on either side (10111010000 or 00001011101)
        lnRule3 := 0;
        
        FOR r IN 1 .. f_matrix_size LOOP  --horizontal direction
            FOR c IN 1 .. f_matrix_size - 10 LOOP
                lcPattern := null;
                FOR p IN 0 .. 10 LOOP
                    lcPattern := lcPattern || gprMasking(t)(r)(c + p);
                END LOOP;
                
                if lcPattern in ('10111010000', '00001011101') then
                    p_debug(lcPattern || ' (horizontal) found in row ' || r || ' and column ' || c, 3);
                    lnRule3 := lnRule3 + 40;
                end if;
            END LOOP;
        END LOOP;
        
        lnDebugTemp := lnRule3;
        p_debug('Masking ' || t || ', rule 3 - horizontal direction: ' || lnRule3, 2);

        FOR c IN 1 .. f_matrix_size LOOP  --horizontal direction
            FOR r IN 1 .. f_matrix_size - 10 LOOP
                lcPattern := null;
                FOR p IN 0 .. 10 LOOP
                    lcPattern := lcPattern || gprMasking(t)(r + p)(c);
                END LOOP;
                
                if lcPattern in ('10111010000', '00001011101') then
                    p_debug(lcPattern || ' (vertical) found in row ' || r || ' and column ' || c, 3);
                    lnRule3 := lnRule3 + 40;
                end if;
            END LOOP;
        END LOOP;

        p_debug('Masking ' || t || ', rule 3 - vertical direction: ' || (lnRule3 - lnDebugTemp), 2);
        p_debug('Masking ' || t || ', rule 3 - sum: ' || lnRule3, 2);
        p_debug(' ', 2);


        --rule 4 -  ratio of light modules to dark modules
        lnCounter := 0;  --count dark modules
        FOR r IN 1 .. f_matrix_size LOOP
            FOR c IN 1 .. f_matrix_size LOOP
                if gprMasking(t)(r)(c) = '1' then
                    lnCounter := lnCounter + 1;
                end if;
            END LOOP;
        END LOOP;

        lnPercent := trim(lnCounter * 100 / (f_matrix_size * f_matrix_size));  --calculate percent of dark modules

        p_debug('Masking ' || t || ', rule 4 - total number of modules: ' || (f_matrix_size * f_matrix_size), 2);
        p_debug('Masking ' || t || ', rule 4 - dark modules: ' || lnCounter, 2);
        p_debug('Masking ' || t || ', rule 4 - % of dark modules: ' || lnPercent, 2);
        
        LOOP  --find lower multiple of 5
            EXIT WHEN lnPercent mod 5 = 0;
            lnPercent := lnPercent - 1;
        END LOOP;
        
        lnRule4 := least(  --subtract 50 from lower and upper multiple of 5; take absolute value; use smallest value; multiply with 10
            abs(lnPercent - 50) / 5,
            abs(lnPercent + 5 - 50) / 5) * 10;
        
        p_debug('Masking ' || t || ', rule 4 - value: ' || lnRule4, 2);
        p_debug(' ', 2);


        p_debug('Masking ' || t || ', final penalty value: ' || (lnRule1 + lnRule2 + lnRule3 + lnRule4), 2);
        p_debug('-----------------------------------------', 2);
        
        --check if penalty for current masking is lowest
        if (lnRule1 + lnRule2 + lnRule3 + lnRule4) < lnLowestPenalty then
            lnLowestPenalty := (lnRule1 + lnRule2 + lnRule3 + lnRule4);
            lnChosenMasking := t;
        end if;
        
    END LOOP;

    p_debug('Masking ' || lnChosenMasking || ' has lowest penalty of ' || lnLowestPenalty || ' and will be used for QR code matrix.', 2);

    --copy the best masking into original matrix and use it as result of QR code calculation
    --in case of debugging and selected masking output - use this value instead calculated and make an output
    gprMatrix.delete;
    gprMatrix := gprMatrix MULTISET UNION ALL gprMasking( nvl(p_masking_out, lnChosenMasking) );

END p_penalty_rules;



PROCEDURE p_generate_qr(
    p_data varchar2,
    p_error_correction varchar2,
    p_debug boolean default false,
    p_debug_level pls_integer default 1,
    p_masking_out pls_integer default null
    ) IS
    
    lcData varchar2(32000);
    lcFinal varchar2(32000);
    
BEGIN
    --global variables and tables, which has the same values during QR code generation
    gpbDebug := p_debug;
    gpnDebugLevel := p_debug_level;

    gpnMode := f_get_mode(p_data);
    gpnVersion := f_get_version(p_data, p_error_correction);
 
    p_fill_err_cor;
    p_fill_log_antilog;
    
    --init matrix collection and fill static elements
    --gpnVersion := 14;  --only for debugging
    p_init_matrix;
    
    --OPERATIONAL PART
    
    --encoded data with all parts (terminal zeros, padding bytes...)
    lcData := f_encode_data(p_data, p_error_correction);
    
    --final structured message (data plus error correction)
    lcFinal := f_final_data_with_ec(lcData, p_error_correction);
    
    --place final message in matrix
    p_place_fm_in_matrix(lcFinal);
    
    --masking; format and version info
    p_masking_format_version(p_error_correction);
    
    --Four Penalty Rules - choose which masking is the easiest to read and copy that masking in matrix variable
    p_penalty_rules(p_masking_out);
    
    
END p_generate_qr;


FUNCTION f_matrix_2_vc2 RETURN varchar2 IS
    lcQR varchar2(32727);
BEGIN
    FOR t IN 1 .. gprMatrix.count LOOP
        FOR p IN 1 .. gprMatrix.count LOOP
            lcQR := lcQR || nvl(gprMatrix(t)(p), 'X');
        END LOOP;
        lcQR := lcQR || chr(10);
    END LOOP;
    
    RETURN lcQR;
END;

  




PROCEDURE p_generate_qr_data(
    p_data varchar2,  --data going to be encoded into QR code
    p_error_correction varchar2, --L, M, Q or H (see bellow)
    p_qr OUT varchar2, --generated QR code data in format row || newline (chr 10) || row || newline...; 1 for black module, 0 for white
    p_matrix_size OUT pls_integer --matrix size in modules (21, 25, 29...)
    ) IS
    
BEGIN
    --generate matrix
    p_generate_qr(
        p_data => p_data, 
        p_error_correction => p_error_correction, 
        p_debug => false, 
        p_debug_level => 1);
    
    --convert matrix to vc2 (output)
    p_qr := f_matrix_2_vc2;

    --matrix size
    p_matrix_size := f_matrix_size;
    
END p_generate_qr_data;


PROCEDURE p_qr_debug(
    p_data varchar2,  --data going to be encoded into QR code
    p_error_correction varchar2, --L, M, Q or H (see bellow)
    p_debug boolean default true,  --should DBMS OUTPUT be printed
    p_debug_level pls_integer default 1,  --debug level (1, 2, 3...) - details to be printed in debug output
    p_masking_out pls_integer default null,
    p_qr OUT varchar2,
    p_matrix_size OUT pls_integer
    ) IS
    
BEGIN
    --generate matrix
    p_generate_qr(
        p_data => p_data, 
        p_error_correction => p_error_correction, 
        p_debug => p_debug, 
        p_debug_level => p_debug_level,
        p_masking_out => p_masking_out);

    --convert matrix to debug form
    p_qr := f_matrix_2_vc2;

    --matrix size
    p_matrix_size := f_matrix_size;
    
END p_qr_debug;



FUNCTION f_qr_as_html_table(
    p_data varchar2,  --data going to be encoded into QR code
    p_error_correction varchar2, --L, M, Q or H
    p_module_size_in_px pls_integer default 8, --module size in pixels
    p_margines boolean default false --margines around QR code (4 modules)
    ) RETURN clob IS
    
    lcQR varchar2(32727);
    lnMatrixSize pls_integer;
    lcClob clob;

    PROCEDURE p_add_clob(lcText varchar2) IS
    BEGIN
        lcClob := lcClob || lcText || chr(10);
    END;
    
BEGIN
    if p_data is null then
        lcClob := 'no data to display.';
        RETURN lcClob;
    end if;


    p_generate_qr_data(
        p_data => p_data,
        p_error_correction => p_error_correction, 
        p_qr => lcQR,
        p_matrix_size => lnMatrixSize
        );

    p_add_clob('<table style="border-collapse: collapse;">');
    
    --columns (for column width defined in style - inline on page)
    FOR t IN 1 .. lnMatrixSize + (CASE WHEN p_margines THEN 8 ELSE 0 END) LOOP
        p_add_clob('<col style="width: ' || p_module_size_in_px || 'px;">');
    END LOOP;
    
    --top margine - 4 module rows
    if p_margines then
        FOR t in 1 .. 4 LOOP
            p_add_clob('<tr style="height: ' || p_module_size_in_px || 'px;"><td style="background-color: #FFFFFF; padding: 0px 0px;"></td></tr>');
        END LOOP;
    end if;


    FOR t IN 1 .. lnMatrixSize LOOP
    
        --new row
        p_add_clob('<tr style="height: ' || p_module_size_in_px || 'px;">');
        
        --left margine - 4 modules
        if p_margines then
            FOR z in 1 .. 4 LOOP
                p_add_clob('<td style="background-color: #FFFFFF; padding: 0px 0px;"></td>');
            END LOOP;
        end if;
        
        --modules in row
        FOR p IN 1 .. lnMatrixSize LOOP
    
            p_add_clob('<td style="background-color: #' ||
                  (CASE 
                       substr(lcQR, (t - 1) * (lnMatrixSize + 1) + p, 1) 
                   WHEN '0' THEN 'FFFFFF' 
                   ELSE '000000' END) || 
                  '; padding: 0px 0px;"></td>');
            
        END LOOP;

        --right margine - 4 modules
        if p_margines then
            FOR z in 1 .. 4 LOOP
                p_add_clob('<td style="background-color: #FFFFFF; padding: 0px 0px;"></td>');
            END LOOP;
        end if;

        p_add_clob('</tr>');
        
    END LOOP;
    
    --bottom margine - 4 module rows
    if p_margines then
        FOR t in 1 .. 4 LOOP
            p_add_clob('<tr style="height: ' || p_module_size_in_px || 'px;"><td style="background-color: #FFFFFF; padding: 0px 0px;"></td></tr>');
        END LOOP;
    end if;
    
    p_add_clob('</table>');

    RETURN lcClob;
    
END f_qr_as_html_table;




PROCEDURE p_qr_as_html_table(
    p_data varchar2,  --data going to be encoded into QR code
    p_error_correction varchar2, --L, M, Q or H
    p_module_size_in_px pls_integer default 8, --module size in pixels
    p_margines boolean default false --margines around QR code (4 modules)
    ) IS
    
    lcClob clob;
    lnFrom pls_integer := 1;
    lnTo pls_integer;
    
BEGIN
    if p_data is null then
        htp.p('no data to display.');
        RETURN;
    end if;

    lcClob := f_qr_as_html_table(p_data, p_error_correction, p_module_size_in_px, p_margines);
    
    LOOP
        lnTo := instr(lcClob, chr(10), lnFrom);
        if lnTo = 0 then
            lnTo := length(lcClob);
        end if;
    
        htp.p(substr(lcClob, lnFrom, lnTo - lnFrom));
        
        lnFrom := lnTo + 1;
        
        EXIT WHEN lnTo = length(lcClob);
    END LOOP;
    
END p_qr_as_html_table;




FUNCTION unsigned_short(s in pls_integer) RETURN raw IS
    lrRet raw(4);
BEGIN
    lrRet := UTL_RAW.reverse( UTL_RAW.cast_from_binary_integer(s) );
    RETURN UTL_RAW.substr(lrRet, 1, 2);
END unsigned_short;


FUNCTION unsigned_int(i in pls_integer) RETURN raw IS 
    lrRet raw(4);
BEGIN
    lrRet := UTL_RAW.reverse( UTL_RAW.cast_from_binary_integer(i) );
    RETURN lrRet;
END unsigned_int;



FUNCTION f_qr_as_bmp(
    p_data varchar2,  --data going to be encoded into QR code
    p_error_correction varchar2, --L, M, Q or H
    p_margines varchar2 default 'N' --margines around QR code (4 modules) - values Y or N
    ) RETURN blob IS
    
    lcQR varchar2(32727);
    lnMatrixSize pls_integer;
    lnZeros pls_integer;
    lnImageBytes pls_integer;
    lnWidthHeight pls_integer;

    lbBlob blob;
    lrLine raw(500);
    
BEGIN
    if p_data is null then
        return null;
        RAISE_APPLICATION_ERROR(-20000, 'no data to display.');
    end if;

    p_generate_qr_data(
        p_data => p_data,
        p_error_correction => p_error_correction, 
        p_qr => lcQR,
        p_matrix_size => lnMatrixSize
        );


    DBMS_LOB.createTemporary(lbBlob, true);

    --Header
    lnWidthHeight := lnMatrixSize + (CASE WHEN p_margines = 'Y' THEN 8 ELSE 0 END);
    lnImageBytes := lnWidthHeight * lnWidthHeight * 8;
    
    dbms_lob.append(lbBlob, utl_raw.cast_to_raw('BM')); -- Pos  0 - fixed
    dbms_lob.append(lbBlob, unsigned_int(14 + 40 + 8 + lnImageBytes));    -- Pos  2 - file size (62 as header size + data size + color pallete)
    dbms_lob.append(lbBlob, unsigned_int(0));      -- Pos 6, unused / reserved, value 0
    dbms_lob.append(lbBlob, unsigned_int(14 + 40 + 8));      -- Pos 10, offset to image data - header size + information size + color pallete

    -- Information
    dbms_lob.append(lbBlob, unsigned_int(40));    -- Pos 14 - size of information header (always 40)
    dbms_lob.append(lbBlob, unsigned_int(lnWidthHeight * 8));    -- Pos 18 - width
    dbms_lob.append(lbBlob, unsigned_int(lnWidthHeight * 8));   -- Pos 22 - height
    dbms_lob.append(lbBlob, unsigned_short(1));        -- Pos 26, planes
    dbms_lob.append(lbBlob, unsigned_short(1));        -- Pos 28, bits per pixel
    dbms_lob.append(lbBlob, unsigned_int(0));        -- Pos 30, no compression
    dbms_lob.append(lbBlob, unsigned_int(lnImageBytes)); -- Pos 34 - image data size
    dbms_lob.append(lbBlob, unsigned_int(0));      -- Pos 38, x pixels/meter
    dbms_lob.append(lbBlob, unsigned_int(0));      -- Pos 42, y pixels/meter
    dbms_lob.append(lbBlob, unsigned_int(0));         -- Pos 46, Number of colors
    dbms_lob.append(lbBlob, unsigned_int(0));         -- Pos 50, Important colors

    --Colors
    dbms_lob.append(lbBlob, unsigned_int(16777215));  -- White (FF FF FF 00)
    dbms_lob.append(lbBlob, unsigned_int(0));         -- Black (00 00 00 00)
    
    
    
    --Data
    
    --zeros at the end of the scan line (scan line in bytes must be mod 4)
    lnZeros := 0;
    LOOP
        EXIT WHEN (lnWidthHeight + lnZeros) mod 4 = 0;
        lnZeros := lnZeros + 1;
    END LOOP;
    
    --bottom margine
    if p_margines = 'Y' then
        lrLine := utl_raw.copies( utl_raw.cast_to_raw(chr(0)), lnWidthHeight + lnZeros);
        
        FOR t IN 1 .. 32 LOOP
            dbms_lob.append(lbBlob, utl_raw.substr(lrLine, 1, lnWidthHeight + lnZeros));
        END LOOP;
    end if;
    
    --data for scan lines
    FOR r IN REVERSE 1 .. lnMatrixSize LOOP
        --first prepare scan line as raw data
        if p_margines = 'Y' then
            --left margine
            lrLine := utl_raw.copies( utl_raw.cast_to_raw(chr(0)), 4);
        else
            --no margines
            lrLine := null;
        end if;
        
        --data from matrix
        FOR c IN 1 .. lnMatrixSize LOOP
            lrLine := lrLine || utl_raw.cast_to_raw(chr(
                CASE WHEN substr(lcQR, (r - 1) * (lnMatrixSize + 1) + c, 1) = '1' THEN 255 ELSE 0 END
                ));
        END LOOP;

        --right margine
        if p_margines = 'Y' then
            lrLine := lrLine || utl_raw.copies( utl_raw.cast_to_raw(chr(0)), 4);
        end if;

        --trailing zeroes (mod 4)
        FOR c IN 1 .. lnZeros LOOP
            lrLine := lrLine || utl_raw.cast_to_raw(chr(0));
        END LOOP;
        
        --8 scan lines in file because module is 8x8 pixels
        FOR t IN 1 .. 8 LOOP
            dbms_lob.append(lbBlob, utl_raw.substr(lrLine, 1, lnWidthHeight + lnZeros));
        END LOOP;
    END LOOP;

    --top margine (4 modules)
    if p_margines = 'Y' then
        lrLine := utl_raw.copies( utl_raw.cast_to_raw(chr(0)), lnWidthHeight + lnZeros);
        
        FOR t IN 1 .. 32 LOOP
            dbms_lob.append(lbBlob, utl_raw.substr(lrLine, 1, lnWidthHeight + lnZeros));
        END LOOP;
    end if;

    RETURN lbBlob;
END f_qr_as_bmp;




PROCEDURE p_qr_as_img_tag_base64(
    p_data varchar2,  --data going to be encoded into QR code
    p_error_correction varchar2, --L, M, Q or H
    p_image_size_px pls_integer,
    p_margines varchar2 default 'N' --margines around QR code (4 modules) - values Y or N
    ) IS
    
    lbBlob blob;
    l_step PLS_INTEGER := 12000; -- make sure you set a multiple of 3 not higher than 24573
    
BEGIN
    lbBlob := f_qr_as_bmp(p_data, p_error_correction, p_margines);
    
    htp.prn('<img src="data:image/bmp;base64, ');
    
    FOR i IN 0 .. TRUNC((DBMS_LOB.getlength(lbBlob) - 1 )/l_step) LOOP
        htp.prn( UTL_RAW.cast_to_varchar2(UTL_ENCODE.base64_encode(DBMS_LOB.substr(lbBlob, l_step, i * l_step + 1))) );
    END LOOP;

    htp.prn('" alt="qr code" width="' || p_image_size_px || 'px" height = "' || p_image_size_px || 'px" />');
    
END;

PROCEDURE p_save_file(
    p_document blob,
    p_file_name varchar2,
    p_folder varchar2
    ) IS

    lfFile utl_file.file_type;
    lnLen pls_integer := 32767;
    
BEGIN
    lfFile := utl_file.fopen(p_folder, p_file_name, 'wb');
    FOR i in 0 .. trunc( (dbms_lob.getlength(p_document) - 1 ) / lnLen ) LOOP
        utl_file.put_raw(lfFile, dbms_lob.substr(p_document, lnLen, i * lnLen + 1));
    END LOOP;
    utl_file.fclose(lfFile);
END;



END ZT_QR;
/