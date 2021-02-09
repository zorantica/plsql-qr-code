# Oracle PL/SQL Package and APEX plugin for QR Code Generation
QR Codes Generator package provides functionality to quickly and efficiently generate QR Codes (module 2) directly from Oracle database.

It requires no additional resources and it is developed in pure PL/SQL.

Item-type APEX plugin uses PL/SQL package for calculations and graphical implementation of QR code and simplifies QR code usage in APEX applications.

## Changelog
- 1.0 - Initial Release
- 1.1 - Added APEX plugin
- 1.2 - UTF-8 support
- 1.3 - "_" and "%" BUG resolved (Franz.Apeltauer@prinzhorn-holding.com, thank You for kind help!)
- 1.4 - added function f_qr_as_long_raw
- 1.5 - terminator zeroes BUG solved (Markus Lobedann, thank You for kind help!)
- 1.6 - older databases compatilbility (10g)
- 1.7 - Numeric mode BUG with "0" at the beginning of triplet group
- 2.0 - SVG image files support

## Install PL/SQL package
- download 2 script files from "package" directory 
- execute them in database schema in following order:
1. PKS script file (package definition)
2. PKB file (package body)

New Package ZT_QR is created in database schema.

## How to use PL/SQL package
Procedure and Function descriptions with input and output parameters and examples are located in package definition script.

## Use JPG images instead of BMP
BI Publisher (and potentialy some other software) is not displaying QR code BMP images correctly.

Solution is to convert BMP images to JPG using JAVA in database - thanks to mr Hamzeh Fathi (hfathi54@gmail.com).

How to install and use this functionality:
- download 2 script files from "BMP2JPG" directory
- install JAVA source from file "01 - bmp2jpg java.sql"
- install PL/SQL function wrapper for JAVA source from file "02 - plsql function.sql"; function can be installed as standalone or in some package (for example in QR code package)

That's it. Usage example for standalone function can be found in file "example.sql".

Remark: this way images also get smaller in size.

## Install APEX plugin
- First install PL/SQL package from "package" directory
- Then import plugin file "item_type_plugin_eu_zttech_qr_code.sql" from "apex plugin" directory into your application

For older versions of APEX, which use deprecated "Function" API interface use plugin file "item_type_plugin_eu_zttech_qr_code_func_api.sql" from "apex plugin/older versions" directory.

## Plugin Settings
For calculation and graphic representation of QR Code there are following parameters:
- Error correction level (4 different levels used for QR Code calculation)
- Margines (Yes/No - show 4 modules margine around QR Code or not)
- Display type (SVG image (default), HTML table or BMP image)
- Module size (used when "HTML table" or "SVG image" display type is selected - defines moduze size in pixels)
- Image size (used when "BMP image" display type is selected - defines image size in pixels)
- Module color (used when "SVG image" display type is selected - defines module color; colors can be defined as named colors (for example black, red, white...), using rgb function (for example rgb(255, 0, 0) ) or HEX values (for example #FF0000) )
- Background color (used when "SVG image" display type is selected - defines QR code background color; colors can be defined as named colors (for example black, red, white...), using rgb function (for example rgb(255, 0, 0) ) or HEX values (for example #FF0000) )
- Rounded module edges (used when "SVG image" display type is selected - defines if modules should have rounded edges; if size of this parameter is half the module size (or larger) then modules are represented as circles)

## Demo Application
https://apex.oracle.com/pls/apex/f?p=zttechdemo

![](https://github.com/zorantica/qr-code/blob/master/preview.jpg)
