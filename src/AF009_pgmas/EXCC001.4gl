################################################################################
#Proyecto          => Sistema de AFORE.( MEXICO )                              #
#Propietario       => E.F.P.                                                   #
#Programa          => EXCC001                                                  #
#Descripcion       => CATALOGO DE CONTROL PROCESO.                             #
#Fecha             => 30 febrero 2001.                                         #
#Por               => MIGUEL ANGEL HERNANDEZ MARTINEZ                          #
#Actualizado       => 17 de septiembre de 2001                                 #
#Actualizado       => 06 de junio de 2002.                                     #
#Sistema           => EXC                                                      #
#Modifico          => JOEL PAZ CRUZ.                                           #
#Fecha             => 08/DICIEMBRE/2011.                                       #
#                  => SE ANEXO VALIDACIONES DE PERFILAMIENTO Y SEGURIDAD.      #
#                     MANEJO DE ERRORES Y LOGS.                                #
################################################################################

DATABASE safre_af

GLOBALS
   DEFINE g_param_dev  RECORD LIKE seg_modulo.*

   DEFINE g_reg  RECORD LIKE dis_ctrl_proceso.* 

   DEFINE hoy           DATE,
          usuario       CHAR(08),
          cla_where     CHAR(300),
          sel_where     CHAR(300),
          g_lista       CHAR(300),
          g_impre       CHAR(300),
          hora          CHAR(08)

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
#####################################################################
MAIN
   OPTIONS PROMPT LINE LAST,
      INPUT WRAP,
      ACCEPT KEY control-o

   DEFER INTERRUPT

   CALL STARTLOG("/safre/exc/logs/EXCC001.log")
   WHENEVER ERROR CALL graba_logs_err

   CALL inicio()
   CALL proceso()

   LET vch_letrero = "Programa : ",
                     r_sesion.privilegio using "<<<<&",
                     " - ", programa clipped,
                     "  finaliza correctamente "
   CALL Graba_Log('2002', '1', vch_letrero, " ", " ", TRUE)

END MAIN
#####################################################################
FUNCTION inicio()
   SELECT ruta_listados,
          USER
   INTO   g_param_dev.ruta_listados,
          usuario
   FROM   seg_modulo
   WHERE  modulo_cod = "exc"

   CALL Sca_Valida(1)

END FUNCTION
#####################################################################
FUNCTION proceso()
   LET HOY = TODAY

   OPEN WINDOW ventana_1 AT 3,3 WITH FORM "EXCC0011" ATTRIBUTE( BORDER)
   DISPLAY " EXCC001              CATALOGO DE CONTROL PROCESO                              " AT 3,1 ATTRIBUTE(REVERSE) 
   DISPLAY HOY USING "dd-mm-yyyy" AT 3,66 ATTRIBUTE(REVERSE)

   MENU "CATALOGO CONTROL PROCESO"
      COMMAND "Consulta" "Consulta Control proceso"
         LET r_sesion.privilegio = 1811 --EXCC001C
         CALL Sca_Valida(2)
         LET r_sesion.privilegio = vin_priv_ini

         CALL Consulta()
      COMMAND "Salir" "Salir del Programa"
         CALL Sca_Valida(2)

         EXIT MENU
   END MENU

   CLOSE WINDOW ventana_1
END FUNCTION
#####################################################################
FUNCTION Inicializa()
   DISPLAY BY NAME g_reg.*
END FUNCTION
#####################################################################
FUNCTION Consulta()

   OPEN WINDOW ventana_2 AT 3,3 WITH FORM "EXCC0011" ATTRIBUTE(BORDER) 
   DISPLAY " (Enter) Consulta " AT 1,1 ATTRIBUTE(REVERSE)
   DISPLAY " EXCC001              CATALOGO DE CONTROL PROCESO                              " AT 3,1 ATTRIBUTE(REVERSE) 
   DISPLAY HOY USING "dd-mm-yyyy" AT 3,66 ATTRIBUTE(REVERSE)

   LET int_flag = FALSE

   CONSTRUCT cla_where ON fecha_proceso,
                          proceso_cod,
                          folio,
                          etapa_cod

                     FROM fecha_proceso,
                          proceso_cod,
                          folio,
                          etapa_cod

      ON KEY (control-m)
         CALL Sca_Valida(2)

         LET int_flag = FALSE
         EXIT CONSTRUCT
      ON KEY (control-c)
         CALL Sca_Valida(2)

         LET int_flag = TRUE
         EXIT CONSTRUCT
   END CONSTRUCT

   IF int_flag = TRUE THEN
      LET int_flag = FALSE
      ERROR "BUSQUEDA CANCELADA..."
      SLEEP 2
      ERROR ""
      CLEAR SCREEN
      CLOSE WINDOW ventana_2
      RETURN
   END IF

   LET sel_where = "SELECT * FROM dis_ctrl_proceso WHERE ",
                    cla_where CLIPPED,
                   " ORDER BY 1,4 "

   PREPARE query FROM sel_where

   DECLARE cursor_1 SCROLL CURSOR  WITH HOLD FOR query

   OPEN cursor_1

   FETCH cursor_1 INTO g_reg.*

   IF SQLCA.SQLCODE <> 0 THEN
      ERROR "Registro no encontrado."
      SLEEP 2
      ERROR ""
      CLEAR SCREEN
      CLOSE WINDOW ventana_2
      RETURN
   ELSE
      CALL Inicializa()

      CALL Botones()

      RETURN
   END IF

   CLEAR SCREEN
END FUNCTION
#####################################################################
FUNCTION Botones()

   MENU "Ingreso a botones."
      COMMAND "Primero" "Primer registro de la tabla."
         CALL Sca_Valida(2)

         CALL Primero()
      COMMAND "Siguiente" "Siguiente registro de la tabla."
         CALL Sca_Valida(2)

         CALL Siguiente()
      COMMAND "Anterior" "Anterior registro de la tabla."
         CALL Sca_Valida(2)

         CALL Anterior()
      COMMAND "Ultimo" "Ultimo registro de la tabla."
         CALL Sca_Valida(2)

         CALL Ultimo()
      COMMAND "Impresion" "Impresion de los registros."
         LET r_sesion.privilegio = 1812 --EXCC001CX
         CALL Sca_Valida(2)
         LET r_sesion.privilegio = vin_priv_ini

         CALL Impresion()
      COMMAND KEY("L") "saLir" "Salir de los botones."
         CALL Sca_Valida(2)

         EXIT MENU
   END MENU

   CLEAR SCREEN
   CLOSE WINDOW ventana_2

END FUNCTION
#######################################################################
FUNCTION Primero()
   FETCH FIRST cursor_1 INTO g_reg.*

   IF SQLCA.SQLCODE <> 0 THEN
      ERROR "Registro no encontrado."
      RETURN
   ELSE
      CALL Inicializa()
      RETURN
   END IF
END FUNCTION
#####################################################################
FUNCTION Siguiente()
   FETCH NEXT cursor_1 INTO g_reg.*

   IF SQLCA.SQLCODE <> 0 THEN
      ERROR "Registro no encontrado."
      RETURN
   ELSE
      CALL Inicializa()
      RETURN
   END IF
END FUNCTION
#####################################################################
FUNCTION Anterior()
   FETCH PREVIOUS cursor_1 INTO g_reg.*

   IF SQLCA.SQLCODE <> 0 THEN
      ERROR "Registro no encontrado."
      RETURN
   ELSE
      CALL Inicializa()
      RETURN
   END IF
END FUNCTION
#####################################################################
FUNCTION Ultimo()
   FETCH LAST cursor_1 INTO g_reg.*

   IF SQLCA.SQLCODE = NOTFOUND THEN
      ERROR "Registro no encontrado."
      RETURN
   ELSE
      CALL Inicializa()
      RETURN
   END IF
END FUNCTION
#####################################################################
FUNCTION Impresion()
   DEFINE i INTEGER

   LET hora = TIME

   LET g_impre = g_param_dev.ruta_listados CLIPPED,"/",usuario CLIPPED,
                 ".IMPCONPROCESO",hoy USING "dd-mm-yyyy","_",hora CLIPPED

   START REPORT rpt_tabcity TO g_impre

      FOREACH cursor_1 INTO g_reg.*
         OUTPUT TO REPORT rpt_tabcity(g_reg.*)
      END FOREACH

      INITIALIZE g_reg.* TO NULL

   FINISH REPORT rpt_tabcity

   ERROR "LISTADO GENERADO..."
   SLEEP 2
   ERROR ""

   LET g_lista = "lp ",g_impre
   RUN g_lista
END FUNCTION
#####################################################################
REPORT rpt_tabcity(g_reg)

   DEFINE g_reg RECORD  LIKE dis_ctrl_proceso.*

   OUTPUT
      TOP MARGIN 1
      BOTTOM MARGIN 0
      LEFT MARGIN 0 
      RIGHT MARGIN 0
      PAGE LENGTH 60

   FORMAT

   PAGE HEADER

      PRINT '\033e\033(10U\033&l1O\033&k2S\033&l12d'
      PRINT COLUMN 02,"EXCC001 ",
            COLUMN 70," LISTADO DE CATALOGOS DE CONTROL PROCESO ",
            COLUMN 165, TODAY USING "dd-mm-yyyy"
      SKIP 3 LINE 

      PRINT COLUMN 01,"F. Proceso",
            COLUMN 12,"Cod.Pro.",
            COLUMN 21,"Etapa",
            COLUMN 27,"Hora Ini.",
            COLUMN 37,"Hora fin",
            COLUMN 46,"Parametro 1",
            COLUMN 60,"Parametro 2",
            COLUMN 75,"Parametro 3",
            COLUMN 90,"Parametro 4",
            COLUMN 105,"Parametro 5",
            COLUMN 120,"Usuario",
            COLUMN 150,"Resultado"

      PRINT COLUMN 01,"______________________________________________________________________________________________________________________________________________________________________________"
      SKIP 1 LINE

   ON EVERY ROW
      PRINT COLUMN 01,g_reg.fecha_proceso USING "DD/MM/YYYY",
            COLUMN 14,g_reg.proceso_cod ,
            COLUMN 21,g_reg.etapa_cod,
            COLUMN 27,g_reg.hora_inicial,
            COLUMN 37,g_reg.hora_final,
            COLUMN 46,g_reg.parametro1,
            COLUMN 60,g_reg.parametro2,
            COLUMN 75,g_reg.parametro3,
            COLUMN 90,g_reg.parametro4,
            COLUMN 105,g_reg.parametro5,
            COLUMN 120,g_reg.usuario,
            COLUMN 130,g_reg.resultado

   PAGE TRAILER
      SKIP 2 LINE
      PRINT COLUMN 60," Pagina : ",PAGENO USING "<<<<<"

   ON LAST ROW
      SKIP 2 LINE
      PRINT COLUMN 02,"Total de registros : ",COUNT(*) USING "<<<<<"
END REPORT

#Sca_Valida     Funcion que realiza las validaciones para SCA.  Puede
#               recibir 2 valores en el parametro 'origen':
#               1 = carga lo parametros iniciales en el programa que
#                   sirven para el SCA.  Registra en tabla LOG
#               2 = realiza las validaciones (de sesion, de privilegio, de 
#                   perfiles) cada vez que el usuario interactua en el programa
#               Al ejecutar las SP, se antepone la base de datos
FUNCTION Sca_Valida(origen)
DEFINE
    origen         SMALLINT,
    vsm_sw1        SMALLINT,
    vsm_sw2        SMALLINT,
    vin_modulo     INTEGER,
    vch_sesion     CHAR(100)

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
         LET vin_priv_ini = 1810
         LET r_sesion.privilegio = vin_priv_ini
         LET vch_version_id = '0'
         LET vin_product_id = 21

         LET v_exe_fn = 'EXECUTE PROCEDURE safre_seg:Carga_Parametros_sca(?,?,?,?,?,?,?) '
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
         LET v_exe_fn = 'EXECUTE PROCEDURE safre_seg:sp_sca_valida(?,?,?,?,?,?,?,?,?,?) '
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

   LET v_today 	      = TODAY USING "mmm dd yyyy" 	  
   LET v_time         = CURRENT 	
   LET v_des_err      = ERR_GET(v_cod_err)
   LET v_signature_id = '6001'
   LET v_severity_id  = '7'

   LET v_procedure = "EXECUTE PROCEDURE safre_seg:sp_graba_logs_err(?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?) "

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

   LET vch_ip_login = r_sesion.ip_login
   LET x = 0
   LET vch_fecha = TODAY using "mmm dd yyyy"
   LET vts_hora = CURRENT
   LET v_exe_fn = 'EXECUTE PROCEDURE safre_seg:graba_log(?,?,?,?,?,?,?,?,?,?,?,?,?) '
   PREPARE sp_grabalog FROM v_exe_fn
   EXECUTE sp_grabalog USING vin_product_id, vch_signature, vch_severity,
                             vch_letrero, vch_dato1, vch_dato2,
                             x, vch_ip_login, programa, r_sesion.usuario,
                             vch_version_id, vch_fecha, vts_hora
   INTO vsm_swlog, vch_letrero

   IF vsm_swlog = FALSE THEN
      CALL ERRORLOG(vch_letrero)
   END IF

END FUNCTION
