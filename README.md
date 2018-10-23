# Oracle PL/SQL Package for QR Code Generation
QR Codes Generator package provides functionality to quickly and efficiently generate QR Codes (module 2) directly from Oracle database.
It requires no additional resources and it is developed in pure PL/SQL.

##Changelog
1.0 - Initial Release

##Install
- download 2 script files from "package" directory 
- install them in database schema
- first install PKS file (package definition) and then PKB file (package body)

##How to use
Main function, which calculate QR data and returns it in "1/0" varchar2 string is
`PROCEDURE p_generate_qr_data(
    p_data varchar2,
    p_error_correction varchar2, 
    p_qr OUT varchar2,
    p_matrix_size OUT pls_integer
    );`

##Demo Application
https://apex.oracle.com/pls/apex/f?p=zttechdemo
