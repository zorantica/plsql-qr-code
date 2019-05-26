CREATE OR REPLACE PACKAGE TICA.ZT_QR AS
/******************************************************************************
    Author:     Zoran Tica
                ZT-TECH, racunalniške storitve s.p.
                http://www.zt-tech.eu
    
    PURPOSE:    A package for QR code data and image generation 

    REVISIONS:
    Ver        Date        Author           Description
    ---------  ----------  ---------------  ------------------------------------
    1.0        18/08/2018  Zoran Tica       First version of package.
    1.1        26/05/2019  Zoran Tica       Added UTF-8 support, fixed minor BUGs for debug display


    ----------------------------------------------------------------------------
    Copyright (C) 2018 - Zoran Tica

    Permission is hereby granted, free of charge, to any person obtaining a copy
    of this software and associated documentation files (the "Software"), to deal
    in the Software without restriction, including without limitation the rights
    to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
    copies of the Software, and to permit persons to whom the Software is
    furnished to do so, subject to the following conditions:

    The above copyright notice and this permission notice shall be included in
    all copies or substantial portions of the Software.

    THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
    IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
    FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
    AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
    LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
    OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
    THE SOFTWARE.
    ----------------------------------------------------------------------------
*/


/*
Error correction modes:
L - Low       Recovers 7% of data
M - Medium    Recovers 15% of data
Q - Quartile  Recovers 25% of data
H - High      Recovers 30% of data
*/


/*
Procedure generates QR code data as varchar2 variable filled with 0 and 1
0 is white module, 1 is black
Lines are separated with chr(10)

IN parameters:
p_data - data that is going to be encoded into QR code
p_error_correction - error correction level (values L, M, Q or H)

OUT parameters:
p_qr - generated QR code data in format "row (1110100010100...) || newline (chr 10) || row || newline..."
p_matrix_size - matrix size in modules (21, 25, 29...)
*/
PROCEDURE p_generate_qr_data(
    p_data varchar2,
    p_error_correction varchar2, 
    p_qr OUT varchar2,
    p_matrix_size OUT pls_integer
    );


/*
Procedure generates QR code data as varchar2 variable filled with 0 and 1
0 is white module, 1 is black
Lines are separated with chr(10)
Debug is printed as DBMS_OUTPUT
There are 3 levels of debug (1, 2 or 3 - low, medium, high)

IN parameters:
p_data - data that is going to be encoded into QR code
p_error_correction - error correction level (values L, M, Q or H)
p_debug - should DBMS OUTPUT be printed
p_debug_level - debug level (1, 2, 3...) - details to be printed in debug output

OUT parameters:
p_qr - generated QR code data in format "row (1110100010100) || newline (chr 10) || row || newline..."
p_matrix_size - matrix size in modules (21, 25, 29...)
*/
PROCEDURE p_qr_debug(
    p_data varchar2,
    p_error_correction varchar2,
    p_debug boolean default true,
    p_debug_level pls_integer default 1,
    p_masking_out pls_integer default null,
    p_qr OUT varchar2,
    p_matrix_size OUT pls_integer
    );



/*
Function return HTML code for HTML table element representing QR code
Modules are shown as table cells
No additional data (CSS or HTML code) is needed to show table in HTML page

IN parameters:
p_data - data that is going to be encoded into QR code
p_error_correction - error correction level (values L, M, Q or H)
p_module_size_in_px - width and height of module (table cell)
p_margines - should white margine around QR code (4 modules wide) be generated
*/
FUNCTION f_qr_as_html_table(
    p_data varchar2,  --data going to be encoded into QR code
    p_error_correction varchar2, --L, M, Q or H
    p_module_size_in_px pls_integer default 8, --module size in pixels
    p_margines boolean default false --margines around QR code (4 modules)
    ) RETURN clob;

/*
Procedure prints HTML code for HTML table element using HTP.P procedure
HTML code is prepared in function f_qr_as_html_table

IN parameters:
p_data - data that is going to be encoded into QR code
p_error_correction - error correction level (values L, M, Q or H)
p_module_size_in_px - width and height of module (table cell)
p_margines - should white margine around QR code (4 modules wide) be generated
*/
PROCEDURE p_qr_as_html_table(
    p_data varchar2,  --data going to be encoded into QR code
    p_error_correction varchar2, --L, M, Q or H
    p_module_size_in_px pls_integer default 8, --module size in pixels
    p_margines boolean default false --margines around QR code (4 modules)
    );


/*
Function return black and white BMP image with QR code
Modules are 8x8 pixels large

IN parameters:
p_data - data that is going to be encoded into QR code
p_error_correction - error correction level (values L, M, Q or H)
p_margines - should white margine around QR code (4 modules wide) be generated
*/
FUNCTION f_qr_as_bmp(
    p_data varchar2,  --data going to be encoded into QR code
    p_error_correction varchar2, --L, M, Q or H
    p_margines varchar2 default 'N' --margines around QR code (4 modules) - values Y or N
    ) RETURN blob;


/*
Procedure shows QR code as black and white BMP image
Printed is HTML img tag with base64 image in it

IN parameters:
p_data - data that is going to be encoded into QR code
p_error_correction - error correction level (values L, M, Q or H)
p_image_size_px - image size in pixels
p_margines - should white margine around QR code (4 modules wide) be generated
*/
PROCEDURE p_qr_as_img_tag_base64(
    p_data varchar2,  --data going to be encoded into QR code
    p_error_correction varchar2, --L, M, Q or H
    p_image_size_px pls_integer,
    p_margines varchar2 default 'N' --margines around QR code (4 modules) - values Y or N
    );


/*
Utility procedure which saves generated BMP file containing QR code on server side (directory)
*/
PROCEDURE p_save_file(
    p_document blob,
    p_file_name varchar2,
    p_folder varchar2
    );

END ZT_QR;
/