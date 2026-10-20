###############################################################################
#  Project        : Sistema Afores (SURA)                                     # 
#  Owner          : Afore SURA S.A. de C.V.                                   #
#  Program        : EXCB100                                                   #
#  Author         : PJF                                                       #
#  Date           : 16 de marzo de 2011                                       #
#  Description    : Reverso carga devolucion de pagos en exceso               #
###############################################################################
DATABASE safre_af
GLOBALS
  DEFINE gfolio        INTEGER,
         g_param_exc   RECORD LIKE safre_af:seg_modulo.*,
         g_ruta        CHAR(60),
         ghoy          DATE,
         g_continua    SMALLINT,
         g_user        CHAR(8),
         g_lista       CHAR(200),
         g_nomb_rpt    CHAR(50),
         g_ejecuta     CHAR(1000),
         g_ctas_dsmrca INTEGER,
         g_tot_cza     SMALLINT,
         g_tot_det     INTEGER,
         g_tot_dep     SMALLINT,
         g_tot_sum     SMALLINT,
         g_tot_sdo     INTEGER,
         g_tot_pcs     SMALLINT,
         g_tot_cza_bor SMALLINT,
         g_tot_det_bor INTEGER,
         g_tot_dep_bor SMALLINT,
         g_tot_sum_bor SMALLINT,
         g_tot_sdo_bor INTEGER,
         g_tot_pcs_bor SMALLINT

  ## Globales para SCA
  DEFINE r_te_cef_log          RECORD LIKE safre_seg:te_cef_log.*,
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
  DEFINE v_msg_w               CHAR(80)
  DEFINE v_procedure           CHAR(300)
  DEFINE v_ret                 INTEGER
  DEFINE op                    CHAR(01)
  DEFINE key                   INTEGER
  DEFINE v_txt                 CHAR(200)
  DEFINE v_cod_err             INTEGER
  DEFINE v_today               CHAR(20)
  DEFINE v_time                DATETIME HOUR TO SECOND
  DEFINE v_window              SMALLINT
  ## Globales para LOGS

END GLOBALS

MAIN
  DEFER INTERRUPT
  OPTIONS
    INPUT WRAP,
    ACCEPT KEY CONTROL-I,
    PROMPT LINES LAST-1

  CALL STARTLOG("/safre/exc/logs/EXCB100.log")
  WHENEVER ERROR CALL graba_logs_err  

  CALL Sca_Valida(1)

  CALL Sca_Valida(2)

  CALL inicializa()

  #DISPLAY 'INICIO REVERSO DEVOLUCION DE PAGOS EN EXCESO'
  #DISPLAY 'FOLIO A REVERSAR :',gfolio

  CALL reverso_desmarca()
  CALL rever_exc_arch()
  CALL Genera_rep()
  CALL envia_mail()

  LET vch_letrero = "Programa : ",
                    r_sesion.privilegio using "<<<<&",
                    " - ", programa clipped,
                    "  finaliza correctamente "

  CALL Graba_Log('2002', '1', vch_letrero, " ", " ", TRUE)

  #DISPLAY 'FIN REVERSO DEVOLUCION DE PAGOS EXCESO IMSS'

END MAIN
##############################################################################

FUNCTION inicializa()

  SELECT *, USER INTO g_param_exc.*, g_user
    FROM safre_af:seg_modulo
   WHERE modulo_cod = "exc"

  LET gfolio        = ARG_VAL(1)
  LET ghoy          = TODAY
  LET g_ruta        = g_param_exc.ruta_rescate
  LET g_ctas_dsmrca = 0
  LET g_tot_cza     = 0 
  LET g_tot_det     = 0 
  LET g_tot_dep     = 0 
  LET g_tot_sum     = 0 
  LET g_tot_sdo     = 0
  LET g_tot_pcs     = 0 
  LET g_tot_cza_bor = 0 
  LET g_tot_det_bor = 0 
  LET g_tot_dep_bor = 0 
  LET g_tot_sum_bor = 0 
  LET g_tot_sdo_bor = 0
  LET g_tot_pcs_bor = 0 

END FUNCTION
##############################################################################


##############################################################################
FUNCTION reverso_desmarca()
  DEFINE fecha_rec         DATE,
         nss_find          CHAR(11),
         curp_find         CHAR(18),
         lrg_dsmca RECORD
           nss             CHAR(11),
           clave_ent_orig  CHAR(3),
           consec_reg_lote INTEGER
         END RECORD,
         lmarca_entra      SMALLINT,
         lconse_mrca       INTEGER,
         lcodigo_marca     SMALLINT,
         lcodigo_rechazo   SMALLINT

  --- Inicia desmarca de cuentas de los diagnosticos 01 Aceptadas 
  --- y parciales 04
  DECLARE cur_dev_dsmrca CURSOR FOR 
  SELECT UNIQUE  nss, clave_ent_orig, consec_reg_lote   
    FROM exc_det_devpgo
   WHERE folio = gfolio
     AND diag_devolucion IN ("01","04")
  FOREACH cur_dev_dsmrca INTO lrg_dsmca.nss, lrg_dsmca.clave_ent_orig,
                              lrg_dsmca.consec_reg_lote

    IF lrg_dsmca.clave_ent_orig = '001' THEN
       LET lmarca_entra = 540
    END IF

    IF lrg_dsmca.clave_ent_orig = '002' THEN
       LET lmarca_entra = 542
    END IF

    LET g_ejecuta = "EXECUTE PROCEDURE desmarca_cuenta (?,?,?,?,?)"

    LET g_ejecuta = g_ejecuta CLIPPED

    PREPARE sq_dsmrca FROM g_ejecuta

    DECLARE cur_dsmrca CURSOR FOR sq_dsmrca 

    OPEN cur_dsmrca USING gfolio,
                          lrg_dsmca.consec_reg_lote,    --Se toma de archivo
                                                        --lconse_mrca,
                          lrg_dsmca.nss,
                          lmarca_entra,
                          g_user

      FETCH cur_dsmrca INTO lcodigo_marca, lcodigo_rechazo

    CLOSE cur_dsmrca
    
    LET g_ctas_dsmrca = g_ctas_dsmrca + 1 

  END FOREACH
     
END FUNCTION

FUNCTION rever_exc_arch()
  DEFINE ltot_cza     SMALLINT,
         ltot_det     INTEGER,
         ltot_dep     SMALLINT,
         ltot_sum     SMALLINT,
         ltot_sdo     INTEGER,
         ltot_ctrl    SMALLINT

  LET ltot_cza  = 0 
  LET ltot_det  = 0 
  LET ltot_dep  = 0 
  LET ltot_sum  = 0 
  LET ltot_sdo  = 0
  LET ltot_ctrl = 0 

  ---Obtiene el total de registros a borrar en exc_cza_exceso
  LET g_tot_cza = 0
  SELECT COUNT(*) INTO g_tot_cza
    FROM exc_cza_exceso
   WHERE folio = gfolio

  IF g_tot_cza IS NULL THEN
     LET g_tot_cza = 0
  END IF

  ---Elimina folio de encabezado  01
  DELETE FROM exc_cza_exceso WHERE folio = gfolio
  
  LET ltot_cza = 0
  SELECT COUNT(*) INTO ltot_cza 
    FROM exc_cza_exceso
   WHERE folio = gfolio 

  IF ltot_cza IS NULL THEN
     LET ltot_cza = 0
  END IF
  
  LET g_tot_cza_bor = g_tot_cza - ltot_cza 

  ---Obtiene el total de registros a borrar en exc_det_devpgo
  LET g_tot_det = 0 
  SELECT COUNT(*) INTO g_tot_det
    FROM exc_det_devpgo
   WHERE folio = gfolio 

  IF g_tot_det IS NULL THEN
     LET g_tot_det = 0
  END IF

  ---Elimina folio de detalle    02
  DELETE FROM exc_det_devpgo WHERE folio = gfolio
 
  ---Verifica si existe registros en exc_det_devpgo 
  LET ltot_det = 0 
  SELECT COUNT(*) INTO ltot_det
    FROM exc_det_devpgo
   WHERE folio = gfolio 

  IF ltot_det IS NULL THEN
     LET ltot_det = 0
  END IF

  LET g_tot_det_bor = g_tot_det - ltot_det

  ---Obtiene el total de registros a borrar en exc_dep_devpgo
  LET g_tot_dep = 0 
  SELECT COUNT(*) INTO g_tot_dep 
    FROM exc_dep_devpgo
   WHERE folio = gfolio 

  IF g_tot_dep IS NULL THEN
     LET g_tot_dep = 0
  END IF

  ---Elimina folio de dep        08
  DELETE FROM exc_dep_devpgo WHERE folio = gfolio
 
  ---Verifica si existe registros en exc_dep_devpgo 
  LET ltot_dep  = 0  
  SELECT COUNT(*) INTO ltot_dep
    FROM exc_dep_devpgo
   WHERE folio = gfolio 

  IF ltot_dep IS NULL THEN
     LET ltot_dep = 0
  END IF

  LET g_tot_dep_bor = g_tot_dep - ltot_dep


  ---Obtiene el total de registros a borrar en exc_sum_devpgo
  LET g_tot_sum = 0 
  SELECT COUNT(*) INTO g_tot_sum 
    FROM exc_sum_devpgo
   WHERE folio = gfolio 

  IF g_tot_sum IS NULL THEN
     LET g_tot_sum = 0
  END IF

  ---Elimina folio de sumario    08
  DELETE FROM exc_sum_devpgo WHERE folio = gfolio
 
  ---Verifica si existe registros en exc_sum_devpgo 
  LET ltot_sum  = 0   
  SELECT COUNT(*) INTO ltot_sum
    FROM exc_sum_devpgo
   WHERE folio = gfolio 

  IF ltot_sum IS NULL THEN
     LET ltot_sum = 0
  END IF

  LET g_tot_sum_bor = g_tot_sum - ltot_sum

  ---Obtiene el total de registros a borrar en safre_tmp:exc_devpgo_sdo
  LET g_tot_sdo = 0 
  SELECT COUNT(*) INTO g_tot_sdo 
    FROM safre_tmp:exc_devpgo_sdo
   WHERE folio = gfolio 

  IF g_tot_sdo IS NULL THEN
     LET g_tot_sdo = 0
  END IF

  ---Elimina folio del detalle de los importes aceptados, parciales, 
  ---rechazados y pendientes 
  DELETE FROM safre_tmp:exc_devpgo_sdo WHERE folio = gfolio
 
  ---Verifica si existe registros en safre_tmp:exc_devpgo_sdo
  LET ltot_sdo  = 0   
  SELECT COUNT(*) INTO ltot_sdo
    FROM safre_tmp:exc_devpgo_sdo
   WHERE folio = gfolio 

  IF ltot_sdo IS NULL THEN
     LET ltot_sdo = 0
  END IF

  LET g_tot_sdo_bor = g_tot_sdo - ltot_sdo 

  ---Obtiene el total de registros a borrar en dis_ctrl_proceso    
  LET g_tot_pcs = 0
  SELECT COUNT(*) INTO g_tot_pcs
    FROM dis_ctrl_proceso
   WHERE folio       = gfolio
     AND proceso_cod = 'EXC'

  IF g_tot_pcs IS NULL THEN
     LET g_tot_pcs = 0
  END IF

  ---Elimina folio del control de procesos 
  DELETE FROM dis_ctrl_proceso WHERE folio       = gfolio
                                 AND proceso_cod = 'EXC'
 
  ---Verifica si existe registros en dis_ctrl_proceso        
  LET ltot_ctrl = 0   
  SELECT COUNT(*) INTO ltot_ctrl
    FROM dis_ctrl_proceso 
   WHERE folio        = gfolio 
     AND proceso_cod  = 'EXC'

  IF ltot_ctrl IS NULL THEN
     LET ltot_ctrl = 0
  END IF

  LET g_tot_pcs_bor = g_tot_pcs - ltot_ctrl

END FUNCTION


##############################################################################
FUNCTION Genera_rep()

  LET g_nomb_rpt = "/CC_ReversoSIDECOIMSS_",ghoy USING "DDMMYY"

  LET g_lista = g_param_exc.ruta_listados CLIPPED,g_nomb_rpt CLIPPED,".txt" 

  START REPORT listado_ctas TO g_lista
    OUTPUT TO REPORT listado_ctas()
  FINISH REPORT listado_ctas

END FUNCTION
##############################################################################

FUNCTION envia_mail()
  DEFINE lcadena_mail CHAR(550),
         lejecuta     CHAR(250),
         l_arch       CHAR(100)


  { LET lcadena_mail = NULL
  LET lcadena_mail = ' Renata.reynoso@mx.ing.com ',
                     'IrmaRuth.escudero@mx.ing.com ',
                     'MarthaAlicia.sosa@mx.ing.com '
  
  #LET lcadena_mail = ' Pedro.Jimenez@mx.ing.com '  #Solo desa

  LET lejecuta = NULL
  LET lejecuta = ' mailx -s "Informe de reverso  dev pago "',
                 lcadena_mail CLIPPED, " < ", g_lista CLIPPED 
  }
  LET lejecuta = "sh /safre/est/shells/env_mail_gral.sh ",
                 "Informe/de/reverso/dev/pago ",
                 g_nomb_rpt CLIPPED," ","txt"," ",
                 g_param_exc.ruta_listados CLIPPED," ",
                 programa CLIPPED
                     

  RUN lejecuta

END FUNCTION


REPORT listado_ctas()

   OUTPUT
    PAGE   LENGTH  90
    LEFT   MARGIN   0
    RIGHT  MARGIN 160
    TOP    MARGIN   0
    BOTTOM MARGIN   0

  FORMAT

    PAGE HEADER

     PRINT COLUMN  1,  'EXCB100',
           COLUMN  12, 'SURA  AFORE',
           COLUMN  50, TODAY  USING "DD/MM/YYYY",
           COLUMN  65, 'PAGINA',
           COLUMN  72, PAGENO USING "#####"
     PRINT COLUMN  05, 'REVERSO CARGA ARCHIVO SOLICITUDES DE DEVOLUCION DE'
     PRINT COLUMN  25, 'PAGOS EN EXCESO IMSS'
     PRINT
     PRINT
     PRINT
     PRINT COLUMN 005, 'FOLIO REVERSADO : ',gfolio USING "####,###,###" 
     PRINT
     PRINT COLUMN 005, 'DETALLE DE LOS REGISTROS REVERSADOS'
     PRINT 
     PRINT COLUMN 005, 'Encabezado : ',g_tot_cza, ' / ',g_tot_cza_bor,
                       ' registros '
     PRINT COLUMN 005, 'Detalle 02 : ',g_tot_det, ' / ',g_tot_det_bor,
                       ' registros '
     PRINT COLUMN 005, 'Detalle 08 : ',g_tot_dep,' / ',g_tot_dep_bor,
                       ' registros '
     PRINT COLUMN 005, 'Sumario    : ',g_tot_sum,' / ',g_tot_sum_bor,
                       ' registros '
     PRINT 
     PRINT COLUMN 005, 'Saldos y diagnosticos : ',g_tot_sdo, ' / ',
                       g_tot_sdo_bor,' registros '  

     PRINT COLUMN 005, 'Etapas del proceso : ', g_tot_pcs,' / ',
                       g_tot_pcs_bor, ' registros '


END REPORT
##############################################################################

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
         LET vin_priv_ini = 3731                            ---EXCB100
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
