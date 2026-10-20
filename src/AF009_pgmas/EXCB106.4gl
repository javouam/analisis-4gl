#*****************************************************************************#
#Programa          => EXCB106                                                 #
#  Marzo 2011      => DEVOLUCION DE PAGOS EN EXCESO LIQUIDACION. RQ19435_PJF  #
#  Diciembre 2014  => Omitir siefore 5. RQ21718_PJF                           #
#*****************************************************************************#
###############################################################################
# Diciembre 2014 => Cambiar diagnostico PENDIENTE por Rechazos, omitir siefore#
#                   5 y notificar en detalle 08 del archivo de envio solo     #
#                   cuando existan rechazos. RQ21718_PJF                      #
###############################################################################
# Diciembre 2015 => Integrar funcion fn_precio_dia y validar siefore por      #
#                   catalogo tc_siefore_local. RQ25372_PJF                    #
###############################################################################
# Modifico MEFH TDF      05/07/2019                                           #
###############################################################################
DATABASE safre_af

GLOBALS
   DEFINE g_bat         RECORD LIKE dis_ctrl_proceso.*,
          g_reg         RECORD LIKE dis_cuenta.*,
          gparam_dev    RECORD LIKE seg_modulo.*,
          gusuario            CHAR(08),
          generar1            DATE,
          generar2            CHAR(10),
          generar3            INTEGER,
          g_ruta              CHAR(200),
          g_nomb_arc          CHAR(50),
          g_fc_rcv            DATE, 
          g_fc_viv            DATE,
          g_siefore           SMALLINT,
          g_sc                SMALLINT,
          g_accs              DECIMAL(19,6),
          g_pesos             DECIMAL(19,2),
          g_tm                SMALLINT,
          vparametro1         CHAR(3),
          vparametro2         INTEGER,
          gtotsieacep         INTEGER,
          g_sol_imss   ARRAY[999] OF RECORD
            rech_diag           INTEGER,
            rech_impt           DECIMAL(16,2)
          END RECORD,
          g_sol_info   ARRAY[999] OF RECORD
            rech_diag           INTEGER,
            rech_impt           DECIMAL(16,2)
          END RECORD,
          g_soltot              INTEGER,
          g_sol001              INTEGER,
          g_sol001_acep         INTEGER,
          g_sol001_rej          INTEGER,
          g_sol001_par          INTEGER,
          g_sol002              INTEGER,
          g_sol002_acep         INTEGER,
          g_sol002_rej          INTEGER,
          g_sol002_par          INTEGER,
          g_sol_acep            INTEGER,
          g_sol_rej             INTEGER,
          g_sol_par             INTEGER

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

  CALL STARTLOG("/safre/exc/logs/EXCB106.log")
  WHENEVER ERROR CALL graba_logs_err

  CALL Sca_Valida(1)

  LET vparametro1 = ARG_VAL(1)
  LET vparametro2 = ARG_VAL(2)
   
  CALL Sca_Valida(2)

  CALL inicializa()
  CALL Proceso()
  CALL cif_resumen()
  CALL envia_mail(1)
  CALL cif_con_imp()
  CALL envia_mail(2)

  LET vch_letrero = "Programa : ",
                    r_sesion.privilegio using "<<<<&",
                    " - ", programa clipped,
                    "  finaliza correctamente "
  CALL Graba_Log('2002', '1', vch_letrero, " ", " ", TRUE)

END MAIN
#*********************************************************************

FUNCTION inicializa()

  SELECT *, USER  INTO  gparam_dev.*, gusuario
    FROM seg_modulo
   WHERE modulo_cod = "exc"

END FUNCTION
#*********************************************************************

FUNCTION Proceso()
  DEFINE cla_sel      CHAR(500),
         lresultado   CHAR(50)

  LET cla_sel = " SELECT * ",
                  " FROM dis_ctrl_proceso ",
                 " WHERE folio = ",vparametro2,
                   " AND proceso_cod = 'EXC' ",
                   " AND etapa_cod = 5 "        -- ETAPA 5

  PREPARE claexe2 FROM cla_sel

  DECLARE cur_proceso2 CURSOR FOR claexe2

  OPEN cur_proceso2
    FETCH cur_proceso2 INTO g_bat.*
  CLOSE cur_proceso2

  LET generar1 = g_bat.parametro1 CLIPPED
  LET generar2 = g_bat.parametro2 CLIPPED
  LET generar3 = g_bat.folio CLIPPED

  ---Realiza el diagnostico con fecha de precio del dia actual
  CALL validacion(generar3)

  CALL Proceso_principal(generar1,
                         generar2,
                         generar3)

  LET lresultado = "Terminada liquidacion dev. pagos en exceso"

  CALL Actualiza_etapa(generar3,5,lresultado)

  DISPLAY  "PROCESO TERMINADO DE PAGOS EN EXCESO"

END FUNCTION
#*********************************************************************

FUNCTION Proceso_principal(lfecha,lorigen,lfolio)
  DEFINE lfecha              DATE,
         lorigen             CHAR(10),
         lfolio              INTEGER,
         lrg_liq        RECORD  
           nss               CHAR(11),
           subcuenta         SMALLINT,
           tipo_movimiento   SMALLINT,
           siefore           SMALLINT,
           conse_lote        INTEGER,
           imp_dis_pesos     DECIMAL(16,6),
           imp_dis_accion    DECIMAL(22,6),
           precio_accion     DECIMAL(22,6),
           id_aportante      CHAR(11)
         END RECORD,
         lmarca_entra        SMALLINT,
         lmarca_cod          SMALLINT,
         lrechazo_cod        SMALLINT


  DECLARE cur_liq CURSOR FOR
  SELECT nss, subcuenta, tipo_movimiento, siefore, conse_lote,
         imp_dis_pesos, imp_dis_accion, precio_accion,  id_aportante
    FROM safre_tmp:exc_devpgo_sdo
   WHERE folio         = lfolio
     AND diagnostico  IN (1,4)
     AND imp_dis_pesos > 0
  ORDER BY nss, subcuenta, tipo_movimiento, id_aportante 
  FOREACH cur_liq INTO lrg_liq.nss,
                       lrg_liq.subcuenta,
                       lrg_liq.tipo_movimiento,
                       lrg_liq.siefore,
                       lrg_liq.conse_lote,
                       lrg_liq.imp_dis_pesos,
                       lrg_liq.imp_dis_accion,
                       lrg_liq.precio_accion,
                       lrg_liq.id_aportante

    IF lrg_liq.subcuenta = 4 THEN
       LET lmarca_entra   = 542
    ELSE
       LET lmarca_entra   = 540
    END IF

    LET lrg_liq.imp_dis_pesos  = lrg_liq.imp_dis_pesos * -1 
    LET lrg_liq.imp_dis_accion = lrg_liq.imp_dis_accion * -1

    INSERT INTO dis_cuenta VALUES(lrg_liq.tipo_movimiento,  
                                  lrg_liq.subcuenta,
                                  lrg_liq.siefore,
                                  lfolio,
                                  lrg_liq.conse_lote,          
                                  lrg_liq.nss,
                                  NULL,                     #CURP 
                                  NULL,                     #FOLIO_SUA 
                                  TODAY,                    #FECHA_PAGO
                                  TODAY,                    #FECHA_VALOR
                                  TODAY,                    #FECHA_CONVERSION
                                  lrg_liq.imp_dis_pesos,
                                  lrg_liq.imp_dis_accion,
                                  lrg_liq.precio_accion,
                                  "0",
                                  NULL,
                                  lrg_liq.id_aportante,
                                  "6",                      #ESTADO
                                  TODAY,                    #FECHA_PROCESO
                                  gusuario, 
                                  TODAY,                    #FECHA_ARCHIVO
                                  "1"                       #ETIQUETA
                                  )

    CALL des_marca(lfolio,              -- folio
                   lrg_liq.conse_lote,  -- consecutivo
                   lrg_liq.nss,         -- nss
                   lmarca_entra,        -- marca_entra
                   gusuario             -- usuario
                  )
                  RETURNING lmarca_cod,lrechazo_cod

  END FOREACH

END FUNCTION
#*********************************************************************

FUNCTION Actualiza_etapa(lfolio,letapa_cod,lresultado)
  DEFINE lfolio       INTEGER,
         letapa_cod   DECIMAL(2,0),
         lresultado   CHAR(50),
         lhora_max    CHAR(08),
         lhora_final  CHAR(08),
         lcla_sel     CHAR(500)

   LET lcla_sel = " SELECT MAX(hora_inicial) ",
                 " FROM   dis_ctrl_proceso ",
                 " WHERE  folio = ",lfolio,
                 " AND    proceso_cod = 'EXC' ",
                 " AND    etapa_cod = ",letapa_cod

   PREPARE claexe6 FROM lcla_sel

   DECLARE cur_proceso6 CURSOR FOR claexe6

   OPEN cur_proceso6
      FETCH cur_proceso6 INTO lhora_max
   CLOSE cur_proceso6

   LET lhora_final   = TIME

   LET lcla_sel = " UPDATE dis_ctrl_proceso ",
                  " SET    hora_final = ","'",lhora_final,"',",
                  "        folio      = ",lfolio,",",
                  "        resultado  = ","'",lresultado,"'",
                  " WHERE  folio = ",lfolio,
                  " AND    proceso_cod   = 'EXC'",
                  " AND    etapa_cod     = ",letapa_cod,
                  " AND    hora_inicial  = ","'",lhora_max,"'" CLIPPED

   PREPARE claexe7 FROM lcla_sel

   EXECUTE claexe7

END FUNCTION
#******************************************************************************

FUNCTION cif_resumen()
  DEFINE lreg  RECORD
           cve_ent_orig CHAR(03),
           diag         CHAR(02),
           rsult_ope    SMALLINT,
           total        INTEGER,
           imp_imss     DECIMAL(16,2),
           imp_infov    DECIMAL(16,2)
         END RECORD,
         li             SMALLINT,
         lrsult_ope     SMALLINT

  FOR li = 1 TO 999
    LET g_sol_imss[li].rech_diag   = 0
    LET g_sol_imss[li].rech_impt   = 0
    LET g_sol_info[li].rech_diag   = 0
    LET g_sol_info[li].rech_impt   = 0
  END FOR

  SELECT COUNT(*) INTO g_soltot             # solicitudes procesadas
    FROM exc_det_devpgo
   WHERE folio = generar3

  SELECT COUNT(*) INTO g_sol001             # solicitudes imss
    FROM exc_det_devpgo
   WHERE folio = generar3
     AND clave_ent_orig = '001'
  
  SELECT COUNT(*) INTO g_sol002              # solicitudes infonavit
    FROM exc_det_devpgo
   WHERE folio = generar3
     AND clave_ent_orig = '002'

  SELECT COUNT(*) INTO g_sol001_acep         # solicitudes imss acep
    FROM exc_det_devpgo
   WHERE folio = generar3
     AND clave_ent_orig  = '001'
     AND diag_devolucion = '01'

  SELECT COUNT(*) INTO g_sol001_rej         # solicitudes imss recha
    FROM exc_det_devpgo
   WHERE folio = generar3
     AND clave_ent_orig  = '001'
     AND diag_devolucion = '02'

  SELECT COUNT(*) INTO   g_sol001_par       # solicitudes imss parciales
    FROM exc_det_devpgo
   WHERE folio = generar3
     AND clave_ent_orig   = '001'
     AND diag_devolucion  = '04'

  LET g_nomb_arc = "excb6_rsmn"
  LET g_ruta = gparam_dev.ruta_rescate CLIPPED,"/",g_nomb_arc CLIPPED,".txt"
  START REPORT r_report TO g_ruta

  #solicitudes imss rechazadas por diagnostico
  DECLARE cc_001_02 CURSOR FOR
  SELECT clave_ent_orig, diag_devolucion, motivo_devolucion, COUNT(*),
         SUM(monto_ret        +
             monto_act_ret    +
             imp_rnd_ret_indv +
             monto_cv_pat     +
             monto_act_cv_pat +
             monto_act_cv_pat +
             monto_cuo_soc),                            #Total imp IMSS
         SUM(monto_apor_pat_viv)                        #Total imp INFONAVIT
    FROM exc_det_devpgo
   WHERE folio           = generar3
     AND diag_devolucion = '02'
  GROUP BY clave_ent_orig, diag_devolucion, motivo_devolucion
  ORDER BY clave_ent_orig, diag_devolucion, motivo_devolucion
  FOREACH  cc_001_02 INTO lreg.cve_ent_orig,
                          lreg.diag,
                          lreg.rsult_ope,
                          lreg.total,
                          lreg.imp_imss,
                          lreg.imp_infov

    LET lrsult_ope = lreg.rsult_ope

    IF lreg.cve_ent_orig = '001' THEN   #Solicitudes dev pagos IMSS
       LET g_sol_imss[lrsult_ope].rech_diag = lreg.total
       LET g_sol_imss[lrsult_ope].rech_impt = lreg.imp_imss
    END IF

    IF lreg.cve_ent_orig = '002' THEN   #Solicitudes dev pagos INFONAVIT
       LET g_sol_info[lrsult_ope].rech_diag = lreg.total
       LET g_sol_info[lrsult_ope].rech_impt = lreg.imp_infov
    END IF

  END FOREACH

  SELECT COUNT(*) INTO g_sol002_acep       # solicitudes infonavit acep
    FROM exc_det_devpgo
   WHERE folio = generar3
     AND clave_ent_orig   = '002'
     AND diag_devolucion  = '01'

  SELECT COUNT(*) INTO g_sol002_rej        # solicitudes infonavit recha
    FROM exc_det_devpgo
   WHERE folio = generar3
     AND clave_ent_orig   = '002'
     AND diag_devolucion  = '02'

  SELECT COUNT(*) INTO g_sol002_par        # solicitudes infonavit parciales
    FROM exc_det_devpgo
   WHERE folio = generar3
     AND clave_ent_orig   = '002'
     AND diag_devolucion  = '04'

  LET g_sol_acep = g_sol001_acep + g_sol002_acep
  LET g_sol_rej  = g_sol001_rej  + g_sol002_rej
  LET g_sol_par  = g_sol001_par  + g_sol002_par

  OUTPUT TO REPORT r_report()
  FINISH REPORT r_report  

END FUNCTION

FUNCTION cif_con_imp()
  DEFINE lreg     RECORD
           siefore          SMALLINT,
           fecha_conversion DATE,
           precio_accion    DECIMAL(19,6)
         END RECORD,
         lsiefore_ant       SMALLINT,
         lsemafo_sie        SMALLINT,
         lejecuta           CHAR(500),
         lciclo             SMALLINT

  DISPLAY "Cifras de Control"

  #RQ25372_PJF
  LET lciclo = 1
  LET g_nomb_arc   = "excb6_cc_cza"
  LET g_ruta = gparam_dev.ruta_rescate CLIPPED,"/",g_nomb_arc CLIPPED,".txt"
  START REPORT p_report_cza TO g_ruta
  
  DECLARE cur_dtosliq CURSOR FOR
  SELECT UNIQUE siefore, fecha_conversion, precio_accion 
    FROM dis_cuenta
   WHERE folio    = generar3
  ORDER BY siefore, fecha_conversion
  FOREACH cur_dtosliq INTO lreg.siefore, lreg.fecha_conversion,
                           lreg.precio_accion 
    OUTPUT TO REPORT p_report_cza(lreg.*,lciclo)
    LET lciclo = lciclo + 1
  END FOREACH

  FINISH REPORT p_report_cza
  #RQ25372_PJF

  LET lsiefore_ant = NULL
  LET lsemafo_sie  = 0
  LET gtotsieacep  = 0
  LET g_nomb_arc   = "excb6_cc_det"
  LET g_ruta = gparam_dev.ruta_rescate CLIPPED,"/",g_nomb_arc CLIPPED,".txt"

  START REPORT p_report_det TO g_ruta

  DECLARE dp_001 CURSOR FOR
  SELECT siefore,
         subcuenta,
         SUM(monto_en_acciones),
         SUM(monto_en_pesos),
         tipo_movimiento 
    FROM dis_cuenta
   WHERE folio   = generar3 
  GROUP BY 1,2,5
  ORDER BY 1,2,5
  FOREACH dp_001 INTO  g_siefore,
                       g_sc,
                       g_accs,
                       g_pesos,
                       g_tm

    IF lsiefore_ant IS NULL THEN
       LET lsemafo_sie = 1
    ELSE
       IF lsiefore_ant <> g_siefore THEN
          LET lsemafo_sie = 1
       END IF
    END IF

    IF lsemafo_sie = 1 THEN 

       SELECT COUNT(UNIQUE nss) INTO gtotsieacep
         FROM dis_cuenta 
        WHERE folio   = generar3 
          AND siefore = g_siefore

    END IF

    OUTPUT TO REPORT p_report_det()

    LET lsemafo_sie  = 0
    LET lsiefore_ant = g_siefore
    LET gtotsieacep  = 0

  END FOREACH

  FINISH REPORT p_report_det

  LET g_nomb_arc   = "excb006_cc"
  LET lejecuta = NULL
  LET lejecuta = " cat ",gparam_dev.ruta_rescate CLIPPED,"/excb6_cc_cza.txt ",
                         gparam_dev.ruta_rescate CLIPPED,"/excb6_cc_det.txt > ",
                         gparam_dev.ruta_rescate CLIPPED,"/excb006_cc.txt"
  RUN lejecuta

END FUNCTION

FUNCTION envia_mail(lrpt_num)
  DEFINE lrpt_num SMALLINT,
         lejecuta CHAR(250),
         lasunto  CHAR(100)

  CASE lrpt_num
    WHEN 1
      LET lasunto = "Informe/liquidacion/dev/pago/resumen/de/cifras"
    WHEN 2
      LET lasunto = "Informe/liquidacion/dev/pago/importes/por/siefore"
  END CASE

  LET lejecuta = "sh /safre/est/shells/env_mail_gral.sh ",lasunto CLIPPED," ",
                 g_nomb_arc CLIPPED," ","txt"," ",
                 gparam_dev.ruta_rescate CLIPPED," ", 
                 programa CLIPPED
                 
  RUN lejecuta

END FUNCTION 

REPORT r_report()
  DEFINE ri SMALLINT

  OUTPUT
    PAGE LENGTH  90
    LEFT MARGIN  0
    RIGHT MARGIN 160
    TOP   MARGIN 0
    BOTTOM MARGIN 0

  FORMAT
    PAGE HEADER
      PRINT COLUMN   1, 'EXCB106',
            COLUMN  12, '        SURA AFORE',
            COLUMN  50, TODAY  USING "DD/MM/YYYY",
            COLUMN  65, 'PAGINA',
            COLUMN  72, PAGENO USING "#####"
      PRINT COLUMN  05, 'CIFRAS DEVOLUCION DE PAGOS SIN JUSTIFICACION LEGAL',
                        '(LIQUIDACION)'
      PRINT COLUMN  05, 'FOLIO : ',generar3 USING "#########"
      PRINT

    ON EVERY  ROW
      PRINT
      PRINT COLUMN  01, "Solicitudes recibidas....",
            COLUMN  30, g_soltot USING "###,###,##&"

      PRINT COLUMN  01, "    IMSS.................",
            COLUMN  30, g_sol001 USING "###,###,##&"

      PRINT COLUMN  01, "    INFONAVIT...........",
            COLUMN  30, g_sol002 USING "###,###,##&"
      PRINT

      PRINT COLUMN  01, "Solicitudes aceptadas....",
            COLUMN  30, g_sol_acep USING "###,###,##&"
      PRINT COLUMN  01, "    IMSS.................",
            COLUMN  30, g_sol001_acep USING "###,###,##&"
      PRINT COLUMN  01, "    INFONAVIT...........",
            COLUMN  30, g_sol002_acep USING "###,###,##&"
      PRINT
      
      PRINT COLUMN  01, "Solicitudes rechazadas...",
            COLUMN  30, g_sol_rej  USING "###,###,##&"
      PRINT COLUMN  01, "    IMSS.................",
            COLUMN  30, g_sol001_rej  USING "###,###,##&"
      PRINT COLUMN  01, "    INFONAVIT...........",
            COLUMN  30, g_sol002_rej  USING "###,###,##&"
      PRINT

      PRINT COLUMN  01, "Solicitudes parciales ...",
            COLUMN  30, g_sol_par  USING "###,###,##&"
      PRINT COLUMN  01, "    IMSS.................",
            COLUMN  30, g_sol001_par  USING "###,###,##&"
      PRINT COLUMN  01, "    INFONAVIT...........",
            COLUMN  30, g_sol002_par  USING "###,###,##&"
      PRINT

      PRINT COLUMN  01, "Solicitudes IMSS rechazadas por diagnostico"
      PRINT COLUMN 001, "Diagnostico",
            COLUMN 020, "Cantidad",
            COLUMN 040, "Importe"

      FOR ri=1 TO 999
        IF g_sol_imss[ri].rech_diag > 0 THEN
           PRINT COLUMN 001, ri     using "&&&",
                 COLUMN 004,"...............",
                 COLUMN 020, g_sol_imss[ri].rech_diag using "###,###,##&",
                 COLUMN 040, g_sol_imss[ri].rech_impt using "#,###,##&.&&"
        END IF
      END FOR
      PRINT

      PRINT COLUMN  01, "Solicitudes INFONAVIT rechazadas por diagnostico"
      PRINT COLUMN 001, "Diagnostico",
            COLUMN 020, "Cantidad",
            COLUMN 040, "Importe"

      FOR ri=1 TO 999
        IF g_sol_info[ri].rech_diag > 0 THEN
           PRINT COLUMN 001, ri     using "&&&",
                 COLUMN 004,"...............",
                 COLUMN 020, g_sol_info[ri].rech_diag using "###,###,##&",
                 COLUMN 040, g_sol_info[ri].rech_impt using "#,###,##&.&&"
        END IF
      END FOR

END REPORT

REPORT p_report_cza(rreg,rciclo)
  DEFINE rreg     RECORD
           siefore          SMALLINT,
           fecha_conversion DATE,
           precio_accion    DECIMAL(19,6)
         END RECORD,
         rciclo             SMALLINT

  OUTPUT

    PAGE   LENGTH   4
    LEFT   MARGIN   0
    RIGHT  MARGIN   0
    TOP    MARGIN   0
    BOTTOM MARGIN   0

  FORMAT
    ON EVERY  ROW

      IF rciclo = 1 THEN
         PRINT COLUMN  1,  'EXCB106',
               COLUMN  12, 'SURA  AFORE',
               COLUMN  50, TODAY  USING "DD/MM/YYYY",
               COLUMN  65, 'PAGINA',
               COLUMN  72, PAGENO USING "#####"
         PRINT COLUMN  05, 'CIFRAS DEVOLUCION DE PAGOS SIN JUSTIFICACION LEGAL'
         PRINT COLUMN 005, 'Importes liquidados del folio : ',
                           generar3 USING "#########"
      END IF

      PRINT COLUMN 010, "Precio S",  rreg.siefore USING "##&",
                        " ", rreg.precio_accion USING "#&.######",
                        " Fecha precio : ", 
                        rreg.fecha_conversion USING "DD/MM/YYYY" 
END REPORT

REPORT p_report_det()

  OUTPUT
    PAGE   LENGTH  90
    LEFT   MARGIN   0
    RIGHT  MARGIN 160
    TOP    MARGIN   0
    BOTTOM MARGIN   0

  FORMAT

    PAGE HEADER
      PRINT
      PRINT COLUMN 001, "SIEFORE",
            COLUMN 009, "SUBCTA",
            COLUMN 016, "T.MOVTO",
            COLUMN 024, "TOT_NSS",
            COLUMN 033, "   TITULOS   ",
            COLUMN 053, "    PESOS    "
      PRINT
    ON EVERY  ROW
      PRINT COLUMN 001, g_siefore    USING "###&",
            COLUMN 011, g_sc         USING "#&",
            COLUMN 018, g_tm         USING "###",
            COLUMN 024, gtotsieacep  USING "###,###",
            COLUMN 033, g_accs       USING "###,###,##&.&&&&&&",
            COLUMN 053, g_pesos      USING "$$$,$$$,$$&.&&"

END REPORT
######################################################################

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
         LET vin_priv_ini = 3733  ----EXCB106
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
