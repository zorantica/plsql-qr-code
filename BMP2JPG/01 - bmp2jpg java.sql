create or replace and compile java source named Bmp2Jpeg
as

import oracle.sql.BLOB;
import oracle.sql.*;
import oracle.jdbc.driver.*;
import java.sql.*;
import javax.imageio.ImageIO;
import java.awt.image.BufferedImage;
import java.io.ByteArrayOutputStream;
import java.io.File;
import java.io.FileOutputStream;
import java.io.OutputStream;
import java.io.*;
import java.util.*;
import javax.imageio.ImageIO;
import java.awt.image.BufferedImage;
import java.sql.Blob;

public class Bmp2JPG {

 static OracleDriver ora = new OracleDriver();
 static Connection conn;
 static ByteArrayOutputStream out;
 static {
  try {
   conn = ora.defaultConnection();
  } catch (Exception ex) {}
 }
 public static ByteArrayOutputStream TO_JPG(java.sql.Blob blob) throws Exception {
  ByteArrayOutputStream outputStream = new ByteArrayOutputStream();
  BufferedImage image = ImageIO.read(blob.getBinaryStream());
  ImageIO.write(image, "jpeg", outputStream);


  return outputStream;
 }

 public static oracle.sql.BLOB convert2JPG(oracle.sql.BLOB value) throws Exception {

  if (conn == null) conn = ora.defaultConnection();
  BLOB retBlob = BLOB.createTemporary(conn, true, oracle.sql.BLOB.DURATION_SESSION);

  ByteArrayOutputStream out = new ByteArrayOutputStream();
  out = Bmp2JPG.TO_JPG(value);

  try {
   java.io.OutputStream outStr = retBlob.setBinaryStream(0);
   outStr.write(out.toByteArray());
   outStr.flush();
  } finally {
   out.close();
  }
  return retBlob;
 }
}


