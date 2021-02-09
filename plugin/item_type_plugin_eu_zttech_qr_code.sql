prompt --application/set_environment
set define off verify off feedback off
whenever sqlerror exit sql.sqlcode rollback
--------------------------------------------------------------------------------
--
-- ORACLE Application Express (APEX) export file
--
-- You should run the script connected to SQL*Plus as the Oracle user
-- APEX_190100 or as the owner (parsing schema) of the application.
--
-- NOTE: Calls to apex_application_install override the defaults below.
--
--------------------------------------------------------------------------------
begin
wwv_flow_api.import_begin (
 p_version_yyyy_mm_dd=>'2018.04.04'
,p_release=>'18.1.0.00.45'
,p_default_workspace_id=>1622468447055903
,p_default_application_id=>102
,p_default_owner=>'TICA'
);
end;
/
prompt --application/shared_components/plugins/item_type/eu_zttech_qrcode
begin
wwv_flow_api.create_plugin(
 p_id=>wwv_flow_api.id(19166686046667066)
,p_plugin_type=>'ITEM TYPE'
,p_name=>'EU.ZTTECH.QRCODE'
,p_display_name=>'QR Code'
,p_supported_ui_types=>'DESKTOP:JQM_SMARTPHONE'
,p_supported_component_types=>'APEX_APPLICATION_PAGE_ITEMS'
,p_plsql_code=>wwv_flow_string.join(wwv_flow_t_varchar2(
'PROCEDURE render_qrcode(',
'    p_item                IN apex_plugin.t_item,',
'    p_plugin              IN apex_plugin.t_plugin,',
'    p_param               IN apex_plugin.t_item_render_param,',
'    p_result              OUT apex_plugin.t_item_render_result) IS',
'    ',
'BEGIN',
'    if p_param.value is null then',
'        htp.p(''no data'');',
'    else',
'',
'        -- Printer Friendly Display',
'        IF p_param.is_printer_friendly THEN',
'            apex_plugin_util.print_display_only(p_item_name        => p_item.name,',
'                                                p_display_value    => p_param.value,',
'                                                p_show_line_breaks => FALSE,',
'                                                p_escape           => TRUE,',
'                                                p_attributes       => p_item.element_attributes);',
'        -- Read Only Display',
'        ELSIF p_param.is_readonly THEN',
'            apex_plugin_util.print_hidden_if_readonly(p_item_name           => p_item.name,',
'                                                      p_value               => p_param.value,',
'                                                      p_is_readonly         => p_param.is_readonly,',
'                                                      p_is_printer_friendly => p_param.is_printer_friendly);',
'',
'        -- Normal Display',
'        ELSE',
'            if p_item.attribute_02 = ''HTML'' then',
'                ZT_QR.p_qr_as_html_table(',
'                    p_data => p_param.value,',
'                    p_error_correction => p_item.attribute_01,',
'                    p_module_size_in_px => p_item.attribute_03,',
'                    p_margines => (CASE WHEN p_item.attribute_05 = ''Y'' THEN true ELSE false END)',
'                );',
'            elsif p_item.attribute_02 = ''BMP'' then',
'                ZT_QR.p_qr_as_img_tag_base64(',
'                    p_data => p_param.value,',
'                    p_error_correction => p_item.attribute_01,',
'                    p_image_size_px => p_item.attribute_04,',
'                    p_margines => p_item.attribute_05',
'                );',
'            elsif p_item.attribute_02 = ''SVG'' then',
'                ZT_QR.p_qr_as_svg(',
'                    p_data => p_param.value,',
'                    p_error_correction => p_item.attribute_01,',
'                    p_module_size_px => p_item.attribute_03,',
'                    p_margines_yn => p_item.attribute_05,',
'                    p_module_color => p_item.attribute_06,',
'                    p_background_color => p_item.attribute_07,',
'                    p_module_rounded_px => p_item.attribute_08',
'                );',
'                ',
'                --htp.p(''<br><br>Download'');',
'            else',
'                htp.prn(''Error - unsupported display type.'');',
'            end if;',
'            ',
'        end if;',
'        ',
'    end if;',
'',
'    p_result.is_navigable := false;',
'    ',
'END render_qrcode;'))
,p_api_version=>2
,p_render_function=>'render_qrcode'
,p_standard_attributes=>'VISIBLE:FORM_ELEMENT:SESSION_STATE:SOURCE'
,p_substitute_attributes=>true
,p_subscribe_plugin_settings=>true
,p_help_text=>wwv_flow_string.join(wwv_flow_t_varchar2(
'QR plugin version 2.0.0',
'Usage and details on GitHub',
'https://github.com/zorantica/plsql-qr-code'))
,p_version_identifier=>'2.0.0.0'
,p_about_url=>'https://github.com/zorantica/plsql-qr-code'
);
wwv_flow_api.create_plugin_attribute(
 p_id=>wwv_flow_api.id(19195010070495085)
,p_plugin_id=>wwv_flow_api.id(19166686046667066)
,p_attribute_scope=>'COMPONENT'
,p_attribute_sequence=>1
,p_display_sequence=>10
,p_prompt=>'Error correction level'
,p_attribute_type=>'SELECT LIST'
,p_is_required=>true
,p_default_value=>'L'
,p_supported_ui_types=>'DESKTOP'
,p_supported_component_types=>'APEX_APPLICATION_PAGE_ITEMS:APEX_APPL_PAGE_IG_COLUMNS'
,p_is_translatable=>false
,p_lov_type=>'STATIC'
);
wwv_flow_api.create_plugin_attr_value(
 p_id=>wwv_flow_api.id(19195587333496851)
,p_plugin_attribute_id=>wwv_flow_api.id(19195010070495085)
,p_display_sequence=>10
,p_display_value=>'L - Low (7% of data)'
,p_return_value=>'L'
);
wwv_flow_api.create_plugin_attr_value(
 p_id=>wwv_flow_api.id(19195953361499270)
,p_plugin_attribute_id=>wwv_flow_api.id(19195010070495085)
,p_display_sequence=>20
,p_display_value=>'M - Medium (15% of data)'
,p_return_value=>'M'
);
wwv_flow_api.create_plugin_attr_value(
 p_id=>wwv_flow_api.id(19196401846501124)
,p_plugin_attribute_id=>wwv_flow_api.id(19195010070495085)
,p_display_sequence=>30
,p_display_value=>'Q - Quartile (25% of data)'
,p_return_value=>'Q'
);
wwv_flow_api.create_plugin_attr_value(
 p_id=>wwv_flow_api.id(19196767711502010)
,p_plugin_attribute_id=>wwv_flow_api.id(19195010070495085)
,p_display_sequence=>40
,p_display_value=>'H - High (30% of data)'
,p_return_value=>'H'
);
wwv_flow_api.create_plugin_attribute(
 p_id=>wwv_flow_api.id(19203464560101742)
,p_plugin_id=>wwv_flow_api.id(19166686046667066)
,p_attribute_scope=>'COMPONENT'
,p_attribute_sequence=>2
,p_display_sequence=>20
,p_prompt=>'Display Type'
,p_attribute_type=>'SELECT LIST'
,p_is_required=>true
,p_default_value=>'SVG'
,p_supported_ui_types=>'DESKTOP'
,p_supported_component_types=>'APEX_APPLICATION_PAGE_ITEMS:APEX_APPL_PAGE_IG_COLUMNS'
,p_is_translatable=>false
,p_lov_type=>'STATIC'
);
wwv_flow_api.create_plugin_attr_value(
 p_id=>wwv_flow_api.id(15301637796637240)
,p_plugin_attribute_id=>wwv_flow_api.id(19203464560101742)
,p_display_sequence=>5
,p_display_value=>'SVG image'
,p_return_value=>'SVG'
);
wwv_flow_api.create_plugin_attr_value(
 p_id=>wwv_flow_api.id(19204051603103163)
,p_plugin_attribute_id=>wwv_flow_api.id(19203464560101742)
,p_display_sequence=>10
,p_display_value=>'HTML Table'
,p_return_value=>'HTML'
);
wwv_flow_api.create_plugin_attr_value(
 p_id=>wwv_flow_api.id(19204426782104803)
,p_plugin_attribute_id=>wwv_flow_api.id(19203464560101742)
,p_display_sequence=>20
,p_display_value=>'BMP Image'
,p_return_value=>'BMP'
);
wwv_flow_api.create_plugin_attribute(
 p_id=>wwv_flow_api.id(19206265959135863)
,p_plugin_id=>wwv_flow_api.id(19166686046667066)
,p_attribute_scope=>'COMPONENT'
,p_attribute_sequence=>3
,p_display_sequence=>30
,p_prompt=>'Module size'
,p_attribute_type=>'NUMBER'
,p_is_required=>true
,p_default_value=>'8'
,p_display_length=>5
,p_max_length=>2
,p_unit=>'pixels'
,p_supported_ui_types=>'DESKTOP'
,p_supported_component_types=>'APEX_APPLICATION_PAGE_ITEMS'
,p_is_translatable=>false
,p_depending_on_attribute_id=>wwv_flow_api.id(19203464560101742)
,p_depending_on_has_to_exist=>true
,p_depending_on_condition_type=>'IN_LIST'
,p_depending_on_expression=>'HTML,SVG'
);
wwv_flow_api.create_plugin_attribute(
 p_id=>wwv_flow_api.id(19207654617152716)
,p_plugin_id=>wwv_flow_api.id(19166686046667066)
,p_attribute_scope=>'COMPONENT'
,p_attribute_sequence=>4
,p_display_sequence=>40
,p_prompt=>'Image size'
,p_attribute_type=>'NUMBER'
,p_is_required=>true
,p_display_length=>5
,p_max_length=>4
,p_unit=>'pixels'
,p_is_translatable=>false
,p_depending_on_attribute_id=>wwv_flow_api.id(19203464560101742)
,p_depending_on_has_to_exist=>true
,p_depending_on_condition_type=>'EQUALS'
,p_depending_on_expression=>'BMP'
);
wwv_flow_api.create_plugin_attribute(
 p_id=>wwv_flow_api.id(19208230004156464)
,p_plugin_id=>wwv_flow_api.id(19166686046667066)
,p_attribute_scope=>'COMPONENT'
,p_attribute_sequence=>5
,p_display_sequence=>15
,p_prompt=>'Margines'
,p_attribute_type=>'CHECKBOX'
,p_is_required=>true
,p_default_value=>'N'
,p_supported_ui_types=>'DESKTOP:JQM_SMARTPHONE'
,p_supported_component_types=>'APEX_APPLICATION_PAGE_ITEMS'
,p_is_translatable=>false
);
wwv_flow_api.create_plugin_attribute(
 p_id=>wwv_flow_api.id(15310884392722565)
,p_plugin_id=>wwv_flow_api.id(19166686046667066)
,p_attribute_scope=>'COMPONENT'
,p_attribute_sequence=>6
,p_display_sequence=>60
,p_prompt=>'Module color'
,p_attribute_type=>'TEXT'
,p_is_required=>false
,p_supported_ui_types=>'DESKTOP:JQM_SMARTPHONE'
,p_supported_component_types=>'APEX_APPLICATION_PAGE_ITEMS'
,p_is_translatable=>false
,p_depending_on_attribute_id=>wwv_flow_api.id(19203464560101742)
,p_depending_on_has_to_exist=>true
,p_depending_on_condition_type=>'EQUALS'
,p_depending_on_expression=>'SVG'
,p_examples=>'black | red | rgb(255, 0, 0) | #FF0000'
,p_help_text=>'Module color (as named color, rgb function or HEX# notification).'
);
wwv_flow_api.create_plugin_attribute(
 p_id=>wwv_flow_api.id(15311493488724950)
,p_plugin_id=>wwv_flow_api.id(19166686046667066)
,p_attribute_scope=>'COMPONENT'
,p_attribute_sequence=>7
,p_display_sequence=>70
,p_prompt=>'Background color'
,p_attribute_type=>'TEXT'
,p_is_required=>false
,p_is_translatable=>false
,p_depending_on_attribute_id=>wwv_flow_api.id(19203464560101742)
,p_depending_on_has_to_exist=>true
,p_depending_on_condition_type=>'EQUALS'
,p_depending_on_expression=>'SVG'
);
wwv_flow_api.create_plugin_attribute(
 p_id=>wwv_flow_api.id(15320807577751337)
,p_plugin_id=>wwv_flow_api.id(19166686046667066)
,p_attribute_scope=>'COMPONENT'
,p_attribute_sequence=>8
,p_display_sequence=>80
,p_prompt=>'Rounded module edges'
,p_attribute_type=>'NUMBER'
,p_is_required=>false
,p_unit=>'pixel'
,p_supported_ui_types=>'DESKTOP:JQM_SMARTPHONE'
,p_supported_component_types=>'APEX_APPLICATION_PAGE_ITEMS'
,p_is_translatable=>false
);
end;
/
begin
wwv_flow_api.import_end(p_auto_install_sup_obj => nvl(wwv_flow_application_install.get_auto_install_sup_obj, false), p_is_component_import => true);
commit;
end;
/
set verify on feedback on define on
prompt  ...done
