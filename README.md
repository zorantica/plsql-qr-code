# Oracle PL/SQL Package for QR Code Generation
QR Codes Generator package provides functionality to quickly and efficiently generate QR Codes (module 2) directly from Oracle database.
It requires no additional resources and it is developed in pure PL/SQL.

## Changelog
1.0 - Initial Release

## Install
- download 2 script files from "package" directory 
- execute them in database schema in following order:
1. PKS script file (package definition)
2. PKB file (package body)

## How to use
Main function, which calculate QR data and returns it in "1/0" varchar2 string is `p_generate_qr_data`.
Input parameters are:
- text which is going to be encoded into QR code
- Error Correction Level (L, M, Q, H)
Output parameters are:
- QR Code data
- matrix size (in modules)

## Demo Application
https://apex.oracle.com/pls/apex/f?p=zttechdemo
