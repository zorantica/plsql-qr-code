set define off verify off feedback off
whenever sqlerror exit sql.sqlcode rollback
--------------------------------------------------------------------------------
--
-- ORACLE Application Express (APEX) export file
--
-- You should run the script connected to SQL*Plus as the Oracle user
-- APEX_050100 or as the owner (parsing schema) of the application.
--
-- NOTE: Calls to apex_application_install override the defaults below.
--
--------------------------------------------------------------------------------
begin
wwv_flow_api.import_begin (
 p_version_yyyy_mm_dd=>'2016.08.24'
,p_release=>'5.1.1.00.08'
,p_default_workspace_id=>1962282725390507
,p_default_application_id=>1000
,p_default_owner=>'AMARTA'
);
end;
/
prompt --application/ui_types
begin
null;
end;
/
prompt --application/shared_components/plugins/item_type/zttech_qr_code
begin
wwv_flow_api.create_plugin(
 p_id=>wwv_flow_api.id(9108633849246785)
,p_plugin_type=>'ITEM TYPE'
,p_name=>'EU.ZTTECH.QRCODE'
,p_display_name=>'QRCode'
,p_supported_ui_types=>'DESKTOP'
,p_supported_component_types=>'APEX_APPLICATION_PAGE_ITEMS'
,p_plsql_code=>wwv_flow_string.join(wwv_flow_t_varchar2(
'FUNCTION render_qrcode(p_item                IN apex_plugin.t_page_item,',
'                       p_plugin              IN apex_plugin.t_plugin,',
'                       p_value               IN VARCHAR2,',
'                       p_is_readonly         IN BOOLEAN,',
'                       p_is_printer_friendly IN BOOLEAN)',
'  RETURN apex_plugin.t_page_item_render_result IS',
'',
'    l_result apex_plugin.t_page_item_render_result;',
'',
'BEGIN',
'    if p_value is null then',
'        htp.p(''no data'');',
'    else',
'',
'        -- Printer Friendly Display',
'        IF p_is_printer_friendly THEN',
'            apex_plugin_util.print_display_only(p_item_name        => p_item.name,',
'                                                p_display_value    => p_value,',
'                                                p_show_line_breaks => FALSE,',
'                                                p_escape           => TRUE,',
'                                                p_attributes       => p_item.element_attributes);',
'        -- Read Only Display',
'        ELSIF p_is_readonly THEN',
'            apex_plugin_util.print_hidden_if_readonly(p_item_name           => p_item.name,',
'                                                      p_value               => p_value,',
'                                                      p_is_readonly         => p_is_readonly,',
'                                                      p_is_printer_friendly => p_is_printer_friendly);',
'',
'        -- Normal Display',
'        ELSE',
'            if p_item.attribute_02 = ''HTML'' then',
'                ZT_QR.p_qr_as_html_table(',
'                    p_data => p_value,',
'                    p_error_correction => p_item.attribute_01,',
'                    p_module_size_in_px => p_item.attribute_03,',
'                    p_margines => (CASE WHEN p_item.attribute_05 = ''Y'' THEN true ELSE false END)',
'                );',
'            elsif p_item.attribute_02 = ''BMP'' then',
'                ZT_QR.p_qr_as_img_tag_base64(',
'                    p_data => p_value,',
'                    p_error_correction => p_item.attribute_01,',
'                    p_image_size_px => p_item.attribute_04,',
'                    p_margines => p_item.attribute_05',
'                );',
'            else',
'                htp.prn(''Error - unsupported display type.'');',
'            end if;',
'        end if;',
'        ',
'    end if;',
'',
'    l_result.is_navigable := false;',
'    RETURN l_result;',
'',
'END render_qrcode;'))
,p_api_version=>1
,p_render_function=>'render_qrcode'
,p_standard_attributes=>'VISIBLE:FORM_ELEMENT:SESSION_STATE:SOURCE'
,p_substitute_attributes=>true
,p_subscribe_plugin_settings=>true
,p_help_text=>'QR plugin version 1.0.0'
,p_version_identifier=>'1.0.0.0'
,p_about_url=>'http://www.zt-tech.eu/download.html'
,p_files_version=>29
);
wwv_flow_api.create_plugin_attribute(
 p_id=>wwv_flow_api.id(9136957873074804)
,p_plugin_id=>wwv_flow_api.id(9108633849246785)
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
 p_id=>wwv_flow_api.id(9137535136076570)
,p_plugin_attribute_id=>wwv_flow_api.id(9136957873074804)
,p_display_sequence=>10
,p_display_value=>'L - Low (7% of data)'
,p_return_value=>'L'
);
wwv_flow_api.create_plugin_attr_value(
 p_id=>wwv_flow_api.id(9137901164078989)
,p_plugin_attribute_id=>wwv_flow_api.id(9136957873074804)
,p_display_sequence=>20
,p_display_value=>'M - Medium (15% of data)'
,p_return_value=>'M'
);
wwv_flow_api.create_plugin_attr_value(
 p_id=>wwv_flow_api.id(9138349649080843)
,p_plugin_attribute_id=>wwv_flow_api.id(9136957873074804)
,p_display_sequence=>30
,p_display_value=>'Q - Quartile (25% of data)'
,p_return_value=>'Q'
);
wwv_flow_api.create_plugin_attr_value(
 p_id=>wwv_flow_api.id(9138715514081729)
,p_plugin_attribute_id=>wwv_flow_api.id(9136957873074804)
,p_display_sequence=>40
,p_display_value=>'H - High (30% of data)'
,p_return_value=>'H'
);
wwv_flow_api.create_plugin_attribute(
 p_id=>wwv_flow_api.id(9145412362681461)
,p_plugin_id=>wwv_flow_api.id(9108633849246785)
,p_attribute_scope=>'COMPONENT'
,p_attribute_sequence=>2
,p_display_sequence=>20
,p_prompt=>'Display Type'
,p_attribute_type=>'SELECT LIST'
,p_is_required=>true
,p_default_value=>'HTML'
,p_supported_ui_types=>'DESKTOP'
,p_supported_component_types=>'APEX_APPLICATION_PAGE_ITEMS:APEX_APPL_PAGE_IG_COLUMNS'
,p_is_translatable=>false
,p_lov_type=>'STATIC'
);
wwv_flow_api.create_plugin_attr_value(
 p_id=>wwv_flow_api.id(9145999405682882)
,p_plugin_attribute_id=>wwv_flow_api.id(9145412362681461)
,p_display_sequence=>10
,p_display_value=>'HTML Table'
,p_return_value=>'HTML'
);
wwv_flow_api.create_plugin_attr_value(
 p_id=>wwv_flow_api.id(9146374584684522)
,p_plugin_attribute_id=>wwv_flow_api.id(9145412362681461)
,p_display_sequence=>20
,p_display_value=>'BMP Image'
,p_return_value=>'BMP'
);
wwv_flow_api.create_plugin_attribute(
 p_id=>wwv_flow_api.id(9148213761715582)
,p_plugin_id=>wwv_flow_api.id(9108633849246785)
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
,p_supported_component_types=>'APEX_APPLICATION_PAGE_ITEMS:APEX_APPL_PAGE_IG_COLUMNS'
,p_is_translatable=>false
,p_depending_on_attribute_id=>wwv_flow_api.id(9145412362681461)
,p_depending_on_has_to_exist=>true
,p_depending_on_condition_type=>'EQUALS'
,p_depending_on_expression=>'HTML'
);
wwv_flow_api.create_plugin_attribute(
 p_id=>wwv_flow_api.id(9149602419732435)
,p_plugin_id=>wwv_flow_api.id(9108633849246785)
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
,p_depending_on_attribute_id=>wwv_flow_api.id(9145412362681461)
,p_depending_on_has_to_exist=>true
,p_depending_on_condition_type=>'EQUALS'
,p_depending_on_expression=>'BMP'
);
wwv_flow_api.create_plugin_attribute(
 p_id=>wwv_flow_api.id(9150177806736183)
,p_plugin_id=>wwv_flow_api.id(9108633849246785)
,p_attribute_scope=>'COMPONENT'
,p_attribute_sequence=>5
,p_display_sequence=>50
,p_prompt=>'Margines'
,p_attribute_type=>'CHECKBOX'
,p_is_required=>true
,p_default_value=>'N'
,p_supported_ui_types=>'DESKTOP'
,p_supported_component_types=>'APEX_APPLICATION_PAGE_ITEMS:APEX_APPL_PAGE_IG_COLUMNS'
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
