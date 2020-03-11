DECLARE
    lbQR blob;
    
BEGIN
    lbQR := f_bmp2jpg( 
		ZT_QR.F_QR_AS_BMP(
			p_data => 'HTTP://WWW.ZT-TECH.EU',
			p_error_correction => 'M')
		);
    
    ZT_QR.p_save_file(lbQR, 'qr.jpg', 'E_SHARED');
END;

