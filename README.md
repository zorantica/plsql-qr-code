# Oracle PL/SQL Package and APEX plugin for QR Code Generation
QR Codes Generator package provides functionality to quickly and efficiently generate QR Codes (module 2) directly from Oracle database.
It requires no additional resources and it is developed in pure PL/SQL.

Item-type APEX plugin uses PL/SQL package for calculations and graphical implementation of QR code and simplifies QR code usage in APEX applications.

## Changelog
1.0 - Initial Release
1.1 - Added APEX plugin

## Install PL/SQL package
- download 2 script files from "package" directory 
- execute them in database schema in following order:
1. PKS script file (package definition)
2. PKB file (package body)

New Package ZT_QR is created in database schema.

## How to use PL/SQL package
Procedure and Function descriptions with input and output parameters and examples are located in package definition script.

## Install APEX plugin
- First install PL/SQL package from "package" directory
- Then import plugin file "item_type_plugin_eu_zttech_qr_code.sql" from "apex plugin" directory into your application

For older versions of APEX, which use deprecated "Function" API interface use plugin file "item_type_plugin_eu_zttech_qr_code_func_api.sql" from "apex plugin/older versions" directory.

## Plugin Settings
For calculation and graphic representation of QR Code there are following parameters:
- Error correction level (4 different levels used for QR Code calculation)
- Display type (HTML table or BMP image)
- Module size (used when "HTML table" display type is selected - defines moduze size in pixels)
- Image size (used when "BMP image" display type is selected - defines image size in pixels)
- Margines (Yes/No - show 4 modules margine around QR Code or not)

## Demo Application
https://apex.oracle.com/pls/apex/f?p=zttechdemo

![](https://github.com/zorantica/qr-code/blob/master/preview.jpg)
