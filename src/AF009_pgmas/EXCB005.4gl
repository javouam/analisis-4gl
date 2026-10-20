#****************************************************************************#
#Proyecto      => safre_af                                                   #
#Programa      => EXCB005                                                    #
#Descripcion   => PARAMETRO DE LIQUIDACION DEV. DE PAG. EN EXC. BATCH        #
#Modifico          => JOEL PAZ CRUZ.                                         #
#Fecha             => 08/DICIEMBRE/2011.                                     #
#                  => SE ANEXO VALIDACIONES DE PERFILAMIENTO Y SEGURIDAD.    #
#                     MANEJO DE ERRORES Y LOGS.                              #
#****************************************************************************#
#  Junio 2012  => Agregar nvo programa de carga EXCB106 y omitir el EXCB006. #
#                 rq19435_PJF                                                #
##############################################################################
# Diciembre 2015 => Integrar la validacion de precios por fn_precio_dia      #
#                    RQ25372_PJF                                             #
##############################################################################
DATABASE  safre_af
GLOBALS
  DEFINE g_reg      RECORD
           folio             INTEGER,
           fecha_liquidacion DATE
         END RECORD,
         gparam_dev RECORD LIKE seg_modulo.*,
         hoy               DATE,
         usuario           CHAR(08),
         opc               CHAR(01),
         ejecuta           CHAR(300),
         hora_inicial      CHAR(08),
         hora_final        CHAR(08),
         parametro         CHAR(3),
         vresultado        CHAR(40),
         x_mes             INTEGER,
         x_ano             INTEGER,
         x_fecha_proceso   DATE,
         hoy2              DATE,
         dias              INTEGER

  ## Globales para SCA
  DEFINE
         r_te_cef_log          RECORD LIKE safre_seg:te_cef_log.*,
         r_sesion RECORD
             sesion            CHAR(100),
             ip_login          CHAR(15),
             usuario           CHAR(12),
             portal            INTEGER,
             privilegio        INTEGER,
             modulo            INTEGER,
             perfiles          CHAR(30),
             aplicativo        CHAR(6),
             sistema           CHAR(30)
         END RECORD,
         vch_parametro         CHAR(300),
         programa              CHAR(20),
         vch_letrero           CHAR(120),
         vch_modulo_uri        CHAR(50),
         vch_version_id        CHAR(5),
         vch_dato1             CHAR(15),
         vch_dato2             CHAR(15),
         vch_ip_login          CHAR(15),
         v_exe_fn              CHAR(300),
         vch_fecha             CHAR(20),
         vts_hora              DATETIME hour TO second,
         vin_cod_sal           INTEGER,
         vin_product_id        INTEGER,
         vin_conta             INTEGER,
         vin_priv_ini          INTEGER,
         vsm_sw                SMALLINT,
         vsm_numarg            SMALLINT,
         vsm_tip_opc           SMALLINT, 
         vsm_status            SMALLINT,
         x                     SMALLINT,
         y                     SMALLINT
  ## Globales para SCA

  ## Globales para LOGS 
    	 DEFINE v_msg_w  char(80)
         DEFINE v_procedure  char(300)
         DEFINE v_ret     integer
         DEFINE op CHAR(1)
         DEFINE key INTEGER
         DEFINE v_txt CHAR(200)
         DEFINE v_cod_err INTEGER
         DEFINE v_today char(20)
         DEFINE v_time DATETIME HOUR TO SECOND
         DEFINE v_window SMALLINT
  ## Globales para LOGS 

END GLOBALS
#*********************************************************************

MAIN
  OPTIONS
    PROMPT LINE LAST,
    INPUT WRAP,
    ACCEPT KEY CONTROL-I,
    COMMENT LINE LAST
    DEFER INTERRUPT

  CALL STARTLOG("/safre/exc/logs/EXCB005.log")
  WHENEVER ERROR CALL graba_logs_err

  SELECT *, USER  INTO gparam_dev.*, usuario
    FROM seg_modulo
   WHERE modulo_cod = "exc"

  LET hoy = TODAY

  CALL Sca_Valida(1)

  OPEN WINDOW ventana1 AT 2,3 WITH FORM "EXCB0051" ATTRIBUTE(BORDER)

  DISPLAY " EXCB005            DEVOLUCION DE PAGOS EN EXCESO                            " AT 3,1 ATTRIBUTE(REVERSE)

  DISPLAY hoy USING "DD-MM-YYYY" AT 3,66 ATTRIBUTE(REVERSE)

  CALL liquidacion()                                    #rq19435_PJF

  CLOSE WINDOW ventana1

  LET vch_letrero = "Programa : ",
                    r_sesion.privilegio using "<<<<&",
                    " - ", programa clipped,
                    "  finaliza correctamente "

  CALL Graba_Log('2002', '1', vch_letrero, " ", " ", TRUE)

END MAIN
#*********************************************************************

FUNCTION liquidacion()

  DISPLAY "           LIQUIDACION DE RCV Y VIVIENDA                                      " AT 5,1 ATTRIBUTE(REVERSE)

  LET INT_FLAG = FALSE

  INPUT BY NAME g_reg.folio

    AFTER FIELD folio
      CALL Sca_Valida(2)

      IF g_reg.folio IS NULL THEN
         ERROR "Este campo no puede ser nulo"
         NEXT FIELD folio
      END IF

      LET r_sesion.privilegio = 1802--EXCB005RX
      CALL Sca_Valida(2)
      LET r_sesion.privilegio = vin_priv_ini

      SELECT fecha_proceso INTO x_fecha_proceso
        FROM dis_ctrl_proceso
       WHERE folio       = g_reg.folio
         AND etapa_cod   = 1
         AND proceso_cod = "EXC"

      IF SQLCA.SQLCODE <> 0 THEN
         PROMPT "FOLIO DE PAGOS EN EXCESO NO EXISTE" ATTRIBUTE (REVERSE)
                FOR opc ATTRIBUTE (REVERSE)

         CALL Sca_Valida(2)

         NEXT FIELD folio
      END IF

      SELECT "X"
        FROM safre_tmp:exc_devpgo_sdo
       WHERE folio      = g_reg.folio
         AND subcuenta IN (1,2,5,4)
      GROUP BY 1

      IF SQLCA.SQLCODE <> 0 THEN
         PROMPT "FOLIO NO TIENE REGISTROS PARA LIQUIDAR" ATTRIBUTE (REVERSE)
                FOR opc ATTRIBUTE (REVERSE)

         CALL Sca_Valida(2)

         NEXT FIELD folio
      END IF

      SELECT "X"
        FROM dis_ctrl_proceso
       WHERE folio       = g_reg.folio
         AND etapa_cod   = 5
         AND proceso_cod = "EXC"

      IF SQLCA.SQLCODE = 0 THEN
         PROMPT "FOLIO DE PAGOS EN EXCESO YA LIQUIDADO" ATTRIBUTE (REVERSE)
                FOR opc ATTRIBUTE (REVERSE)

         CALL Sca_Valida(2)

         NEXT FIELD folio
      END IF

      SELECT "X"
        FROM dis_cuenta
       WHERE folio = g_reg.folio

      IF SQLCA.SQLCODE = 0 THEN
         PROMPT "FOLIO YA EXISTE EN CATALOGO DE LIQUIDACION " ATTRIBUTE(REVERSE)
                FOR opc ATTRIBUTE (REVERSE)

         CALL Sca_Valida(2)

         NEXT FIELD folio
      END IF

      LET hoy  = TODAY
      LET hoy2 = TODAY

      LET x_mes = MONTH(hoy2)
      LET x_ano = YEAR(hoy2)

      LET hoy2 = MDY(x_mes,1,x_ano)

      LET dias = 15

      LET g_reg.fecha_liquidacion = TODAY

      DISPLAY BY NAME g_reg.fecha_liquidacion

      IF hoy < g_reg.fecha_liquidacion THEN
         PROMPT "FALTAN DIAS PARA LA LIQUIDACION " ATTRIBUTE (REVERSE)
                FOR opc ATTRIBUTE (REVERSE)

         CALL Sca_Valida(2)

         NEXT FIELD folio
      END IF

      EXIT INPUT

    ON KEY(INTERRUPT)
      
       CALL Sca_Valida(2)

       LET INT_FLAG = TRUE
       EXIT INPUT
  END INPUT

  IF INT_FLAG THEN
     LET INT_FLAG = FALSE
     DISPLAY "                                                        " AT 5,1
     CLEAR FORM
     CLEAR SCREEN
     RETURN
  END IF

  CALL ValidarPrecios()

  PROMPT "Desea ejecutar el proceso [S/N] ..." FOR opc

  CALL Sca_Valida(2)

  IF opc MATCHES '[Ss]' THEN
     CALL ejecuta_liquidacion_rcv()
  ELSE
     ERROR "Proceso de liquidacion CANCELADO"
     SLEEP 2
     ERROR ""
  END IF

  DISPLAY "                                                           " AT 5,1

  CLEAR FORM
  CLEAR SCREEN
END FUNCTION

FUNCTION ValidarPrecios()
  DEFINE lqry_prcio_val CHAR(200),
         lfec_viv       CHAR(10),
         lgrupo         SMALLINT,
         lsiefore       SMALLINT,
         lrazon_social  CHAR(50),
         lprecio        DECIMAL(19,6),
         lstatus        SMALLINT,
         lfec_precio    DATE

  LET lqry_prcio_val = "EXECUTE PROCEDURE safre_af:fn_precio_dia(?,?)"
  LET lfec_viv       = MONTH(TODAY) USING "&&" ,"/01/" CLIPPED,
                       YEAR(TODAY) USING "&&&&"

  FOR lgrupo = 1  TO  2

    CASE lgrupo
      WHEN 1 LET lfec_precio = TODAY
      WHEN 2 LET lfec_precio = lfec_viv
    END CASE

    PREPARE sql_prcio_val FROM lqry_prcio_val
    DECLARE cur_prcio_val CURSOR FOR sql_prcio_val
    FOREACH cur_prcio_val USING lgrupo, lfec_precio
                           INTO lsiefore, lrazon_social, lprecio
      LET lstatus = status

      IF lstatus <> 0  THEN
         ERROR " NO EXISTEN PRECIOS PARA GRUPO : ",lgrupo USING "&",
               " De Fecha : ",lfec_precio
         SLEEP 6
         EXIT PROGRAM
      END IF

    END FOREACH

  END FOR

END FUNCTION

FUNCTION ejecuta_liquidacion_rcv()

  LET hora_inicial = TIME
  LET hora_final   = NULL
  LET parametro    = "RCV"
  LET vresultado   = "Iniciando liquidacion de registros "

  INSERT INTO dis_ctrl_proceso 
       VALUES (x_fecha_proceso,         -- fecha_proceso
               "EXC",                   -- proceso_cod
               5,                       -- etapa_cod   -- LIQUIDACION
               hora_inicial,            -- hora_inicial
               hora_final,              -- hora_final
               g_reg.fecha_liquidacion, -- parametro1
               parametro,               -- parametro2
               "",                      -- parametro3
               "",                      -- parametro4
               "",                      -- parametro5
               g_reg.folio,             -- folio
               vresultado,              -- resultado
               usuario                  -- usuario
              )

  IF SQLCA.SQLCODE <> 0 THEN
     ERROR "ERROR AL INSERTA EN TABLA dis_ctrl_proceso Lectura Archivo",STATUS
     SLEEP 4

     LET vch_letrero = "ERROR AL INSERTA EN TABLA dis_ctrl_proceso Lectura ",
                       "Archivo.  Se cierra el programa"
     CALL ERRORLOG(vch_letrero)
     CALL Graba_Log('2002', '1', vch_letrero, " ", " ", TRUE)

     EXIT PROGRAM
  END IF

  ERROR "Ejecutando Lectura y Proceso de Archivo por nohup ..." 
  SLEEP 3
  ERROR ""

  LET ejecuta = "cd ",vch_modulo_uri CLIPPED,
                ";nohup fglgo EXCB106 ",parametro," ",g_reg.folio,
                " '",r_sesion.sesion CLIPPED,"' ",
                " ",r_sesion.modulo CLIPPED," 2>>",
                "/safre/exc/logs/nohup.EXCB106 & "
  RUN ejecuta

  ERROR "El proceso se ejecuto satisfactoriamente por nohup ..."
  SLEEP 2
  ERROR ""

  ERROR "Genera cifras de control excb006_cc en la ruta de rescate."
  SLEEP 4

END FUNCTION
#*********************************************************************

#Sca_Valida     Funcion que realiza las validaciones para SCA.  Puede
#               recibir 2 valores en el parametro 'origen':
#               1 = carga lo parametros iniciales en el programa que
#                   sirven para el SCA.  Registra en tabla LOG
#               2 = realiza las validaciones (de sesion, de privilegio, de 
#                   perfiles) cada vez que el usuario interactua en el programa
FUNCTION Sca_Valida(origen)
DEFINE
    origen         SMALLINT,
    vsm_sw1        SMALLINT,
    vsm_sw2        SMALLINT,
    vin_modulo     INTEGER,
    vch_sesion     CHAR(100)

    DATABASE safre_seg

    CASE origen 
       WHEN 1 
         LET programa = ARG_VAL(0)
         LET vsm_numarg = NUM_ARGS()
         LET r_sesion.modulo = ARG_VAL(vsm_numarg)
         LET vch_sesion = ARG_VAL(vsm_numarg - 1)
         LET r_sesion.sesion = vch_sesion
         LET vch_fecha = TODAY using "mmm dd yyyy"
         LET vts_hora = CURRENT
         LET v_window = TRUE
         LET vin_priv_ini = 1800 --EXCB005
         LET r_sesion.privilegio = vin_priv_ini
         LET vch_version_id = '0'
         LET vin_product_id = 9 --AF-009

         LET v_exe_fn = 'EXECUTE PROCEDURE Carga_Parametros_sca(?,?,?,?,?,?,?) '
         PREPARE sp_cargaparam FROM v_exe_fn
         EXECUTE sp_cargaparam USING vch_sesion, 
                                     programa, 
                                     vin_product_id,
                                     vch_version_id,
                                     r_sesion.privilegio,
                                     vch_fecha,
                                     vts_hora
         INTO vsm_sw1, vsm_sw2, r_sesion.ip_login, r_sesion.usuario,
              r_sesion.portal, r_sesion.perfiles, r_sesion.aplicativo,
              r_sesion.sistema, vch_letrero

         IF vsm_sw1 > 0 OR vsm_sw2 > 0 THEN
            ERROR vch_letrero
            SLEEP 4
            CALL ERRORLOG(vch_letrero)
         END IF
         IF vsm_sw1 > 0 THEN
            EXIT PROGRAM
         END IF

      WHEN 2
         LET v_exe_fn = 'EXECUTE PROCEDURE sp_sca_valida(?,?,?,?,?,?,?,?,?,?) '
         PREPARE sp_valida FROM v_exe_fn
         EXECUTE sp_valida USING programa,
                                 r_sesion.sesion,
                                 r_sesion.ip_login,
                                 r_sesion.usuario,
                                 r_sesion.portal,
                                 r_sesion.privilegio,
                                 r_sesion.modulo,
                                 r_sesion.perfiles,
                                 r_sesion.aplicativo,
                                 r_sesion.sistema
         INTO vsm_sw, vin_cod_sal, vch_letrero, vch_modulo_uri,
              vsm_tip_opc, vin_modulo
         IF vsm_sw <> 0 THEN
            ERROR vch_letrero
            SLEEP 4
            CALL ERRORLOG(vch_letrero)
            IF vin_cod_sal <> 99 THEN
               CALL Graba_Log('3001', '9', vch_letrero, " ", " ", TRUE)
            ELSE
               CALL Graba_Log('3002', '6', vch_letrero, " ", " ", TRUE)
            END IF 
            EXIT PROGRAM vin_cod_sal
         END IF

      OTHERWISE
            LET vch_letrero = 'La rutina Sca_Valida NO recibio parametros',
                              '  Fin de programa inesperado'
            CALL ERRORLOG(vch_letrero)
            EXIT PROGRAM
    END CASE
    DATABASE safre_af

END FUNCTION

#####################################################################
#- Funcion que trata los errores generados en tiempo de ejecucion
#- 1. Graba en el archivo .LOG del programa
#- 2. Graba en la tabla de LOG de informix (te_cef_log)
#- 3. Despliega en pantalla ventana con datos del error,
#-    confirmar con <enter> para continuar
#  4. Se ha agrega WHENEVER ERROR CONTINUE para tabla te_cef_log
#  5. La ventana de ERROR no aplica para el ERROR de conexion a otra 
#     INSTANCIA (var. v_st_err_i), ni error al insert en te_cef_log
#  6. la var. v_window = TRUE muestra ventana de error y confirma usuario 
#  7. la var. v_window = FALSE NO muestra ventana de error para procesos
#     que se ejecutan automaticamente y no tiene interaccion con el usuario 
#####################################################################
FUNCTION graba_logs_err()
DEFINE v_st_err        SMALLINT
DEFINE v_st_err_i      SMALLINT
DEFINE v_des_err       CHAR(120)
DEFINE v_signature_id  CHAR(4)
DEFINE v_severity_id   CHAR(2)

   LET v_cod_err  = SQLCA.SQLCODE LET v_st_err = TRUE LET v_st_err_i = FALSE 

   IF v_cod_err = 0 THEN 
      LET v_st_err = FALSE 
   END IF

   WHENEVER ERROR CONTINUE
   DATABASE safre_seg

   IF SQLCA.SQLCODE <> 0 THEN 
      LET v_st_err_i = TRUE 
      LET v_cod_err  = SQLCA.SQLCODE 
   END IF

   LET v_today 	      = TODAY USING "mmm dd yyyy" 	  
   LET v_time         = CURRENT 	
   LET v_des_err      = ERR_GET(v_cod_err)
   LET v_signature_id = '6001'
   LET v_severity_id  = '7'

   LET v_procedure = "EXECUTE PROCEDURE sp_graba_logs_err(?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?) "

   PREPARE exe_procedure FROM v_procedure
   EXECUTE exe_procedure USING v_today,v_time, r_sesion.ip_login, r_sesion.usuario, programa, v_cod_err, v_des_err, v_st_err, v_st_err_i,
                               r_te_cef_log.cefts_event, vin_product_id, r_te_cef_log.cefch_vendor, v_signature_id, v_severity_id, vch_version_id, r_te_cef_log.cefch_hostname,
                               r_te_cef_log.cefch_event_name, r_te_cef_log.cefch_extension
   INTO  v_ret,v_txt
   IF v_ret <> TRUE THEN
        CALL ERRORLOG(v_txt)
        IF NOT v_st_err_i THEN
           LET v_cod_err = v_ret
           LET v_st_err_i = TRUE	
        END IF
   END IF

   WHILE (v_window = TRUE AND v_st_err_i = FALSE AND (key <> fgl_keyval("RETURN")))
      OPEN WINDOW win_err AT 18,5 WITH 4 ROWS, 70 COLUMNS ATTRIBUTE (BORDER)
      OPTIONS PROMPT LINE LAST, MESSAGE LINE LAST

      IF v_st_err THEN
         LET v_msg_w = "Se ha producido el error: ", v_cod_err using "-<<<<<<<<", ". Por favor contacte a SISTEMAS. "
      ELSE
         LET v_msg_w = "ERROR, Verifique el archivo LOG del programa."
      END IF
      DISPLAY v_msg_w AT 2,2 ATTRIBUTE (REVERSE)
      PROMPT " Presione la tecla <ENTER> para continuar .... " FOR CHAR op
      IF (FGL_LASTKEY() = fgl_keyval("RETURN")) THEN
         EXIT WHILE
      ELSE
         MESSAGE  " !!!! ERROR, debe presionar la tecla <ENTER> !!!! "  SLEEP 3 MESSAGE ""
      END IF
      CLOSE WINDOW win_err
   END WHILE
   IF v_st_err THEN
      LET vch_letrero = "Se ha producido el error: ", v_cod_err using "-<<<<<<<<", ".  Se cierra programa "
   ELSE
       LET vch_letrero = "ERROR, Verifique el archivo LOG del programa. Se cierra programa"
   END IF

   DATABASE safre_af
   WHENEVER ERROR CALL graba_logs_err

   IF NOT v_st_err_i THEN
      CALL Graba_Log('2002', '8', vch_letrero, " ", " ", TRUE)
      EXIT PROGRAM
   END IF
END FUNCTION

FUNCTION Graba_Log(vch_signature, vch_severity, vch_letrero,
                   vch_dato1, vch_dato2, vsm_swlog)
DEFINE
   vch_signature    CHAR(4),
   vch_severity     CHAR(2),
   vch_letrero      CHAR(120),
   vch_dato1        CHAR(15),
   vch_dato2        CHAR(15),
   vsm_swlog        SMALLINT,
   x                SMALLINT

   DATABASE safre_seg

   LET vch_ip_login = r_sesion.ip_login
   LET x = 0
   LET vch_fecha = TODAY using "mmm dd yyyy"
   LET vts_hora = CURRENT
   LET v_exe_fn = 'EXECUTE PROCEDURE graba_log(?,?,?,?,?,?,?,?,?,?,?,?,?) '
   PREPARE sp_grabalog FROM v_exe_fn
   EXECUTE sp_grabalog USING vin_product_id, vch_signature, vch_severity,
                             vch_letrero, vch_dato1, vch_dato2,
                             x, vch_ip_login, programa, r_sesion.usuario,
                             vch_version_id, vch_fecha, vts_hora
   INTO vsm_swlog, vch_letrero

   IF vsm_swlog = FALSE THEN
      CALL ERRORLOG(vch_letrero)
   END IF

   DATABASE safre_af

END FUNCTION
